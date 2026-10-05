import UIKit
import SwiftUI
import ObjectiveC
import UserNotifications

private let shareLog = AppLogger(category: "Share")
private let lifecycleLog = AppLogger(category: "Lifecycle")

// MARK: - Bundle Language Override

/// Overrides `Bundle.main.localizedString(forKey:value:table:)` so that
/// `String(localized:)` and UIKit strings respect the in-app language setting
/// without requiring an app restart.
extension Bundle {
    private static var overrideBundleKey: UInt8 = 0

    /// The language-specific `.lproj` bundle currently in use, or `nil` for system default.
    var languageBundle: Bundle? {
        get { objc_getAssociatedObject(self, &Self.overrideBundleKey) as? Bundle }
        set { objc_setAssociatedObject(self, &Self.overrideBundleKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// Call once at launch to swizzle `localizedString(forKey:value:table:)`.
    static func enableLanguageOverride() {
        let original = class_getInstanceMethod(Bundle.self, #selector(localizedString(forKey:value:table:)))!
        let swizzled = class_getInstanceMethod(Bundle.self, #selector(overrideLocalizedString(forKey:value:table:)))!
        method_exchangeImplementations(original, swizzled)
    }

    @objc private func overrideLocalizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if self == Bundle.main, let bundle = languageBundle {
            return bundle.overrideLocalizedString(forKey: key, value: value, table: tableName)
        }
        return overrideLocalizedString(forKey: key, value: value, table: tableName) // calls original (swizzled)
    }

    /// Sets the override language. Pass `nil` or `""` to revert to system language.
    static func setLanguage(_ code: String?) {
        guard let code, !code.isEmpty,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            Bundle.main.languageBundle = nil
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            return
        }
        Bundle.main.languageBundle = bundle
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
    }
}

extension Notification.Name {
    static let newChatRequested = Notification.Name("newChatRequested")
    /// Posted when a new session is persisted to the database. `object` is the session ID (`String`).
    static let sessionDidCreate = Notification.Name("sessionDidCreate")
    /// Posted when a session's title or messages are updated.
    static let sessionDidUpdate = Notification.Name("sessionDidUpdate")
    /// Posted when an agent loop ends on a VM that is not the currently-displayed one.
    /// `object` is the session ID (`String`). Allows the active VM to reload from DB.
    static let sessionAgentLoopDidEnd = Notification.Name("sessionAgentLoopDidEnd")
    /// Posted when the user wants to move input (text + attachments) to another session.
    /// userInfo: ["targetId": String]
    static let moveInputToSession = Notification.Name("moveInputToSession")
    /// Posted when a session's model binding changes (group or direct entry).
    /// userInfo: ["sessionId": String] and optionally ["groupId": String] when bound to a group.
    static let sessionModelBindingChanged = Notification.Name("sessionModelBindingChanged")

    /// Posted by any path that's about to take over the screen (incoming
    /// share, WebApp deep-link launch). Every fullScreenCover host —
    /// AIChatView, the WindowGroup root — listens and dismisses its
    /// covers so the new content actually surfaces instead of getting
    /// stuck behind a leftover WebView / camera / gallery sheet.
    static let dismissAllImmersivePresentations = Notification.Name("dismissAllImmersivePresentations")
}

@main
struct MinisApp: App {
    /// [T-voice-input-mode-preference-ios] Process launch instant, pinned in
    /// the App initializer (Swift statics are lazy — referencing it from
    /// init() makes it accurate). Used to tell a cold-launch LANDING chat
    /// apart from a chat the user navigated into minutes later.
    static let processLaunchedAt = Date()

    // Minimal UIApplicationDelegate adapter — needed only to receive
    // `UIApplicationShortcutItem` events (Home Screen Quick Actions).
    // SwiftUI's pure App lifecycle has no equivalent surface.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0
    @AppStorage("appLanguage") private var appLanguage: String = ""
    @StateObject private var shareCoordinator = ShareCoordinator.shared
    @ObservedObject private var fontSettings = FontSettings.shared
    @ObservedObject private var configConfirmGate = ConfigConfirmationGate.shared
    /// [review S14] Drives the root-level restore sheet for a `.minisbak`
    /// opened from outside the app.
    @ObservedObject private var openRouter = BackupOpenRouter.shared
    /// Observed so the restore sheet re-evaluates when the app locks/unlocks.
    @ObservedObject private var sessionLockStore = SessionLockStore.shared
    @Environment(\.scenePhase) private var scenePhase
    /// Set by the OpenWebAppIntent notification observer; drives a fullScreenCover
    /// presenting `WebAppWebViewScreen`. Cleared when the user dismisses the
    /// immersive WebView (back-edge swipe / programmatic dismiss).
    @State private var pendingWebAppPresentation: WebAppPresentation?
    @State private var pendingURLWhileLocked: URL?

    #if DEBUG
    let debugServer = DebugServer()
    #endif

    /// Tracks when the app entered background for duration logging.
    @State private var backgroundEntryDate: Date?

    init() {
        // [T-ios-mac-uncaught-nsexception] FIRST statement in the process's own
        // code — before any subsystem gets a chance to throw.
        //
        // This used to run only from CrashReporter.onAppLaunch(), which is
        // dispatched from the scenePhase→.active handler AFTER an `await
        // Task.yield()`. Everything before that point — the rest of this init,
        // the entire first view-graph build, and any main-queue block enqueued
        // during it — ran with NO uncaught-exception handler installed, so an
        // NSException there was reported by AppKit with the reason field that
        // the App Store crash report then strips.
        //
        // That window is where the two 1.13(4) macOS crashes landed: the stack
        // bottoms out in NSApplicationMain → -[NSApplication run] with no frame
        // of ours below `MinisApp.$main()`, i.e. a main-runloop turn during
        // startup, not a user gesture. Installing here does not fix a throw, it
        // makes the next one say what it was.
        //
        // `install` is idempotent, so the later onAppLaunch() call is a no-op.
        CrashSignalHandler.install()
        // [T-auto-grouping-default-on] Auto-grouping ships ON. `bool(forKey:)`
        // returns false for an unregistered key, so the default has to be
        // registered here rather than expressed at the (multiple) read sites —
        // registration also leaves an explicit user choice untouched, which a
        // read-site `?? true` would too, but only if every site remembered it.
        //
        // This reverses the original opt-in decision ("moves user data without
        // being asked"). The concern is bounded: the feature only files a chat
        // into a group the user already created, only when the model is
        // confident, only once per chat, and never over a hand-filed session
        // (setFolderIfUnfiled). Android defaults ON to match.
        UserDefaults.standard.register(defaults: ["autoGroupingEnabled": true])
        // [T-voice-input-mode-preference-ios] Pin the lazy static to the real
        // launch instant.
        _ = Self.processLaunchedAt
        #if DEBUG
        try? debugServer.start(port: 8321)
        #endif
        // Install the NSTextContainer setSize: reentrancy guard before any
        // UITextView gets created. Breaks the iOS 26 TextKit1 fillLayoutHole
        // storm that has caused 0x8BADF00D scene-update watchdog kills on
        // markdown tables during streaming.
        NSTextContainerSetSizeGuard.install()
        // Enable in-app language override for String(localized:) and UIKit strings
        Bundle.enableLanguageOverride()
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        Bundle.setLanguage(lang.isEmpty ? nil : lang)
        // [T-ios-soul-name-sidebar-stale] Pre-load cachedMetadata synchronously so
        // ContentView's `@State soulName` gets the real SOUL.md name on its very
        // first render instead of the `.default` stub ("Minis"). Without this the
        // @State initializer (evaluated at ContentView instantiation, before any
        // .onAppear refresh) locks the sidebar title to the default even when the
        // user set a custom name. refreshCache() only reads the tiny SOUL.md file.
        SoulStore.refreshCache()
        // Pre-warm KaTeX WKWebView as fallback for formulas SwiftMath can't render
        KaTeXRenderer.shared.warmUp()
        // Pre-warm the biometric capability probe off the main thread. The
        // first LAContext.canEvaluatePolicy call cold-starts the
        // LocalAuthentication XPC daemon (~500 ms); without this it would run
        // inline on the first sessionContextMenu builder during scroll and
        // hang a frame. (T-ios-biometric-probe-scroll-hang)
        BiometricAuth.prewarm()
        // Clean up Live Activities left over from a previous app session (e.g. app was killed)
        AgentLiveActivityManager.shared.cleanupStaleActivities(source: "MinisApp.init")
        // Start screen-awake controller — it will observe running tasks
        // + the user's opt-in flag and toggle the idle timer accordingly.
        Task { @MainActor in KeepScreenAwakeController.shared.start() }
        // [T-zombie-child-sweep] Retire sub agent sessions whose parent
        // conversation was truncated away — see sweepZombieChildSessions for
        // why a month-old floor is what makes this safe against sync ordering.
        // Cold start only (this init runs once per process) and at background
        // priority: it competes with nothing, and a zombie that survives one
        // extra launch costs nothing.
        Task.detached(priority: .background) {
            // [T-ios27-scene-create-watchdog] Run the one-shot data migrations
            // that used to sit inside ChatStore's dispatch_once (the part_flags
            // backfill and the v1 dirty-row sweep). They are bulk UPDATE/DELETE
            // over the whole messages / sync_dirty_records tables, and anything
            // slow inside that once token blocks every later toucher of
            // ChatStore.shared — including the main thread during scene
            // creation, which is a 10 s hard kill.
            //
            // Ordered before the zombie sweep so the schema is fully settled
            // before that query runs; both are idempotent and actor-serialised.
            await ChatStore.shared.runDeferredMigrations()
            await ChatStore.shared.sweepZombieChildSessions()
        }
    }

    /// [T-ios-reboot-keychain-identity-rotation] The sync bootstrap, factored out
    /// so the launch path and the protected-data-available retry call exactly the
    /// same thing. Both engines self-guard against double-start.
    @available(iOS 17.0, *)
    @MainActor
    private static func startSyncEngines() async {
        await SyncV2Bootstrap.startIfEnabled()
        if !SyncV2Bootstrap.shouldPauseV1() {
            await CloudSyncEngine.shared.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .overlay(alignment: .top) {
                        BackgroundInterruptionBanner()
                    }
                AudioPiPCapsule()
                // Global read-replies capsule — a SINGLE app-root instance driven by
                // VoiceOutputState, so it persists across chat → home (no per-session
                // copy). It lays itself out full-screen (bottom-trailing capsule +
                // tap-to-dismiss catcher), so no positioning wrapper here.
                SpeechPlayerControl()
                AppLockOverlay()
            }
                .onReceive(SessionLockStore.shared.$appIsLocked) { locked in
                    guard !locked, let url = pendingURLWhileLocked else { return }
                    pendingURLWhileLocked = nil
                    if BackupOpenRouter.handle(url) {
                        // .minisbak → restore flow, not the attachment pipeline.
                    } else if ExternalFileImporter.canIngest(url) {
                        ExternalFileImporter.ingest(url, into: shareCoordinator)
                        return
                    }
                    DeepLinkRouter.handle(url: url, shareCoordinator: shareCoordinator)
                }
                // Force a full ContentView rebuild whenever the user-selected
                // language changes. Without this, SwiftUI keeps Text/Label
                // bodies that were already materialized in their original
                // localization — String(localized:) is only re-evaluated when
                // the owning view's body re-runs, and many setting/dashboard
                // sections (iCloud Sync, Appearance, etc.) hold cached strings
                // captured at first render. Bundle.setLanguage swizzles new
                // lookups but does not invalidate the existing view tree.
                // Re-keying the root drops + re-mounts every descendant,
                // re-running their bodies under the new languageBundle.
                .id(appLanguage)
                // Confirmation gate for every minis-config write. Mounted
                // at the root so the sheet appears regardless of which
                // screen is active when the agent triggers a change.
                // Bind to the @ObservedObject's published `pending` so
                // SwiftUI re-evaluates the sheet when the gate enqueues
                // a request — a plain `Binding(get:)` on the singleton
                // would not subscribe to the publisher.
                .sheet(item: Binding(
                    get: { configConfirmGate.pending },
                    set: { _ in /* dismissal goes through gate.userReject() */ }
                )) { _ in
                    ConfigConfirmSheet(gate: configConfirmGate)
                }
                // [review S14] Restore flow for a `.minisbak` opened from
                // Files / AirDrop / a share sheet. Mounted HERE rather than in
                // BackupSettingsView, which was the only observer before: the
                // user opening a backup is almost always mid device-migration
                // and standing on the chat list, so setting `pendingPackage`
                // did nothing visible until they happened to walk into
                // Settings — at which point a restore sheet appeared
                // unprompted. This is the primary migration entry point, so it
                // has to work from wherever the user actually is.
                //
                // Gated on the lock state, and deliberately at the sheet rather
                // than at each call site: AppLockOverlay is a ZStack sibling, so
                // a sheet presents OVER it. `handle()` runs from three places
                // (onOpenURL, the unlock replay, and AppDelegate's scene URL
                // path for a cold launch) and only the first checks the lock —
                // so a locked device could otherwise show a restore sheet, with
                // the package's device name and contents, to whoever is holding
                // the phone. Gating the presentation covers every path at once.
                // The pending package survives here until unlock, so nothing is
                // lost — `appIsLocked` publishing flips this back on.
                .sheet(item: Binding(
                    get: { sessionLockStore.appIsLocked ? nil : openRouter.pendingPackage },
                    set: { openRouter.pendingPackage = $0 }
                )) { pending in
                    NavigationView {
                        // Opens on the RESTORE tab with the package already
                        // loaded. Someone who just tapped a .minisbak is mid
                        // device-migration — landing them on the backup form
                        // and making them find the switch would be exactly
                        // backwards.
                        BackupAndRestoreView(initialTab: .restore,
                                             initialPackageURL: pending.url)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Close") { openRouter.pendingPackage = nil }
                                }
                            }
                    }
                }
                .environmentObject(shareCoordinator)
                .preferredColorScheme(
                    appearanceMode == 1 ? .light : appearanceMode == 2 ? .dark : nil
                )
                .environment(\.locale, appLanguage.isEmpty ? .current : Locale(identifier: appLanguage))
                .dynamicTypeSize(fontSettings.appBaseScale.dynamicTypeSize)
                .onOpenURL { url in
                    shareLog.info("[Share] onOpenURL: \(url.absoluteString)")
                    guard !SessionLockStore.shared.appIsLocked else {
                        shareLog.info("[Share] onOpenURL deferred — app is locked")
                        pendingURLWhileLocked = url
                        return
                    }
                    if BackupOpenRouter.handle(url) {
                        // .minisbak → restore flow, not the attachment pipeline.
                    } else if ExternalFileImporter.canIngest(url) {
                        ExternalFileImporter.ingest(url, into: shareCoordinator)
                        return
                    }
                    DeepLinkRouter.handle(url: url, shareCoordinator: shareCoordinator)
                }
                // Fullscreen immersive WebView for HTML web-app shortcuts.
                // Driven by `.openWebAppDeepLink` (posted by DeepLinkRouter
                // for `minis://open?session=…&path=…`). Mounted at the
                // WindowGroup root so it covers the chat list / draft / any
                // other foreground state.
                // [T-ios-remove-open-webapp-shortcut-intent] The
                // `.openWebAppFromIntent` path (Home-Screen-pinned Shortcut →
                // OpenWebAppIntent) was removed; only the deep-link entry
                // point remains.
                .fullScreenCover(item: $pendingWebAppPresentation) { pres in
                    WebAppWebViewScreen(shortcut: pres.shortcut, resolved: pres.resolved)
                        .ignoresSafeArea()
                        .statusBar(hidden: true)
                }
                .onReceive(NotificationCenter.default.publisher(for: .openWebAppDeepLink)) { note in
                    guard !SessionLockStore.shared.appIsLocked else { return }
                    guard let shortcut = note.userInfo?["shortcut"] as? WebAppShortcut else { return }
                    Task { @MainActor in
                        Self.presentWebAppDeepLink(shortcut: shortcut, into: $pendingWebAppPresentation)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .dismissAllImmersivePresentations)) { _ in
                    // Tear down any open WebApp fullScreenCover so the
                    // upcoming share / deep-link target can surface.
                    // Re-presenting a WebApp goes through this same path
                    // (DeepLinkRouter posts dismiss → waits → posts
                    // .openWebAppDeepLink), so a peer that wants to show
                    // a different WebApp also benefits from this clear.
                    if pendingWebAppPresentation != nil {
                        pendingWebAppPresentation = nil
                    }
                }
                .onAppear {
                    // Populate ConfigRegistry once. Idempotent — every
                    // appearance after the first is a no-op.
                    ConfigRegistry.shared.registerBuiltinsIfNeeded()
                    // Register notification delegate for shortcut task tap-to-open
                    ShortcutNotificationDelegate.shared.register()
                    // Start logging if previously enabled
                    LoggingManager.shared.startIfEnabled()
                    // HangFix(2026-05-14) — always-on hang detector. Was
                    // previously gated to `isProcessing == true`, but the
                    // user can also hit hang while just browsing a session
                    // that contains large attachment-dense markdown.
                    // Acquired once at launch, never released; HangDetector
                    // itself is cheap (100ms poll on a background thread,
                    // observer write on each runloop hop).
                    StreamingHangLogger.shared.acquire(reason: "app-launch always-on")
                    // [T-ios-backup-shared-leak] One-shot migration: an earlier
                    // build delivered backup packages into shared/Backups/,
                    // which is bind-mounted into the guest at /var/minis/shared
                    // and is itself the Shared Files backup category. Move any
                    // leftovers out of the agent-visible workspace.
                    BackupDelivery.migrateLegacySharedBackups()
                    // [T-ios-backup-rollback-persistence] If a restore was
                    // killed mid-flight, put back whatever snapshot survived
                    // and log it — previously nothing knew a restore had even
                    // been interrupted.
                    BackupRestoreJournal.reconcileAtLaunch()
                    // [review I6] Remove staging trees no marker points at.
                    // `defer` cleanup only runs when the process survives, so
                    // an export killed mid-flight used to leave hundreds of MB
                    // in tmp/ that nothing ever swept.
                    BackupExportJournal.sweepAbandoned()
                    // A run still marked .running means the app died mid
                    // backup; without this the list shows a spinner forever
                    // for something that will never finish.
                    BackupHistory.shared.reconcileInterrupted()
                    // NOTE: deliberately NOT releasing the backup keep-alive
                    // here. It looks like useful belt-and-braces and is
                    // actually all downside:
                    //   - it cannot recover anything. `activated` is a static
                    //     in memory, so a killed process zeroes it (and the
                    //     audio session dies with the process anyway) — on the
                    //     next launch the call is a no-op;
                    //   - the ONLY state in which it would do something is when
                    //     a backup is genuinely running, and .onAppear has no
                    //     once-guard, so a root-view rebuild would cut the
                    //     session of a live backup and leave it ~30s of
                    //     beginBackgroundTask before iOS suspends it.
                    // Ownership is enforced where it belongs, by the run token
                    // in BackupRunController.finished(token:).
                    // Migrate legacy provider config on first launch after upgrade
                    ProviderMigration.migrateIfNeeded(store: ProviderConfigStore.shared)
                    // Refresh model lists once per day to keep them current
                    ProviderConfigStore.shared.refreshAllModelsIfNeeded()
                    // [T-mimo-shadow-voice] One-time upgrade fix: force-refresh
                    // mixed-modality providers (MiMo/DashScope) mis-classified by
                    // the old voice-only whitelist, so their text models + shadow
                    // voice rows recover promptly without waiting for a natural refresh.
                    ProviderConfigStore.shared.migrateVoiceModalityIfNeeded()
                    // [T-tools-granular-switches] Carry the one-round master
                    // Tools switch forward into the per-tool Agents switch.
                    AgentToolSwitch.migrateLegacyIfNeeded()
                    // For existing users with no model groups, create a default group silently
                    Task { await ProviderConfigStore.shared.createDefaultGroupIfNeeded() }
                    shareLog.info("[Share] onAppear — checking for pending share")
                    shareCoordinator.checkForPendingShare()
                    // Set up background keep-alive manager
                    BackgroundKeepAliveManager.shared.setup()
                    // Monitor network changes to keep iSH DNS up to date
                    NetworkMonitor.shared.start()
                    // iOS 15 backport: FileProvider removed
                    // Migrate legacy shared dir to App Group container
                    // Trace the resolved AppGroup paths so we can confirm the
                    // main app, FileProvider extension, and iSH bind mount all
                    // agree on which directory holds the user's shared files.
                    // Start watching shared/skills/memory subtrees so iSH writes
                    // and FileBrowserView mutations propagate to the Files app.
                    AppGroupChangeWatcher.shared.start()
                    // Activate security scopes for user-mounted external folders
                    // (e.g. Obsidian vault in iCloud Drive). Held for app lifetime.
                    MountedFoldersManager.shared.activateAll()
                    // Create /var/minis/mounts/<name> symlinks in the fakefs now
                    // that the rootfs exists and mounts are active.
                    AIChatViewModel.refreshMountedFolderSymlinks()
                    // Start iCloud sync engine. v2 takes precedence when its
                    // feature flag is on (see SyncV2Bootstrap); v1 stays
                    // paused while v2 is active. When v2 is off, v1 boots
                    // exactly as before.
                    if #available(iOS 17.0, *) {
                        Task { @MainActor in
                            await Self.startSyncEngines()
                        }
                        // [T-ios-reboot-keychain-identity-rotation] Retry once
                        // protected data unlocks.
                        //
                        // This `.onAppear` fires when the root view MOUNTS, not on
                        // every foreground, so it is a one-shot. Both sync
                        // bootstraps now bail when the device identity is
                        // provisional (Keychain unreadable on a pre-first-unlock
                        // reboot relaunch) — without this observer that bail would
                        // trade a corrupted zone for no sync at all until the user
                        // force-quit the app.
                        //
                        // Both entry points are idempotent (`syncEngine == nil`
                        // guard in v1; v2's own start flag), so an extra call on a
                        // healthy launch is a no-op.
                        NotificationCenter.default.addObserver(
                            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                            object: nil, queue: .main
                        ) { _ in
                            Task { @MainActor in
                                await Self.startSyncEngines()
                            }
                        }
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    NotificationCenter.default.post(name: .newChatRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    // MARK: - Lifecycle Logging

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            let remaining = UIApplication.shared.backgroundTimeRemaining
            if let entry = backgroundEntryDate {
                let elapsed = Date().timeIntervalSince(entry)
                lifecycleLog.info("[Lifecycle] → Active (was background for \(String(format: "%.1f", elapsed))s, remaining: \(Self.formatTimeRemaining(remaining)))")
            } else {
                lifecycleLog.info("[Lifecycle] → Active (remaining: \(Self.formatTimeRemaining(remaining)))")
            }
            backgroundEntryDate = nil

            // [T-new-session-hang-credential-cache] L2 invalidation hook #4:
            // foreground backstop. Credentials may have changed while backgrounded
            // (another device edited a provider and it synced, a Keychain item
            // rotated) in ways the precise hooks (#1-#3) might not have observed
            // while suspended. Clear the credential cache once on resume so the
            // first resolve re-reads truth.
            ProviderCredentialCache.shared.invalidateAll()
            // [T-ios-provider-row-keychain-in-body] Same backstop for the
            // Providers-list row cache — foreground resume can follow a
            // credential change that never bumped `authRevision`.
            ProviderRowCredentialCache.shared.invalidateAll()

            // Unified audio re-assertion on foreground return: stop the background
            // keep-alive track and re-apply the correct session category for the
            // current intent (reply TTS / capture), fixing stale-category silence.
            AudioSessionCoordinator.shared.reassertForForeground()

            // [T-ios-scenephase-active-sigkill] ALL foreground-resume work is
            // deferred off the synchronous scenePhase→.active callback by one
            // yield. Running ANY non-trivial work inside the callback stalls the
            // main thread at the exact moment SwiftUI tears down / re-evaluates
            // the view graph for the foreground transition. The stall overlaps a
            // ChatSession ModifiedContent modifier-chain destroy and the witness-
            // table deref hits freed memory → SIGKILL (CODESIGNING Invalid Page).
            // Yielding first lets the view-graph transition settle; all the work
            // runs on a later tick, outside the fragile window.
            Task { @MainActor in
                await Task.yield()

                ViewModelCache.shared.resumeAllStreamingUI()

                SessionLockStore.shared.evaluateAppLock()

                CrashReporter.shared.onAppLaunch()
                // [T-resource-diag] Start the 60s port/resource sampler. Cheap
                // and off the main queue; see ResourceDiagnostics.
                ResourceDiagnostics.start()
                // [T-perf-cpu-probe] Periodic flush of the CPU buckets.
                PerfProbe.start()
                CrashReporter.shared.updateMarkerPhase(phase: "active")

                _ = SessionBadgeStore.shared
                // [T-ios-session-paused-badge-hardkill] Reconcile .paused badges
                // against the DB's interrupted-session set. The background-expiry
                // push only fires on a graceful task expiry; a hard kill (jetsam/
                // SIGKILL) never runs it, so the badge would be missing after
                // restart. The persisted message tail is the durable source of
                // truth — scan it on the actor, reconcile on the main actor.
                // [T-ios-group-pause-badge-reconcile-stamp] Carry each tail's
                // own date so a restored marker is stamped with WHEN the
                // session was interrupted, not with "now".
                let interruptedWithDates = await ChatStore.shared.interruptedSessionsWithTailDate()
                let interruptedSessions = Set(interruptedWithDates.keys)
                // Exclude sessions that are actively streaming RIGHT NOW: a
                // resumed/running session's DB tail still looks "interrupted"
                // (mid-loop shape), but it is executing, not paused — flagging it
                // would surface a ⏸ badge on a live, spinning session. Active ⇒
                // never paused. (Mirrors the Android foreground reconcile.)
                let activeNow = SessionActivityTracker.shared.activeSessions
                // [T-ios-group-pause-badge-reconcile-stamp] One-time repair of
                // stamps already polluted on existing installs, then reconcile.
                // Order matters: repair first so a corrected stamp is in place
                // before reconcile decides whether one "survives".
                SessionBadgeStore.shared.repairPollutedPausedStamps(entryDates: interruptedWithDates)
                SessionBadgeStore.shared.reconcileInterruptedSessions(
                    interruptedSessions.subtracting(activeNow),
                    entryDates: interruptedWithDates,
                    trigger: "launch-or-foreground")
                ISHKernel.shared.refreshDns()

                #if DEBUG
                debugServer.restartIfDead(port: 8321)
                #endif

                UIApplication.shared.applicationIconBadgeNumber = 0
                BackgroundInterruptionTracker.shared.checkOnForeground()
                // [T-shortcuts-diag-and-pending] Scan for AppIntent runs that
                // were marked pending but never cleared (i.e. the process was
                // suspended before the completion path ran). Records where the
                // user hadn't enabled Background Keep-Alive at the time get a
                // one-shot guidance notification with the setting to turn on;
                // stale (>24h) records are dropped silently.
                // [T-shortcut-orphan-false-positive] Now async: it verifies
                // against ChatStore whether each orphan actually completed before
                // warning. Wrapped in a Task so scenePhase handling stays
                // synchronous; the scan is advisory and nothing below depends on it.
                Task { await ShortcutRunTracker.checkPendingOnForeground() }
                AgentLiveActivityManager.shared.cleanupStaleActivities(source: "scenePhase.active")
                // [T-ios-live-activity-soft-finish] If a completed task's Live
                // Activity is lingering (soft-finished, awaiting the user), the
                // user is now back in the app — dismiss it.
                AgentLiveActivityManager.shared.dismissFinishedActivityOnForeground()
                // [T-ios-listsessions-perf] Deferred off the first-frame
                // critical path. SkillStore.reload() → loadSkills() is a
                // synchronous @MainActor SQLite query PLUS one filesystem read
                // of SKILL.md per installed skill, and scenePhase becomes
                // .active while the launch frame is still being built — it
                // showed up inside the 1.14 s and 0.52 s launch hangs in the
                // CPU Profiler trace. Nothing drawn in the first frame reads
                // `skills`: the slash-command menu and the prompt fragment both
                // consult it later, on demand. A main-queue async hop lets the
                // frame commit first, then reloads.
                DispatchQueue.main.async { SkillStore.shared.reload() }

                if #available(iOS 17.0, *) {
                    SkillFilesystemNotifier.shared.drainIfDirtyAsync(reason: "scenePhase active")
                }

                // iOS 15 backport: FileProvider removed
                MountedFoldersManager.shared.refreshAllWritability()

                // Credential-presence diagnostic (Keychain reads off-main)
                let credInstances: [(id: String, type: ProviderType, cred: String, enabled: Bool)] =
                    ProviderConfigStore.shared.instances.map {
                        ($0.id, $0.providerType, $0.credentialType.rawValue, $0.isEnabled)
                    }
                Task.detached(priority: .utility) {
                    let logger = AppLogger(category: "Provider")
                    for inst in credInstances {
                        let hasKey = ProviderKeychainHelper.loadAPIKey(instanceId: inst.id) != nil
                        let hasOAuthTok: Bool
                        switch inst.type {
                        case .anthropic: hasOAuthTok = ProviderKeychainHelper.loadOAuthToken(instanceId: inst.id, as: ClaudeTokenStorage.self) != nil
                        case .gemini: hasOAuthTok = ProviderKeychainHelper.loadOAuthToken(instanceId: inst.id, as: GeminiTokenStorage.self) != nil
                        case .openAI: hasOAuthTok = ProviderKeychainHelper.loadOAuthToken(instanceId: inst.id, as: CodexTokenStorage.self) != nil
                        case .xAI: hasOAuthTok = ProviderKeychainHelper.loadOAuthToken(instanceId: inst.id, as: XAITokenStorage.self) != nil
                        case .kimiCode: hasOAuthTok = ProviderKeychainHelper.loadOAuthToken(instanceId: inst.id, as: KimiTokenStorage.self) != nil
                        default: hasOAuthTok = false
                        }
                        let hasManual = ProviderKeychainHelper.loadOAuthString(instanceId: inst.id, account: "manual-oauth-token") != nil
                        logger.info("appPhase=active instanceId=\(inst.id.prefix(8)) type=\(inst.type.rawValue) cred=\(inst.cred) enabled=\(inst.enabled) hasApiKey=\(hasKey) hasOAuthToken=\(hasOAuthTok) hasManualOAuth=\(hasManual)")
                    }
                }
            }
            // Trigger iCloud sync on foreground resume: fetch remote changes + send local dirty records.
            // Route to whichever engine is active. v1 must stay quiet whenever
            // v2 has taken over (SyncV2Bootstrap.shouldPauseV1 == true) —
            // otherwise v1's triggerFetch round-trips v1 records every scene-
            // active tick, observed as endless `[iCloud] mergeRemoteMessage
            // SKIP (local newer)` log spam plus continuous v1-side dirty
            // drain that competes with v2's send pipeline.
            if #available(iOS 17.0, *) {
                Task { @MainActor in
                    if SyncV2Bootstrap.shouldPauseV1() {
                        // [T-icloud-device-heartbeat] Re-announce this device on
                        // every foreground resume so peers see a fresh lastSeen.
                        // The record was previously written ONCE per process
                        // lifetime (V2 startup); a Mac app left open for days
                        // never refreshed it and read as "last seen N days ago".
                        if !DeviceIdentity.isProvisional {
                            await ChatStore.shared.markDirty(recordType: "SyncDeviceV2", recordId: DeviceIdentity.deviceId)
                        }
                        // [T-copilot-models-refresh-window] Re-check the model-list
                        // refresh window on every return to the foreground, so a
                        // model a provider enabled while the app sat open appears
                        // without waiting for the next cold launch.
                        ProviderConfigStore.shared.refreshAllModelsIfNeeded()
                        await SyncCore.shared.fetchNow(trigger: .foregroundTimer)
                        await SyncCore.shared.sendNow(trigger: .foregroundTimer)
                    } else {
                        await CloudSyncEngine.shared.triggerFetch()
                        await CloudSyncEngine.shared.triggerSend()
                    }
                }
            }

        case .inactive:
            let remaining = UIApplication.shared.backgroundTimeRemaining
            lifecycleLog.info("[Lifecycle] → Inactive (remaining: \(Self.formatTimeRemaining(remaining)))")
            CrashReporter.shared.updateMarkerPhase(phase: "inactive")
            ViewModelCache.shared.suspendAllStreamingUI()
            // Privacy screen in task switcher when app lock is enabled
            if SessionLockStore.shared.appLockEnabled {
                SessionLockStore.shared.showPrivacyScreen = true
            }

        case .background:
            backgroundEntryDate = Date()
            let remaining = UIApplication.shared.backgroundTimeRemaining
            lifecycleLog.info("[Lifecycle] → Background (remaining: \(Self.formatTimeRemaining(remaining)))")
            CrashReporter.shared.updateMarkerPhase(phase: "background")
            shareCoordinator.clearBufferIfStale()
            // Sync the app-icon badge to the current running-task count
            // on the way out — covers the case where the publisher in
            // BackgroundKeepAliveManager last fired while we were still
            // foreground (badge was forced to 0 by the .active branch).
            BackgroundKeepAliveManager.shared.refreshActiveTaskBadge()
            // Drain any pending skill-filesystem rescan now that the
            // app is leaving the foreground — last chance to run the
            // heavier disk-scan + markDirty pass while we still have
            // CPU before iOS suspends us.
            if #available(iOS 17.0, *) {
                SkillFilesystemNotifier.shared.drainIfDirtyAsync(reason: "scenePhase background")
            }
            // [T-config-audit-wal-loss] The config-audit DB runs in WAL mode and
            // is NOT covered by ICloudBackupManager's checkpointing (it lives in
            // its own file, deliberately outside minis.db). Without a checkpoint
            // a jetsam can drop history that only ever reached the -wal sidecar.
            // Cheap and synchronous — this is the last reliable moment to do it.
            ConfigAuditLog.shared.checkpoint()
            // "Lock on exit" mode — drop every cached unlock
            // stamp so re-entering any locked session requires Face ID.
            // Per-session AIChatView observer only covers the session
            // currently on screen; this catches the rest.
            if SessionLockStore.shared.idleTimeoutSeconds < 0 {
                SessionLockStore.shared.clearAllUnlocks()
            }
            // [T-applock-repeated-faceid] App-level "lock on exit": record WHEN we
            // backgrounded instead of dropping the unlock immediately. The next
            // foreground evaluateAppLock() re-locks only if the background spell
            // exceeded the grace window (SessionLockStore.lockOnExitGraceSeconds),
            // so the rapid inactive↔active churn iOS emits (banners, control
            // center, background-audio state flips) no longer re-prompts Face ID.
            if SessionLockStore.shared.appLockIdleSeconds < 0 {
                SessionLockStore.shared.noteAppBackgrounded()
            }

        @unknown default:
            lifecycleLog.warning("[Lifecycle] → Unknown scene phase")
        }
    }

    private static func formatTimeRemaining(_ remaining: TimeInterval) -> String {
        if remaining > 99999 {
            return "unlimited"
        }
        return String(format: "%.1fs", remaining)
    }

    // MARK: - WebApp Presentation

    /// Identifiable wrapper passed to `fullScreenCover(item:)`. Carries both
    /// the persisted row (so the WebView can read its title) and the
    /// already-resolved host paths (so resolution failures are surfaced
    /// before the cover appears, not from inside it).
    fileprivate struct WebAppPresentation: Identifiable {
        let id: String
        let shortcut: WebAppShortcut
        let resolved: WebAppPathResolver.Resolved
    }

    // [T-ios-remove-open-webapp-shortcut-intent] `openWebAppShortcut(id:into:)`
    // removed alongside OpenWebAppIntent — it was only called from the
    // `.openWebAppFromIntent` handler. The deep-link entry point below
    // (`presentWebAppDeepLink`) is the remaining WebApp presentation path.

    /// Resolves a transient `WebAppShortcut` reconstructed from a
    /// `minis://open?session=…&path=…` deep link (openminis.app launcher
    /// round-trip) and presents the immersive WebView. Does not touch
    /// ChatStore — the launcher URL is fully self-describing.
    @MainActor
    fileprivate static func presentWebAppDeepLink(shortcut: WebAppShortcut,
                                                  into binding: Binding<WebAppPresentation?>) {
        do {
            let resolved = try WebAppPathResolver.resolve(shortcut)
            binding.wrappedValue = WebAppPresentation(id: shortcut.id, shortcut: shortcut, resolved: resolved)
        } catch {
            lifecycleLog.error("[WebApp] deeplink resolve failed scope=\(shortcut.pathScope.rawValue) htmlPath=\(shortcut.htmlPath) error=\(error)")
        }
    }
}
