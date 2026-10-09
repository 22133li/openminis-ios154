import FileProvider
import UniformTypeIdentifiers
import os.log

/// Classic File Provider extension (NSFileProviderExtension, iOS 11+) that exposes
/// MinisFileProvider/ to the system Files app.
/// Structure: Minis → { memory, skills, shared }
///
/// iOS 15-compatible implementation. The classic API has no domain concept and no
/// explicit create/modify/delete callbacks — the App Group directory (providerRoot)
/// is the source of truth, and the extension materializes files into its document
/// storage on demand.
///
/// Write support: edits to existing files sync back via itemChanged(at:); new
/// files/folders can be created under shared/; memory/ and skills/ are read-only.
/// Deletions made in Files do NOT propagate (the file reappears on next
/// enumeration) — the classic API offers no delete callback, and
/// stopProvidingItem(at:) signals cache eviction, not user deletes, so it must
/// not touch providerRoot.
final class FileProviderExtension: NSFileProviderExtension {

    private static let log = OSLog(subsystem: "com.openminis.app.FileProvider", category: "Extension")

    /// Root directory for all FileProvider-visible files in the App Group container.
    static var providerRoot: URL {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.openminis.app"
        ) ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let url = container.appendingPathComponent("MinisFileProvider", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The three top-level subdirectories exposed via the FileProvider.
    static let topLevelSubdirs = ["memory", "skills", "shared"]

    override init() {
        super.init()
        let fm = FileManager.default
        let root = Self.providerRoot
        for sub in Self.topLevelSubdirs {
            try? fm.createDirectory(at: root.appendingPathComponent(sub, isDirectory: true),
                                    withIntermediateDirectories: true)
        }
        os_log("FileProviderExtension init — providerRoot: %{public}@",
               log: Self.log, type: .info, root.path)

        let resolvedRoot = root.resolvingSymlinksInPath().path
        var rootSummaries: [String] = []
        for sub in Self.topLevelSubdirs {
            let dir = root.appendingPathComponent(sub, isDirectory: true)
            let count = (try? fm.contentsOfDirectory(atPath: dir.path).count) ?? -1
            rootSummaries.append("\(sub)=\(count)")
        }
        // [T-ios-fp-mac-bootcrash] Stamp every SUCCESSFUL launch with the app
        // version and the executable's mtime. See the replicated-extension
        // implementation history for the full rationale.
        let bundle = Bundle.main
        let ver = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        var execStamp = "?"
        if let execURL = bundle.executableURL,
           let mod = (try? fm.attributesOfItem(atPath: execURL.path))?[.modificationDate] as? Date {
            execStamp = ISO8601DateFormatter().string(from: mod)
        }
        let onMac = ProcessInfo.processInfo.isiOSAppOnMac
        FPSyncTraceLog.log("init classic ver=\(ver)(\(build)) exec=\(execStamp) mac=\(onMac) providerRoot=\(root.path) resolved=\(resolvedRoot) [\(rootSummaries.joined(separator: " "))]")

        // Liveness heartbeat for the main app's circuit breaker.
        FileProviderBootHealth.recordSuccessfulBoot(generation: execStamp)

        Self.recoverFakeTrashDirIfNeeded(root: root)
        Self.cleanupLegacyLogsDirIfNeeded(root: root)
        Self.cleanupLegacyMountedFoldersIfNeeded(root: root)
    }

    /// Delete leftover FileProvider extension log directories (see replicated
    /// implementation for the two historical locations).
    private static func cleanupLegacyLogsDirIfNeeded(root: URL) {
        let fm = FileManager.default
        let inProvider = root.appendingPathComponent("logs", isDirectory: true)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: inProvider.path, isDirectory: &isDir), isDir.boolValue {
            try? fm.removeItem(at: inProvider)
        }
        if let container = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.openminis.app") {
            let inConfig = container.appendingPathComponent("MinisConfig/logs", isDirectory: true)
            if fm.fileExists(atPath: inConfig.path, isDirectory: &isDir), isDir.boolValue {
                try? fm.removeItem(at: inConfig)
            }
        }
    }

    /// Delete a residual `mounted-folders.json` that the main app already
    /// migrated to `MinisConfig/`.
    private static func cleanupLegacyMountedFoldersIfNeeded(root: URL) {
        let fm = FileManager.default
        let legacy = root.appendingPathComponent("mounted-folders.json")
        guard fm.fileExists(atPath: legacy.path) else { return }
        guard let container = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.openminis.app") else { return }
        let canonical = container.appendingPathComponent("MinisConfig/mounted-folders.json")
        if fm.fileExists(atPath: canonical.path) {
            try? fm.removeItem(at: legacy)
        }
    }

    /// Clean up any leftover `NSFileProviderTrashContainerItemIdentifier`
    /// directory under providerRoot (see replicated implementation).
    private static func recoverFakeTrashDirIfNeeded(root: URL) {
        let fm = FileManager.default
        let fakeTrash = root.appendingPathComponent("NSFileProviderTrashContainerItemIdentifier", isDirectory: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: fakeTrash.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }
        let recovered = root.appendingPathComponent("shared/_recovered_trash", isDirectory: true)
        do {
            try fm.createDirectory(at: recovered, withIntermediateDirectories: true)
        } catch {
            return
        }
        if let entries = try? fm.contentsOfDirectory(atPath: fakeTrash.path) {
            for name in entries {
                let src = fakeTrash.appendingPathComponent(name)
                var dst = recovered.appendingPathComponent(name)
                var n = 1
                while fm.fileExists(atPath: dst.path) {
                    let ext = (name as NSString).pathExtension
                    let base = (name as NSString).deletingPathExtension
                    let candidate = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
                    dst = recovered.appendingPathComponent(candidate)
                    n += 1
                }
                try? fm.moveItem(at: src, to: dst)
            }
        }
        try? fm.removeItem(at: fakeTrash)
    }

    // MARK: - Document storage mapping

    /// System-managed document storage for this extension. Materialized files live here;
    /// providerRoot (App Group) remains the source of truth.
    private var documentStorageURL: URL {
        NSFileProviderManager.default.documentStorageURL
    }

    /// Map a document-storage URL back to its item identifier.
    /// Identifier scheme is unchanged from the replicated implementation:
    /// identifier.rawValue == providerRoot-relative path.
    private func identifierForDocumentURL(_ url: URL) -> NSFileProviderItemIdentifier? {
        let base = documentStorageURL.standardized.path
        let path = url.standardized.path
        guard path.hasPrefix(base) else { return nil }
        let relative = String(path.dropFirst(base.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if relative.isEmpty { return .rootContainer }
        return NSFileProviderItemIdentifier(relative)
    }

    /// Whether a new item may be created at the given providerRoot-relative path.
    /// Only shared/ (and its subdirectories) is writable; root, memory/, skills/
    /// are fixed/read-only.
    private static func canCreate(atRelativePath relativePath: String) -> Bool {
        guard !relativePath.isEmpty else { return false }
        let first = relativePath.split(separator: "/").first.map(String.init) ?? ""
        return first == "shared"
    }

    /// Whether the existing item at the given providerRoot-relative path may be
    /// modified. Mirrors the replicated implementation's guards.
    private static func isWritable(relativePath: String) -> Bool {
        if topLevelSubdirs.contains(relativePath) { return false }
        if relativePath == "memory" || relativePath == "skills" { return false }
        if relativePath.hasPrefix("memory/") || relativePath.hasPrefix("skills/") { return false }
        return true
    }

    /// Signal the parent enumerator to re-list after a local change.
    private func signalParent(of identifier: NSFileProviderItemIdentifier) {
        let raw = identifier.rawValue
        let parentPath = (raw as NSString).deletingLastPathComponent
        let parentID: NSFileProviderItemIdentifier =
            parentPath.isEmpty ? .rootContainer : NSFileProviderItemIdentifier(parentPath)
        NSFileProviderManager.default.signalEnumerator(for: parentID) { error in
            if let error {
                os_log("signalEnumerator(%{public}@) error: %{public}@",
                       log: Self.log, type: .error,
                       parentID.rawValue, error.localizedDescription)
            }
        }
    }

    // MARK: - Item lookup

    override func item(for identifier: NSFileProviderItemIdentifier,
                       completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) {
        os_log("item(for: %{public}@)", log: Self.log, type: .debug, identifier.rawValue)
        if identifier == .rootContainer {
            completionHandler(FileProviderItem(url: Self.providerRoot, parentIdentifier: .rootContainer, isRoot: true), nil)
            return
        }
        if identifier == .trashContainer {
            completionHandler(nil, NSFileProviderError(.noSuchItem))
            return
        }
        let url = Self.providerRoot.appendingPathComponent(identifier.rawValue)
        guard FileManager.default.fileExists(atPath: url.path) else {
            completionHandler(nil, NSFileProviderError(.noSuchItem))
            return
        }
        let parentPath = (identifier.rawValue as NSString).deletingLastPathComponent
        let parentID = parentPath.isEmpty
            ? NSFileProviderItemIdentifier.rootContainer
            : NSFileProviderItemIdentifier(parentPath)
        completionHandler(FileProviderItem(url: url, parentIdentifier: parentID), nil)
    }

    // MARK: - URL mapping

    override func urlForItem(withPersistentIdentifier identifier: NSFileProviderItemIdentifier,
                             completionHandler: @escaping (URL?, Error?) -> Void) {
        if identifier == .rootContainer {
            completionHandler(documentStorageURL, nil)
            return
        }
        if identifier == .trashContainer || identifier == .workingSet {
            completionHandler(nil, NSFileProviderError(.noSuchItem))
            return
        }
        completionHandler(documentStorageURL.appendingPathComponent(identifier.rawValue), nil)
    }

    override func persistentIdentifierForItem(at url: URL,
                                              completionHandler: @escaping (NSFileProviderItemIdentifier?, Error?) -> Void) {
        guard let identifier = identifierForDocumentURL(url) else {
            completionHandler(nil, NSFileProviderError(.noSuchItem))
            return
        }
        completionHandler(identifier, nil)
    }

    // MARK: - Providing items

    override func providePlaceholder(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        guard let identifier = identifierForDocumentURL(url) else {
            completionHandler(NSFileProviderError(.noSuchItem))
            return
        }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let placeholderURL = NSFileProviderExtension.placeholderURL(for: url)
            if fm.fileExists(atPath: placeholderURL.path) {
                try fm.removeItem(at: placeholderURL)
            }
            if identifier == .rootContainer {
                try writePlaceholder(at: placeholderURL,
                                     withMetadata: FileProviderItem(url: Self.providerRoot,
                                                                    parentIdentifier: .rootContainer,
                                                                    isRoot: true))
            } else {
                let sourceURL = Self.providerRoot.appendingPathComponent(identifier.rawValue)
                if fm.fileExists(atPath: sourceURL.path) {
                    // Existing item — placeholder from real metadata.
                    item(for: identifier) { item, error in
                        if let item {
                            do {
                                try self.writePlaceholder(at: placeholderURL, withMetadata: item)
                                completionHandler(nil)
                            } catch {
                                completionHandler(error)
                            }
                        } else {
                            completionHandler(error ?? NSFileProviderError(.noSuchItem))
                        }
                    }
                    return
                } else if Self.canCreate(atRelativePath: identifier.rawValue) {
                    // New item under shared/ — materialize an empty file in
                    // providerRoot first so identifier ↔ path stays consistent,
                    // then write the placeholder from its metadata.
                    // (Directory creation via Files pre-creates the dir in
                    // document storage; detect that and mirror it.)
                    var isDir: ObjCBool = false
                    let preCreatedDir = fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
                    if preCreatedDir {
                        try fm.createDirectory(at: sourceURL, withIntermediateDirectories: true)
                    } else {
                        fm.createFile(atPath: sourceURL.path, contents: nil)
                    }
                    item(for: identifier) { item, error in
                        if let item {
                            do {
                                try self.writePlaceholder(at: placeholderURL, withMetadata: item)
                                completionHandler(nil)
                            } catch {
                                completionHandler(error)
                            }
                        } else {
                            completionHandler(error ?? NSFileProviderError(.noSuchItem))
                        }
                    }
                    self.signalParent(of: identifier)
                    return
                } else {
                    completionHandler(NSError(domain: NSCocoaErrorDomain,
                                              code: NSFileWriteNoPermissionError))
                    return
                }
            }
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    override func startProvidingItem(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        guard let identifier = identifierForDocumentURL(url) else {
            completionHandler(NSFileProviderError(.noSuchItem))
            return
        }
        let fm = FileManager.default
        let sourceURL: URL
        if identifier == .rootContainer {
            sourceURL = Self.providerRoot
        } else {
            sourceURL = Self.providerRoot.appendingPathComponent(identifier.rawValue)
        }
        do {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir) else {
                completionHandler(NSFileProviderError(.noSuchItem))
                return
            }
            // Remove any stale file at the destination, then materialize.
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if isDir.boolValue {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try fm.copyItem(at: sourceURL, to: url)
            }
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    override func itemChanged(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        guard let identifier = identifierForDocumentURL(url),
              identifier != .rootContainer else {
            completionHandler(nil)
            return
        }
        let relativePath = identifier.rawValue
        guard Self.isWritable(relativePath: relativePath) else {
            // Read-only tree — revert the document-storage copy from providerRoot.
            let sourceURL = Self.providerRoot.appendingPathComponent(relativePath)
            let fm = FileManager.default
            if fm.fileExists(atPath: sourceURL.path) {
                try? fm.removeItem(at: url)
                try? fm.copyItem(at: sourceURL, to: url)
            }
            completionHandler(nil)
            return
        }
        let sourceURL = Self.providerRoot.appendingPathComponent(relativePath)
        let fm = FileManager.default
        do {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                if fm.fileExists(atPath: sourceURL.path) {
                    try fm.removeItem(at: sourceURL)
                }
                try fm.createDirectory(at: sourceURL.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                try fm.copyItem(at: url, to: sourceURL)
                signalParent(of: identifier)
            }
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    override func stopProvidingItem(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        // Cache eviction only — never touch providerRoot here. A user delete in
        // Files removes the document-storage copy without a callback; the item
        // reappears on next enumeration (documented limitation).
        completionHandler(nil)
    }

    // MARK: - Enumeration

    override func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier) throws -> NSFileProviderEnumerator {
        os_log("enumerator(for: %{public}@)", log: Self.log, type: .info, containerItemIdentifier.rawValue)
        switch containerItemIdentifier {
        case .rootContainer:
            return FileProviderEnumerator(containerItemIdentifier: .rootContainer)
        case .workingSet:
            return FileProviderEnumerator(containerItemIdentifier: .rootContainer, recursive: true)
        case .trashContainer:
            return FileProviderEnumerator(containerItemIdentifier: .trashContainer)
        default:
            return FileProviderEnumerator(containerItemIdentifier: containerItemIdentifier)
        }
    }
}
