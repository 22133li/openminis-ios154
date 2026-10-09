// FileProviderExtension.swift
// iOS 15-compatible FileProvider extension (classic NSFileProviderExtension API).
//
// Why this exists: the upstream OpenMinis app uses NSFileProviderReplicatedExtension
// (iOS 16+). On iOS 15.4 the extension never loads, so the "Files" app shows nothing.
// This port re-implements the provider on the classic NSFileProviderExtension API
// (iOS 11+) so memory/skills/shared appear in Files on iOS 15.
//
// Identifier scheme (unchanged from the replicated implementation):
//   identifier.rawValue == providerRoot-relative path, e.g. "shared/notes/todo.md".
//   .rootContainer maps to the virtual root listing memory/, skills/, shared/.
// providerRoot is the App Group MinisFileProvider directory (source of truth);
// the system-managed document storage holds materialized files + placeholders.

import FileProvider
import UniformTypeIdentifiers
import os.log

final class FileProviderExtension: NSFileProviderExtension {

    static let log = OSLog(subsystem: "com.openminis.app", category: "FileProvider15")

    /// App Group source of truth: MinisFileProvider/{memory,skills,shared}/.
    /// Mirrors the replicated implementation's providerRoot resolution exactly.
    static var providerRoot: URL = {
        let fm = FileManager.default
        if let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.openminis.app") {
            let root = groupURL.appendingPathComponent("MinisFileProvider", isDirectory: true)
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
            try? fm.createDirectory(at: root.appendingPathComponent("memory", isDirectory: true), withIntermediateDirectories: true)
            try? fm.createDirectory(at: root.appendingPathComponent("skills", isDirectory: true), withIntermediateDirectories: true)
            try? fm.createDirectory(at: root.appendingPathComponent("shared", isDirectory: true), withIntermediateDirectories: true)
            cleanupLegacyMountedFoldersIfNeeded(root: root)
            recoverFakeTrashDirIfNeeded(root: root)
            return root
        }
        // Fallback: never crash the extension if the App Group is unavailable.
        let fallback = fm.temporaryDirectory.appendingPathComponent("MinisFileProvider", isDirectory: true)
        try? fm.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }()

    /// The three fixed top-level folders exposed under the root.
    private static let topLevelSubdirs = ["memory", "skills", "shared"]

    override init() {
        super.init()
        // Touch providerRoot so directories exist before first enumeration.
        _ = Self.providerRoot
        FPSyncTraceLog.log("FileProviderExtension(classic,iOS15) init providerRoot=\(Self.providerRoot.path)")
        FileProviderBootHealth.recordSuccessfulBoot(generation: "classic-ios15")
    }

    // MARK: - Legacy cleanup (unchanged from replicated implementation)

    /// Remove the old `mounted-folders.json` left at providerRoot by builds that
    /// stored it there before the canonical location became `MinisConfig/`.
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

    /// Map a document-storage URL back to its item identifier.
    /// Identifier scheme is unchanged from the replicated implementation:
    /// identifier.rawValue == providerRoot-relative path.
    private func identifierForDocumentURL(_ url: URL) -> NSFileProviderItemIdentifier? {
        let base = NSFileProviderManager.default.documentStorageURL.standardized.path
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

    override func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem {
        os_log("item(for: %{public}@)", log: Self.log, type: .debug, identifier.rawValue)
        if identifier == .rootContainer {
            return FileProviderItem(url: Self.providerRoot, parentIdentifier: .rootContainer, isRoot: true)
        }
        // Note: .trashContainer is iOS 16+; the classic provider on iOS 15 has no
        // trash container. Unknown identifiers simply report noSuchItem.
        let url = Self.providerRoot.appendingPathComponent(identifier.rawValue)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSFileProviderError(.noSuchItem)
        }
        let parentPath = (identifier.rawValue as NSString).deletingLastPathComponent
        let parentID: NSFileProviderItemIdentifier = parentPath.isEmpty
            ? .rootContainer
            : NSFileProviderItemIdentifier(parentPath)
        return FileProviderItem(url: url, parentIdentifier: parentID)
    }

    // MARK: - URL mapping

    override func urlForItem(withPersistentIdentifier identifier: NSFileProviderItemIdentifier) -> URL? {
        let docStorage = NSFileProviderManager.default.documentStorageURL
        if identifier == .rootContainer {
            return docStorage
        }
        if identifier == .workingSet {
            return nil
        }
        return docStorage.appendingPathComponent(identifier.rawValue)
    }

    // Note: persistentIdentifierForItem(at:) is intentionally NOT overridden.
    // The default implementation returns the path relative to documentStorageURL,
    // which exactly matches our identifier scheme (identifier.rawValue ==
    // documentStorageURL-relative path).

    // MARK: - Providing items

    override func providePlaceholder(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        guard let identifier = identifierForDocumentURL(url) else {
            completionHandler(NSFileProviderError(.noSuchItem))
            return
        }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // placeholderURL(for:) is deprecated since iOS 11 but remains the
            // working API for classic providers; the replacement lives on
            // NSFileProviderManager in newer SDKs.
            let placeholderURL = NSFileProviderExtension.placeholderURL(for: url)
            if fm.fileExists(atPath: placeholderURL.path) {
                try fm.removeItem(at: placeholderURL)
            }
            let item: NSFileProviderItem
            if identifier == .rootContainer {
                item = FileProviderItem(url: Self.providerRoot,
                                        parentIdentifier: .rootContainer,
                                        isRoot: true)
            } else {
                let sourceURL = Self.providerRoot.appendingPathComponent(identifier.rawValue)
                if fm.fileExists(atPath: sourceURL.path) {
                    // Existing item — placeholder from real metadata.
                    item = try self.item(for: identifier)
                } else if Self.canCreate(atRelativePath: identifier.rawValue) {
                    // New item under shared/ — materialize an empty file in
                    // providerRoot first so identifier <-> path stays consistent,
                    // then write the placeholder from its metadata.
                    var isDir: ObjCBool = false
                    let preCreatedDir = fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
                    if preCreatedDir {
                        try fm.createDirectory(at: sourceURL, withIntermediateDirectories: true)
                    } else {
                        fm.createFile(atPath: sourceURL.path, contents: nil)
                    }
                    item = try self.item(for: identifier)
                    self.signalParent(of: identifier)
                } else {
                    throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
                }
            }
            try NSFileProviderManager.writePlaceholder(at: placeholderURL, withMetadata: item)
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
        if identifier == .rootContainer {
            completionHandler(nil)
            return
        }
        let fm = FileManager.default
        let sourceURL = Self.providerRoot.appendingPathComponent(identifier.rawValue)
        guard fm.fileExists(atPath: sourceURL.path) else {
            completionHandler(NSFileProviderError(.noSuchItem))
            return
        }
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Replace any placeholder with the real file content.
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
            try fm.copyItem(at: sourceURL, to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    override func itemChanged(at url: URL) {
        // The host app finished a coordinated write; sync the bytes back into
        // the App Group source of truth. Read-only subtrees are not writable
        // through Files (capabilities say so), but guard anyway.
        guard let identifier = identifierForDocumentURL(url) else { return }
        guard !identifier.rawValue.isEmpty else { return } // never the root
        guard Self.isWritable(relativePath: identifier.rawValue) else { return }
        let fm = FileManager.default
        let sourceURL = Self.providerRoot.appendingPathComponent(identifier.rawValue)
        do {
            try fm.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: sourceURL.path) {
                try fm.removeItem(at: sourceURL)
            }
            try fm.copyItem(at: url, to: sourceURL)
            os_log("itemChanged synced %{public}@ -> providerRoot", log: Self.log, type: .debug, identifier.rawValue)
            signalParent(of: identifier)
        } catch {
            os_log("itemChanged sync failed %{public}@: %{public}@", log: Self.log, type: .error,
                   identifier.rawValue, error.localizedDescription)
        }
    }

    override func stopProvidingItem(at url: URL) {
        // Keep materialized files; storage pressure is not a concern for this
        // small on-device dataset. Nothing to evict.
    }

    // MARK: - Enumeration

    override func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier) throws -> NSFileProviderEnumerator {
        switch containerItemIdentifier {
        case .rootContainer:
            return FileProviderEnumerator(containerItemIdentifier: .rootContainer)
        case .workingSet:
            throw NSFileProviderError(.noSuchItem)
        default:
            break
        }
        // Validate that the container is a real directory under providerRoot.
        let url = Self.providerRoot.appendingPathComponent(containerItemIdentifier.rawValue)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw NSFileProviderError(.noSuchItem)
        }
        return FileProviderEnumerator(containerItemIdentifier: containerItemIdentifier)
    }
}
