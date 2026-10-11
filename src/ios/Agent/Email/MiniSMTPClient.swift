import Foundation
import Network

/// Minimal SMTP client for the agent's `send_email` tool: implicit TLS
/// (port 465) + AUTH LOGIN. No third-party dependencies.
///
/// Only the subset SMTP needs is implemented: EHLO, AUTH LOGIN, MAIL FROM,
/// RCPT TO, DATA, QUIT. STARTTLS (port 587) is deliberately not supported —
/// all built-in provider presets use implicit TLS.
enum SMTPError: LocalizedError {
    case connectionFailed(String)
    case unexpectedReply(code: Int, text: String)
    case authFailed
    case timeout

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let s): return "SMTP connection failed: \(s)"
        case .unexpectedReply(let c, let t): return "SMTP error \(c): \(t)"
        case .authFailed: return "SMTP authentication failed (bad username/password)"
        case .timeout: return "SMTP timed out"
        }
    }
}

struct SMTPClient {
    /// Well-known implicit-TLS endpoints keyed by sender domain.
    static func preset(forDomain domain: String) -> (host: String, port: Int)? {
        switch domain.lowercased() {
        case "qq.com": return ("smtp.qq.com", 465)
        case "163.com": return ("smtp.163.com", 465)
        case "126.com": return ("smtp.126.com", 465)
        case "yeah.net": return ("smtp.yeah.net", 465)
        case "gmail.com": return ("smtp.gmail.com", 465)
        case "outlook.com", "hotmail.com", "live.com": return ("smtp-mail.outlook.com", 465)
        case "yahoo.com": return ("smtp.mail.yahoo.com", 465)
        case "icloud.com", "me.com", "mac.com": return ("smtp.mail.me.com", 587)
        default: return nil
        }
    }

    /// Send a plain-text UTF-8 email. `password` is the SMTP auth secret
    /// (e.g. QQ mail "authorization code", not the login password).
    static func send(host: String, port: Int = 465,
                     username: String, password: String,
                     from: String, to: [String],
                     subject: String, body: String,
                     timeout: TimeInterval = 30) async throws {
        let conn = SMTPConnection(host: host, port: port, timeout: timeout)
        try await conn.connect()
        defer { conn.close() }

        // 1. Greeting
        let (greetCode, _) = try await conn.readReply()
        guard (200...299).contains(greetCode) else {
            throw SMTPError.unexpectedReply(code: greetCode, text: "greeting")
        }

        // 2. EHLO
        try await conn.sendLine("EHLO minis")
        let (ehloCode, _) = try await conn.readReply()
        guard (200...299).contains(ehloCode) else {
            throw SMTPError.unexpectedReply(code: ehloCode, text: "EHLO")
        }

        // 3. AUTH LOGIN
        try await conn.sendLine("AUTH LOGIN")
        var (code, _) = try await conn.readReply()
        guard code == 334 else { throw SMTPError.unexpectedReply(code: code, text: "AUTH LOGIN") }
        try await conn.sendLine(Data(username.utf8).base64EncodedString())
        (code, _) = try await conn.readReply()
        guard code == 334 else { throw SMTPError.authFailed }
        try await conn.sendLine(Data(password.utf8).base64EncodedString())
        (code, _) = try await conn.readReply()
        guard (200...299).contains(code) else { throw SMTPError.authFailed }

        // 4. MAIL / RCPT / DATA
        try await conn.sendLine("MAIL FROM:<\(from)>")
        (code, _) = try await conn.readReply()
        guard (200...299).contains(code) else {
            throw SMTPError.unexpectedReply(code: code, text: "MAIL FROM")
        }
        for rcpt in to {
            try await conn.sendLine("RCPT TO:<\(rcpt)>")
            (code, _) = try await conn.readReply()
            guard (200...299).contains(code) else {
                throw SMTPError.unexpectedReply(code: code, text: "RCPT TO \(rcpt)")
            }
        }
        try await conn.sendLine("DATA")
        (code, _) = try await conn.readReply()
        guard code == 354 else { throw SMTPError.unexpectedReply(code: code, text: "DATA") }

        try await conn.sendLine(buildMessage(from: from, to: to, subject: subject, body: body))
        try await conn.sendLine(".")
        (code, _) = try await conn.readReply()
        guard (200...299).contains(code) else {
            throw SMTPError.unexpectedReply(code: code, text: "message body")
        }

        try await conn.sendLine("QUIT")
    }

    // MARK: - Message building

    private static func buildMessage(from: String, to: [String], subject: String, body: String) -> String {
        var lines: [String] = []
        lines.append("From: \(from)")
        lines.append("To: \(to.joined(separator: ", "))")
        lines.append("Subject: \(rfc2047(subject))")
        lines.append("MIME-Version: 1.0")
        lines.append("Content-Type: text/plain; charset=utf-8")
        lines.append("Content-Transfer-Encoding: 8bit")
        lines.append("Date: \(rfc2822Date())")
        lines.append("X-Mailer: Minis")
        lines.append("")
        // Dot-stuffing per RFC 5321 §4.5.2.
        let stuffed = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix(".") ? "." + $0 : String($0) }
            .joined(separator: "\r\n")
        lines.append(stuffed)
        return lines.joined(separator: "\r\n")
    }

    /// RFC 2047 encoded-word for non-ASCII subjects.
    private static func rfc2047(_ s: String) -> String {
        guard s.unicodeScalars.contains(where: { !$0.isASCII }) else { return s }
        return "=?UTF-8?B?\(Data(s.utf8).base64EncodedString())?="
    }

    private static func rfc2822Date() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f.string(from: Date())
    }
}

// MARK: - Line-oriented TLS connection

/// Thin wrapper around NWConnection (.tls) with \r\n line framing and a
/// per-operation timeout. One-shot: connect → dialogue → close.
private final class SMTPConnection {
    private let host: String
    private let port: Int
    private let timeout: TimeInterval
    private var connection: NWConnection?
    private var buffer = Data()
    private let queue = DispatchQueue(label: "minis.smtp")

    init(host: String, port: Int, timeout: TimeInterval) {
        self.host = host
        self.port = port
        self.timeout = timeout
    }

    func connect() async throws {
        let portValue = UInt16(clamping: port)
        let conn = NWConnection(host: NWEndpoint.Host(host),
                                port: NWEndpoint.Port(rawValue: portValue) ?? .https,
                                using: .tls)
        self.connection = conn
        var resumed = false
        try await withThrowingTimeout(seconds: timeout) {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                conn.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard !resumed else { return }
                        resumed = true
                        c.resume()
                    case .failed, .cancelled:
                        // Let the post-await state check produce the error;
                        // guard against a second resume if .ready fired first.
                        guard !resumed else { return }
                        resumed = true
                        c.resume()
                    default: break
                    }
                }
                conn.start(queue: self.queue)
            }
        }
        guard conn.state == .ready else {
            throw SMTPError.connectionFailed("TLS handshake to \(host):\(port) failed (state: \(conn.state))")
        }
    }

    func close() {
        connection?.cancel()
        connection = nil
    }

    func sendLine(_ s: String) async throws {
        guard let conn = connection else { throw SMTPError.connectionFailed("not connected") }
        let data = (s + "\r\n").data(using: .utf8) ?? Data()
        try await withThrowingTimeout(seconds: timeout) {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                conn.send(content: data, completion: .contentProcessed { _ in c.resume() })
            }
        }
    }

    /// Reads one SMTP reply, following multi-line replies (code + "-").
    /// Returns (code, full text).
    func readReply() async throws -> (Int, String) {
        var lines: [String] = []
        while true {
            let line = try await readLine()
            lines.append(line)
            // Multi-line: "250-..." continues, "250 ..." ends.
            if line.count >= 4 {
                let code = String(line.prefix(3))
                let sep = line[line.index(line.startIndex, offsetBy: 3)]
                if sep == " " { break }
                if sep != "-" { break }
                _ = code
            } else { break }
        }
        let text = lines.joined(separator: "\n")
        let code = Int(text.prefix(3)) ?? 0
        return (code, text)
    }

    private func readLine() async throws -> String {
        while true {
            if let range = buffer.range(of: Data("\r\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                return String(data: lineData, encoding: .utf8) ?? ""
            }
            guard let conn = connection else { throw SMTPError.connectionFailed("not connected") }
            let chunk: Data? = try await withThrowingTimeout(seconds: timeout) {
                await withCheckedContinuation { (c: CheckedContinuation<Data?, Never>) in
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                        c.resume(returning: data)
                    }
                }
            }
            guard let chunk, !chunk.isEmpty else {
                throw SMTPError.connectionFailed("server closed connection")
            }
            buffer.append(chunk)
        }
    }
}

/// Runs `op` with a wall-clock timeout.
private func withThrowingTimeout<T>(seconds: TimeInterval, op: @escaping () async -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { await op() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw SMTPError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
