import Foundation

// iOS 15 backport: Notification names removed with Intents
extension NSNotification.Name {
    static let openSessionFromIntent = NSNotification.Name("com.openminis.app.openSessionFromIntent")
}
