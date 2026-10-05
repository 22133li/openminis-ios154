import SwiftUI

// iOS 15 backport: AnyShape is iOS 16+. Simple type-erased Shape.
struct AnyShape: Shape {
    private let pathBuilder: (CGRect) -> Path
    init<S: Shape>(_ shape: S) {
        self.pathBuilder = { rect in shape.path(in: rect) }
    }
    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}

// iOS 15 backport: UnevenRoundedRectangle is iOS 16+.
// Approximates with uniform RoundedRectangle using average radius.
struct UnevenRoundedRectangle: Shape {
    var topLeadingRadius: CGFloat = 0
    var bottomLeadingRadius: CGFloat = 0
    var bottomTrailingRadius: CGFloat = 0
    var topTrailingRadius: CGFloat = 0
    var style: RoundedCornerStyle = .continuous

    init(topLeadingRadius: CGFloat = 0, bottomLeadingRadius: CGFloat = 0,
         bottomTrailingRadius: CGFloat = 0, topTrailingRadius: CGFloat = 0,
         style: RoundedCornerStyle = .continuous) {
        self.topLeadingRadius = topLeadingRadius
        self.bottomLeadingRadius = bottomLeadingRadius
        self.bottomTrailingRadius = bottomTrailingRadius
        self.topTrailingRadius = topTrailingRadius
        self.style = style
    }

    func path(in rect: CGRect) -> Path {
        let avg = (topLeadingRadius + bottomLeadingRadius + bottomTrailingRadius + topTrailingRadius) / 4
        return RoundedRectangle(cornerRadius: avg, style: style).path(in: rect)
    }
}
