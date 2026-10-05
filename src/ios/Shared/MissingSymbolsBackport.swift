import Foundation

// iOS 15 backport: Notification names removed with Intents
extension NSNotification.Name {
    static let openSessionFromIntent = NSNotification.Name("com.openminis.app.openSessionFromIntent")
}

extension NSNotification.Name {
    static let minisUserAttachmentsMounted = NSNotification.Name("minisUserAttachmentsMounted")
    static let messageListNeedsResnapshot = NSNotification.Name("messageListNeedsResnapshot")
}
