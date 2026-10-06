import Foundation

// Notification names for Intent-related navigation (iOS 15.4 compatible)
// These were originally defined in the Intents files, but those require iOS 16+.
// This file provides the names so the rest of the app can post/observe them.
extension Notification.Name {
    static let openSessionFromIntent = Notification.Name("openSessionFromIntent")
    static let minisUserAttachmentsMounted = Notification.Name("minisUserAttachmentsMounted")
}

/// Bridge for audio toggle Darwin notifications (extracted from AudioTogglePlaybackIntent.swift).
/// The Intent itself requires iOS 16+, but this bridge is 15.4-compatible.
enum AudioTogglePlaybackBridge {
    /// Darwin notification name the widget posts and the app observes.
    static let darwinNotificationName = "com.openminis.app.liveActivity.audioToggle"
}
