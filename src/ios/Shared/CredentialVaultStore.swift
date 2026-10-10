import Foundation
import Security

private let vaultLogger = AppLogger(category: "CredentialVault")

// MARK: - VaultEntry

/// Metadata for one vault secret. The VALUE lives in the Keychain only —
/// this struct (persisted to credential-vault.json) never carries it.
struct VaultEntry: Identifiable, Codable {
    let id: String
    var name: String
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Custom decoder so older entries missing newer fields still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()
    }
}

// MARK: - CredentialVaultStore

/// The user's credential vault — the Minis equivalent of the assistant's
/// Secure Vault: named secrets (API tokens, passwords) stored in the iOS
/// Keychain, managed in Settings → Credential Vault, and usable by the
/// agent only through the approval-gated `vault_use_secret` tool.
///
/// Security properties (mirror EnvVarStore):
/// - values: Keychain kSecClassGenericPassword, synchronizable, never in JSON
/// - metadata JSON carries id/name/note/dates only
/// - init performs no main-thread IO (iOS 15.4 watchdog-safe)
/// - writes use update-in-place (no delete-then-add data-loss window)
/// - every mutation drops the vault redactor cache so a new/changed secret
///   is masked in tool output from the very next call
@MainActor
final class CredentialVaultStore: ObservableObject {
    static let shared = CredentialVaultStore()

    @Published private(set) var entries: [VaultEntry] = []

    /// Keychain service for vault values. Mirrored by EnvVarRedactor's
    /// vault loader — keep the two in sync.
    nonisolated static let keychainService = "com.openminis.app.credentialvault"
    nonisolated static let fileName = "credential-vault.json"

    private var fileURL: URL

    /// Entry ids the user approved for agent use during the CURRENT turn.
    /// A `let` box so nonisolated readers (ISH runner) can reach it: `var`
    /// state on a @MainActor class is not visible off the main actor.
    private let turnApprovals = TurnApprovals()

    nonisolated static func vaultFileURL() -> URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        let baseURL = (libraryURL ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("MinisChat", isDirectory: true)
        return baseURL.appendingPathComponent(fileName)
    }

    init() {
        // No file IO on the main thread: init with a provisional URL, load
        // for real in the background (same watchdog-safe pattern as
        // EnvVarStore — the iOS 15.4 SIGKILL fix).
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        let baseURL = (libraryURL ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("MinisChat", isDirectory: true)
        self.fileURL = baseURL.appendingPathComponent(Self.fileName)
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let url = Self.vaultFileURL()
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let loaded = Self.loadEntries(from: url)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.fileURL = url
                self.entries = loaded
            }
        }
    }

    // MARK: - Lookups

    func entry(id: String) -> VaultEntry? {
        entries.first { $0.id == id }
    }

    func entry(named name: String) -> VaultEntry? {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return entries.first { $0.name.compare(t, options: .caseInsensitive) == .orderedSame }
    }

    /// Shell-visible name for an entry, e.g. "GitHub Token" -> "VAULT_GITHUB_TOKEN".
    /// Deterministic so the agent can reference it after approval. ASCII-only:
    /// anything else becomes "_" (a CJK name must not produce an invalid var).
    /// Pure function: no actor state, safe to call off the main actor.
    nonisolated static func envVarName(for entry: VaultEntry) -> String {
        var s = entry.name.uppercased().map { ch -> String in
            let v = ch.asciiValue
            if let v, (v >= 65 && v <= 90) || (v >= 48 && v <= 57) { return String(ch) }
            return "_"
        }.joined()
        while s.contains("__") { s = s.replacingOccurrences(of: "__", with: "_") }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if s.isEmpty { s = "SECRET" }
        if s.count > 48 { s = String(s.prefix(48)) }
        return "VAULT_" + s
    }

    // MARK: - Mutations

    /// Add a new secret. Returns the entry, or nil when the name is blank /
    /// duplicate or the value is empty / failed to persist.
    @discardableResult
    func add(name: String, value: String, note: String) -> VaultEntry? {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !value.isEmpty, entry(named: t) == nil else { return nil }
        let e = VaultEntry(
            name: t,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard Self.saveValue(value, forAccount: e.id) else { return nil }
        entries.append(e)
        saveEntries()
        return e
    }

    /// Update name/note, and optionally replace the value (nil/empty = keep).
    /// Returns false when the entry is missing, the name is blank/duplicate,
    /// or the new value failed to persist (old value left intact).
    @discardableResult
    func update(id: String, name: String, value: String?, note: String) -> Bool {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return false }
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        if let other = entry(named: t), other.id != id { return false }
        if let v = value, !v.isEmpty {
            guard Self.saveValue(v, forAccount: id) else { return false }
        }
        entries[idx].name = t
        entries[idx].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[idx].updatedAt = Date()
        saveEntries()
        return true
    }

    func delete(id: String) {
        entries.removeAll { $0.id == id }
        Self.deleteValue(forAccount: id)
        turnApprovals.remove(id)
        saveEntries()
    }

    // MARK: - Turn-scoped agent access

    /// Grant the agent use of this entry for the rest of the current turn.
    /// Called only after explicit per-use user approval.
    func approveForTurn(id: String) {
        turnApprovals.insert(id)
    }

    /// Env dict of turn-approved secrets, for injection into shell_execute.
    /// Nonisolated: called from the ISH runner off the main thread.
    nonisolated func envForApprovedTurn() -> [String: String] {
        let ids = turnApprovals.snapshot()
        guard !ids.isEmpty else { return [:] }
        let entries = Self.loadEntries(from: Self.vaultFileURL())
        var out: [String: String] = [:]
        for e in entries where ids.contains(e.id) {
            if let v = Self.loadValue(forAccount: e.id), !v.isEmpty {
                out[Self.envVarName(for: e)] = v
            }
        }
        return out
    }

    /// Drop all turn approvals. Called when the user sends a new message
    /// (turn boundary) so a grant never leaks into the next turn.
    func endTurn() {
        turnApprovals.removeAll()
    }

    /// All current values, for the always-on vault redactor. Nonisolated.
    nonisolated static func allValuesForRedaction() -> [String] {
        let entries = loadEntries(from: vaultFileURL())
        return entries.compactMap { loadValue(forAccount: $0.id) }.filter { !$0.isEmpty }
    }

    // MARK: - Persistence (metadata JSON)

    /// Pure file read: nonisolated so the background loader and the
    /// ISH runner can call it without a main-actor hop.
    nonisolated private static func loadEntries(from url: URL) -> [VaultEntry] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([VaultEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private func saveEntries() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            vaultLogger.error("Failed to save vault entries: \(error)")
        }
        // A new/changed/removed secret must be (un)masked from the very
        // next tool output.
        EnvVarRedactor.invalidateVaultCache()
    }

    // MARK: - Keychain (values)

    /// Persist a value under the entry id. Update-in-place first, add only
    /// when missing, update on duplicate race — the old value is never
    /// deleted before the new one lands (same anti-blanking pattern as
    /// EnvVarStore.saveValue).
    @discardableResult
    nonisolated private static func saveValue(_ value: String, forAccount account: String) -> Bool {
        let syncMatch: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        var status = SecItemUpdate(syncMatch as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = syncMatch
            addQuery.merge(attrs) { _, new in new }
            status = SecItemAdd(addQuery as CFDictionary, nil)
            if status == errSecDuplicateItem {
                status = SecItemUpdate(syncMatch as CFDictionary, attrs as CFDictionary)
            }
        }

        if status == errSecSuccess {
            EnvVarRedactor.invalidateVaultCache()
            return true
        }
        vaultLogger.error("Keychain vault save failed for account \(account): OSStatus \(status) — prior value left intact")
        return false
    }

    /// One fresh `result` per SecItemCopyMatching (Copy rule — never reuse
    /// the out-pointer across calls; see EnvVarStore.loadValue).
    nonisolated private static func loadValue(forAccount account: String) -> String? {
        func copyData(_ query: [String: Any]) -> Data? {
            var result: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
            return result as? Data
        }
        let syncQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let data = copyData(syncQuery) { return String(data: data, encoding: .utf8) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        guard let data = copyData(query) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated private static func deleteValue(forAccount account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var syncQuery = query
        syncQuery[kSecAttrSynchronizable as String] = true
        SecItemDelete(syncQuery as CFDictionary)
        EnvVarRedactor.invalidateVaultCache()
    }

    /// Non-isolated read for the reveal UI (called after Face ID auth).
    nonisolated static func loadValueSync(forId id: String) -> String? {
        loadValue(forAccount: id)
    }
}

// MARK: - TurnApprovals

/// Lock-guarded set of vault entry ids approved for the current turn.
/// `@unchecked Sendable` + NSLock: the guarded value is a plain Set, and
/// every access goes through the lock — the same shape as
/// ProviderCredentialCache.
private final class TurnApprovals: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<String> = []

    func insert(_ id: String) {
        lock.withLock { _ = ids.insert(id) }
    }

    func remove(_ id: String) {
        lock.withLock { _ = ids.remove(id) }
    }

    func removeAll() {
        lock.withLock { ids.removeAll() }
    }

    func snapshot() -> Set<String> {
        lock.withLock { ids }
    }
}

// MARK: - Vault access approval

/// One pending agent request to use a vault secret.
struct VaultAccessRequest: Identifiable {
    let id: String
    let entryName: String
    let envVarName: String
    let purpose: String
    let toolTitle: String
    let continuation: CheckedContinuation<Bool, Never>
}

/// Per-use user approval for agent vault access. Mirrors
/// OffloadPermissionManager's pending-request + sheet pattern, but every
/// grant is single-turn by construction — there is deliberately no
/// "ask once per session" bypass for secrets.
@MainActor
final class CredentialVaultAccessManager: ObservableObject {
    static let shared = CredentialVaultAccessManager()

    @Published var pendingRequest: VaultAccessRequest?

    private init() {}

    /// Ask the user whether the agent may use `entry` for `purpose`.
    /// Returns true on explicit approval, false on deny or 60s timeout.
    /// The sheet is non-dismissable: the user must choose.
    func requestAccess(entry: VaultEntry, envVarName: String, purpose: String, toolTitle: String) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let request = VaultAccessRequest(
                id: UUID().uuidString,
                entryName: entry.name,
                envVarName: envVarName,
                purpose: purpose,
                toolTitle: toolTitle,
                continuation: continuation
            )
            self.pendingRequest = request
            // 60s timeout: secrets are higher-stakes than shell commands,
            // so the user gets longer than the 30s offload window.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if self.pendingRequest?.id == request.id {
                    self.pendingRequest = nil
                    continuation.resume(returning: false)
                }
            }
        }
    }

    func respond(to requestId: String, allowed: Bool) {
        guard let request = pendingRequest, request.id == requestId else { return }
        pendingRequest = nil
        request.continuation.resume(returning: allowed)
    }
}
