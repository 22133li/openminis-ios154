import Foundation

// iOS 15 backport: LocalizedStringResource is iOS 16+.
// For the backport target, treat it as a plain String.
typealias LocalizedStringResource = String
