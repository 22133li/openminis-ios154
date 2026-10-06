import SwiftUI

// iOS 15 backport: CollectionViewMessageListV3 uses UIHostingConfiguration (iOS 16+).
// Stubbed with a simple List for iOS 15.
struct CollectionViewMessageListV3: View {
    @ObservedObject var vm: AIChatViewModel
    var inputFocused: Bool
    var onRetryMessage: ((UUID) -> Void)?
    var onRetryLast: (() -> Void)?
    var onOpenSoulSettings: (() -> Void)?
    var onEdit: ((UUID) -> Void)?
    var onDeleteFrom: ((UUID) -> Void)?
    var onWithdraw: ((UUID) -> Void)?
    var onResume: (() -> Void)?
    var onStop: (() -> Void)?
    var onBrowserTakeover: (() -> Void)?
    var onTakeoverDone: (() -> Void)?
    var onCompact: ((UUID) -> Void)?
    var onRevertCompact: (() -> Void)?
    var onForceSync: (() -> Void)?
    var onScreenshotImage: ((UIImage) -> Void)?
    var maxContentWidth: CGFloat
    var floatingBarHeight: CGFloat
    var inputBarHeight: CGFloat

    var body: some View {
        // iOS 15 fallback: simple message list
        List {
            Text("Message list (iOS 15 backport)")
                .foregroundColor(.secondary)
        }
    }
}
