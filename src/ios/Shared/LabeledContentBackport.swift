
import SwiftUI

// iOS 15 backport: LabeledContent is iOS 16+.
struct LabeledContent<Content: View, Label: View>: View {
    let content: Content
    let label: Label

    init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
    }

    init(_ label: String, @ViewBuilder content: () -> Content) where Label == Text {
        self.content = content()
        self.label = Text(LocalizedStringKey(label))
    }

    init(_ label: String, value: String) where Content == Text, Label == Text {
        self.content = Text(value)
        self.label = Text(LocalizedStringKey(label))
    }

    var body: some View {
        HStack {
            label
            Spacer()
            content
        }
    }
}
