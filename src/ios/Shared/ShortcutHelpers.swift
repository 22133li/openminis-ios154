import Foundation
import UserNotifications
enum ShortcutNotification {
    /// Category ID for shortcut task notifications — enables tap-to-open-session.
    static let categoryId = "SHORTCUT_TASK"

    static func post(id: String, title: String, body: String, sessionId: String) {
        // Respect the global task notifications toggle
        guard UserDefaults.standard.object(forKey: "backgroundNotificationsEnabled") == nil
                || UserDefaults.standard.bool(forKey: "backgroundNotificationsEnabled") else { return }

        let center = UNUserNotificationCenter.current()

        // [T-shortcut-authprompt-midrun] Only ask for permission when the user
        // has never been asked. iOS suppresses the alert once the status is
        // decided, so the previous unconditional call was harmless in the steady
        // state — but on a first run it pops a system dialog, and now that a
        // "task started" notification fires DURING the shortcut, that dialog can
        // land in the middle of an automation. Checking first means the prompt
        // only ever appears in the genuinely-undecided case.
        //
        // Both calls are async with completion handlers and nothing awaits them,
        // so this stays fire-and-forget: post() returns immediately and the
        // intent's return timing is unchanged.
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }

        // Register category (idempotent)
        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: [],
            intentIdentifiers: []
        )
        // [T-user-ask] Through the shared registry: a bare set() wipes other features' categories.
        NotificationCategoryCenter.shared.register([category])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = ["sessionId": sessionId]

        // [T-mac-dock-badge] Through the badge ledger, not "icon + 1". The
        // ledger lives on the main actor; post() stays fire-and-forget.
        Task { @MainActor in
            content.badge = NSNumber(value: BackgroundKeepAliveManager.shared.noteUnseenNotification())
            let request = UNNotificationRequest(
                identifier: id,
                content: content,
                trigger: nil  // deliver immediately
            )
            center.add(request)
        }
    }
}

/// [T-notification-tap-vs-launch-session] Cold-launch handoff for a
/// notification-tap navigation. On a cold launch the delegate's `didReceive`
/// fires before ContentView has mounted its `.onReceive(.openSessionFromIntent)`
/// subscriber, so the posted NotificationCenter event is simply lost — and the
/// Launch Session preference (e.g. "New Chat") then opens a fresh session
/// instead of the tapped one. The delegate buffers the target here;
/// ContentView's launch `.task` consumes it with top priority, and the warm
/// path (`.onReceive` did navigate) marks it handled so the launch-screen
/// logic yields either way.
@MainActor
final class NotificationNavigationStore {
    static let shared = NotificationNavigationStore()

    private var pendingSessionId: String?
    private var pendingSetAt: Date?
    private var handledAt: Date?

    /// Buffer a tap target (called from didReceive before posting the event).
    func setPending(_ sessionId: String) {
        pendingSessionId = sessionId
        pendingSetAt = Date()
    }

    /// One-shot consume for the cold-launch path. Entries older than 30s are
    /// stale (a warm tap that `.onReceive` already navigated for) and ignored.
    func takePending() -> String? {
        defer { pendingSessionId = nil; pendingSetAt = nil }
        guard let sid = pendingSessionId,
              let t = pendingSetAt,
              Date().timeIntervalSince(t) < 30 else { return nil }
        return sid
    }

    /// Warm path: `.onReceive` navigated directly — drop the buffered copy so
    /// a later launch can't replay it, and remember when it happened so an
    /// in-flight launch `.task` (post arrived during its await) doesn't
    /// clobber the navigation with the Launch Session default.
    func markHandled() {
        pendingSessionId = nil
        pendingSetAt = nil
        handledAt = Date()
    }

    /// True when a notification navigation happened moments ago — the
    /// launch-screen logic must not override it.
    var handledRecently: Bool {
        guard let t = handledAt else { return false }
        return Date().timeIntervalSince(t) < 10
    }
}

/// Handles notification tap → navigates to the session.
final class ShortcutNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ShortcutNotificationDelegate()

    /// Call once at app startup to register as delegate. MUST run inside
    /// `application(_:didFinishLaunchingWithOptions:)` — if the delegate isn't
    /// set by the time didFinishLaunching returns, iOS does not deliver the
    /// cold-launch notification tap to `didReceive` at all (the SwiftUI
    /// `.onAppear` registration alone was too late, which is why tapping a
    /// notification on a killed app used to land on the Launch Session
    /// default instead of the tapped session).
    func register() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Called when user taps the notification (app in foreground or background).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        // [T-user-ask] An answer (or Cancel / Allow) from a user_ask
        // notification: record it first (first come, first served), keep a
        // little background time for the run to pick it up, and open the app
        // only for "Open App" or a plain tap.
        if userInfo["userAskRequestId"] != nil {
            let bgTask = UIApplication.shared.beginBackgroundTask(withName: "user-ask-answer")
            Task { @MainActor in
                let outcome = UserAskCenter.shared.handleNotificationResponse(response)
                if outcome == .openApp { Self.openSession(from: userInfo) }
                completionHandler()
                DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
                    if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
                }
            }
            return
        }
        Self.openSession(from: userInfo)
        completionHandler()
    }

    private static func openSession(from userInfo: [AnyHashable: Any]) {
        if let sessionId = userInfo["sessionId"] as? String, !sessionId.isEmpty {
            DispatchQueue.main.async {
                // Buffer first (cold-launch consumer), then post (warm-path
                // consumer). Whichever runs marks the other's copy dead.
                NotificationNavigationStore.shared.setPending(sessionId)
                NotificationCenter.default.post(
                    name: .openSessionFromIntent,
                    object: nil,
                    userInfo: ["sessionId": sessionId]
                )
                // [T-p2-background-helper] A helper insurance notification
                // also names the child: once the parent chat is up, open its
                // read-only mirror so the user lands on what the notice was
                // about. The delay covers the push animation; the chat view
                // ignores the event if the parent does not match.
                if let childId = userInfo["childSessionId"] as? String, !childId.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        NotificationCenter.default.post(
                            name: .openHelperSheet, object: nil,
                            userInfo: ["childSessionId": childId, "title": "", "parentSessionId": sessionId])
                    }
                }
            }
        }
    }

    /// Show notification even when app is in foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // [T-user-ask] In the foreground the card is on screen already.
        // [T-mac-dock-badge] Except on a Mac with another app in front: UIKit
        // still calls this ("foreground"), but nobody is looking at the card.
        if notification.request.content.userInfo["userAskRequestId"] != nil {
            DispatchQueue.main.async {
                let away = MainActor.assumeIsolated { BackgroundKeepAliveManager.shared.userIsAway }
                completionHandler(away ? [.banner, .sound] : [])
            }
            return
        }
        completionHandler([.banner, .sound])
    }
}

// iOS 15 backport: helper for Shortcut-related utilities
enum ShortcutHelpers {
}

// iOS 15 backport: extracted from deleted SendPromptIntent
extension ShortcutHelpers {
    @MainActor static func extractResponseText(from vm: AIChatViewModel) -> String {
        guard let lastAssistant = vm.messages.last(where: { $0.role == .assistant && !$0.isInternalBridge }) else {
            return "No response."
        }
        let textBlocks = lastAssistant.blocks
            .filter { $0.kind == .text }
            .map { $0.content }
        let text = textBlocks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "No response." : text
    }
}
