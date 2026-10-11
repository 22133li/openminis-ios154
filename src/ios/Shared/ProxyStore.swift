import Foundation

/// App-wide HTTP/SOCKS5 proxy settings behind Settings → Proxy.
///
/// When enabled, `AppNetwork.shared` routes through the proxy and the
/// ISH terminal gets `http_proxy`/`https_proxy`/`all_proxy` env vars.
/// Note: WKWebView (in-app browser) cannot take a per-app proxy on iOS —
/// it always follows the system proxy settings. The settings page says so.
enum ProxyStore {
    enum ProxyType: String, CaseIterable {
        case http = "http"
        case socks5 = "socks5"

        var title: String {
            switch self {
            case .http: return "HTTP"
            case .socks5: return "SOCKS5"
            }
        }
    }

    private static let enabledKey = "proxyEnabled"
    private static let typeKey = "proxyType"
    private static let hostKey = "proxyHost"
    private static let portKey = "proxyPort"

    static let defaultPort = 7890

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var type: ProxyType {
        get {
            let raw = UserDefaults.standard.string(forKey: typeKey) ?? ""
            return ProxyType(rawValue: raw) ?? .http
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: typeKey) }
    }

    static var host: String {
        get { UserDefaults.standard.string(forKey: hostKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: hostKey) }
    }

    static var port: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: portKey)
            return v > 0 ? v : defaultPort
        }
        set { UserDefaults.standard.set(max(1, min(65535, newValue)), forKey: portKey) }
    }

    /// True when the proxy should actually be used.
    static var isActive: Bool {
        isEnabled && !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Cache-buster key for AppNetwork's session.
    static var configKey: String {
        "\(isEnabled)-\(type.rawValue)-\(host)-\(port)"
    }

    /// Dictionary for URLSessionConfiguration.connectionProxyDictionary.
    /// Nil when the proxy is not active.
    static var proxyDictionary: [AnyHashable: Any]? {
        guard isActive else { return nil }
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case .http:
            return [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: h,
                kCFNetworkProxiesHTTPPort as String: port,
                kCFNetworkProxiesHTTPSEnable as String: true,
                kCFNetworkProxiesHTTPSProxy as String: h,
                kCFNetworkProxiesHTTPSPort as String: port,
            ]
        case .socks5:
            return [
                kCFNetworkProxiesSOCKSEnable as String: true,
                kCFNetworkProxiesSOCKSProxy as String: h,
                kCFNetworkProxiesSOCKSPort as String: port,
            ]
        }
    }

    /// Env vars for shell sessions (ISH terminal): http_proxy / https_proxy /
    /// all_proxy. Empty when the proxy is not active.
    static var proxyEnvironment: [String: String] {
        guard isActive else { return [:] }
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let url: String
        switch type {
        case .http: url = "http://\(h):\(port)"
        case .socks5: url = "socks5://\(h):\(port)"
        }
        return [
            "http_proxy": url,
            "https_proxy": url,
            "all_proxy": url,
            "HTTP_PROXY": url,
            "HTTPS_PROXY": url,
            "ALL_PROXY": url,
        ]
    }
}

/// Central URLSession that honors ProxyStore.
///
/// Drop-in replacement for `URLSession.shared` in app code that should go
/// through the user's proxy. When the proxy is off it behaves like a default
/// session. The session is rebuilt when the proxy config changes.
enum AppNetwork {
    private static let lock = NSLock()
    private static var cachedSession: URLSession?
    private static var cachedKey: String?

    static var shared: URLSession {
        lock.lock()
        defer { lock.unlock() }
        let key = ProxyStore.configKey
        if let s = cachedSession, cachedKey == key { return s }
        let config = URLSessionConfiguration.default
        config.applyProxySettings()
        let s = URLSession(configuration: config)
        cachedSession = s
        cachedKey = key
        return s
    }
}

extension URLSessionConfiguration {
    /// Applies ProxyStore's proxy to this configuration. No-op when the
    /// proxy is not active.
    func applyProxySettings() {
        if let dict = ProxyStore.proxyDictionary {
            connectionProxyDictionary = dict
        }
    }
}
