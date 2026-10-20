import SwiftUI
import UIKit

// iOS 15 backport: CollectionViewMessageListV3 uses UIHostingConfiguration (iOS 16+).
// This is a functional iOS 15-compatible implementation using SwiftUI List.
// It renders user/assistant messages, supports streaming, and auto-scrolls.

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
    /// iOS 15 backport: open a message attachment (routes to handleMinisURLTap).
    var onOpenAttachment: ((AttachmentMeta) -> Void)?
    var maxContentWidth: CGFloat
    var floatingBarHeight: CGFloat
    var inputBarHeight: CGFloat
    /// True from view creation (the list is rebuilt per session) until the
    /// bottom spacer has actually appeared, proving we're at the latest
    /// message. While true, content changes force-scroll to the bottom —
    /// session messages load asynchronously after the view appears, so the
    /// single onAppear scroll races the load and lands nowhere, which left
    /// users at the top of the transcript having to pull down manually.
    /// Upstream's UIKit list opens at the latest message; this restores
    /// that. Bounded by a short timeout so a user who immediately scrolls
    /// up during load is not fought for long.
    @State private var awaitingInitialScroll = true

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(vm.messages) { message in
                    MessageRowView(
                        message: message,
                        onRetry: { onRetryMessage?(message.id) },
                        onRetryLast: onRetryLast,
                        onEdit: { onEdit?(message.id) },
                        onDeleteFrom: { onDeleteFrom?(message.id) },
                        onWithdraw: { onWithdraw?(message.id) },
                        onStop: onStop,
                        onCompact: { onCompact?(message.id) },
                        onOpenAttachment: { onOpenAttachment?($0) }
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .id(message.id)
                    // Track whether the first turn is visible: drives the
                    // floating scroll-up button in AIChatView. (The UIKit
                    // list reported this via its scroll delegate; the
                    // simplified List had left isAtFirstTurn stuck at false.)
                    .onAppear { if message.id == vm.messages.first?.id { vm.isAtFirstTurn = true } }
                    .onDisappear { if message.id == vm.messages.first?.id { vm.isAtFirstTurn = false } }
                }
                // 底部 spacer：确保 scrollTo(.bottom) 时最后一条消息不会被输入栏遮住
                Color.clear
                    .frame(height: floatingBarHeight + inputBarHeight + 8)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    // Track bottom visibility: while the user has scrolled up
                    // to read history, streaming updates must not yank them
                    // back down. (The UIKit list reported this via its scroll
                    // delegate; the simplified List had left isNearBottom
                    // stuck at true, which also kept the floating scroll
                    // buttons permanently hidden.)
                    .onAppear { vm.isNearBottom = true; awaitingInitialScroll = false }
                    .onDisappear { vm.isNearBottom = false }
            }
            .listStyle(.plain)
            .onChange(of: vm.messages.count) { _ in
                if awaitingInitialScroll {
                    scrollToBottom(proxy: proxy, animated: false)
                } else {
                    scrollToBottomIfNear(proxy: proxy)
                }
            }
            // 流式输出时：直接观察最后一条消息的 content 变化
            //（ChatMessage 是 ObservableObject，content 是 @Published）
            .background(
                LastMessageScrollTrigger(message: vm.messages.last) {
                    if awaitingInitialScroll {
                        scrollToBottom(proxy: proxy, animated: false)
                    } else {
                        scrollToBottomIfNear(proxy: proxy)
                    }
                }
            )
            .onReceive(vm.forceScrollToBottom) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onReceive(vm.forceScrollToTop) { _ in
                scrollToTop(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy, animated: false)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    awaitingInitialScroll = false
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        guard let last = vm.messages.last else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        } else {
            // Unanimated for initial positioning (upstream loads with
            // animated: false): row heights are still estimates while the
            // transcript loads, and an animated scroll lands short.
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    /// Auto-scroll for streaming / count changes: suppressed while the user
    /// is reading history (bottom spacer off-screen). Explicit
    /// forceScrollToBottom (floating button, new turn) still goes through.
    private func scrollToBottomIfNear(proxy: ScrollViewProxy) {
        guard vm.isNearBottom else { return }
        scrollToBottom(proxy: proxy)
    }

    private func scrollToTop(proxy: ScrollViewProxy) {
        guard let first = vm.messages.first else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(first.id, anchor: .top)
        }
    }
}

// MARK: - Markdown Text (iOS 15 backport: AttributedString markdown parsing)

private struct MarkdownText: View {
    let content: String

    var body: some View {
        // iOS 15's AttributedString markdown parser only handles inline
        // syntax, so fenced code blocks (```) are split out and rendered
        // as monospaced blocks. (Tables remain plain text: iOS 15 has no
        // table support in AttributedString.)
        let segments = content.components(separatedBy: "```")
        if segments.count == 1 {
            inlineText(content)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(segments.indices, id: \.self) { i in
                    if i % 2 == 1 {
                        CodeBlockView(code: segments[i])
                    } else if !segments[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        inlineText(segments[i])
                    }
                }
            }
        }
    }

    private func inlineText(_ s: String) -> some View {
        Group {
            if let attributed = try? AttributedString(markdown: s, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnly)) {
                Text(styledInlineCode(attributed))
            } else {
                Text(verbatim: s)
            }
        }
        // [iOS15-font] Match upstream: message text follows FontSettings.
        .font(.system(size: FontSettings.shared.scaledMessage(16.5)))
        .textSelection(.enabled)
        // [T-link-v3-handler-91] Route link taps through the app's minis://
        // handler. Without this, Text(AttributedString) links use the system
        // default openURL: http(s) opens Safari (works), but minis://,
        // file:// and bare filenames silently fail. This was the root cause
        // of "file links do nothing" — handleMinisURLTap was never reached.
        .modifier(MinisOpenURLHandler())
    }

    /// Match upstream inline code: systemOrange text on an adaptive light
    /// background (systemGray6 / dark #3A3A3C). Per-run corner radius is not
    /// expressible in AttributedString; color + background carry the look.
    private func styledInlineCode(_ a: AttributedString) -> AttributedString {
        var out = a
        for run in out.runs {
            if run.inlinePresentationIntent?.contains(.code) == true {
                out[run.range].foregroundColor = .orange
                out[run.range].backgroundColor = Color(UIColor { traits in
                    traits.userInterfaceStyle == .dark
                        ? UIColor(red: 0x3A / 255.0, green: 0x3A / 255.0, blue: 0x3C / 255.0, alpha: 1)
                        : .systemGray6
                })
            }
        }
        return out
    }
}

private struct CodeBlockView: View {
    let code: String
    @State private var copied = false

    /// Drop a leading language tag line (```swift\n...) if present.
    private var bodyCode: String {
        var lines = code.components(separatedBy: .newlines)
        if lines.count >= 2, let first = lines.first,
           !first.isEmpty, !first.contains(" "), !first.contains("\t") {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var language: String? {
        let lines = code.components(separatedBy: .newlines)
        if lines.count >= 2, let first = lines.first,
           !first.isEmpty, !first.contains(" "), !first.contains("\t") {
            return first
        }
        return nil
    }

    // [iOS15-codeblock] Match upstream SelectableMarkdownTheme: black
    // background (dark: dark gray), green terminal text, Menlo, 11pt
    // language label + copy button.
    private var codeBg: Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.15, alpha: 1) : .black })
    }
    private var codeTextColor: Color {
        Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.55, green: 0.95, blue: 0.55, alpha: 1) : .systemGreen })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let lang = language {
                    Text(lang.lowercased())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = bodyCode
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(copied ? .green : .white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: bodyCode)
                    .font(.custom("Menlo", size: 13))
                    .foregroundColor(codeTextColor)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(codeBg)
        .cornerRadius(8)
    }
}

// MARK: - Message Row

private struct MessageRowView: View {
    @ObservedObject var message: ChatMessage
    var onRetry: (() -> Void)?
    var onRetryLast: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDeleteFrom: (() -> Void)?
    var onWithdraw: (() -> Void)?
    var onStop: (() -> Void)?
    var onCompact: (() -> Void)?
    var onOpenAttachment: ((AttachmentMeta) -> Void)?

    /// Display text with the <user-attached-files> model XML stripped, in
    /// case a stored message carries it.
    private var displayContent: String {
        var text = message.content
        if let start = text.range(of: "<user-attached-files>") {
            let endBound = text.range(of: "</user-attached-files>")?.upperBound ?? text.endIndex
            text = String(text[text.startIndex..<start.lowerBound] + text[endBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: 4) {
                    if !displayContent.isEmpty {
                        Text(verbatim: displayContent)
                            // [iOS15-bubble] Match upstream UserBubbleSurface:
                            // tertiarySystemFill bubble + label-color text
                            // (not iMessage blue), font follows FontSettings.
                            .font(.system(size: FontSettings.shared.scaledMessage(16.5)))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(ChatColors.userBubble)
                            .foregroundColor(ChatColors.primaryText)
                            .cornerRadius(18)
                    }
                    if !message.attachments.isEmpty {
                        ForEach(message.attachments) { attachment in
                            AttachmentRowView(attachment: attachment) {
                                onOpenAttachment?(attachment)
                            }
                        }
                    } else if !message.inputAttachments.isEmpty {
                        // Queued / in-flight send: files not yet copied to uploads,
                        // so no AttachmentMeta exists — preview from cache.
                        // Mirrors upstream ChatMessageViews' QueuedAttachmentPreview fallback.
                        ForEach(message.inputAttachments) { inputAttachment in
                            PendingAttachmentRowView(attachment: inputAttachment)
                        }
                    }
                }
            }
            .contextMenu {
                Button { onRetry?() } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                Button { onEdit?() } label: {
                    Label("编辑", systemImage: "pencil")
                }
                Button { onDeleteFrom?() } label: {
                    Label("从这里删除", systemImage: "trash")
                }
                if message.isQueued {
                    Button { onWithdraw?() } label: {
                        Label("撤回", systemImage: "arrow.uturn.backward")
                    }
                }
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                // Render text blocks
                ForEach(message.blocks.indices, id: \.self) { idx in
                    let block = message.blocks[idx]
                    BlockView(block: block)
                }
                // Fallback to content if no blocks
                if message.blocks.isEmpty && !message.content.isEmpty {
                    MarkdownText(content: message.content)
                }
                // Error state with retry
                if let error = message.error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                        Button("重试") {
                            onRetryLast?()
                        }
                        .font(.caption)
                    }
                }
                // Streaming indicator — matches upstream TypingIndicator.
                if message.isAwaitingModelResponse {
                    TypingIndicatorView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = message.content
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                if onCompact != nil {
                    Button { onCompact?() } label: {
                        Label("压缩到此处", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                }
            }
        case .compactDivider:
            HStack {
                Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.3))
                Text("上下文已压缩")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.3))
            }
        case .systemInfo:
            HStack {
                Spacer()
                Text(message.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(10)
                Spacer()
            }
        }
    }
}

// MARK: - Attachment Row

/// iOS 15 backport: the simplified list showed only "附件 N 个". Restore the
/// file rows (name + size) with tap-to-open, matching the reference package.
private struct AttachmentRowView: View {
    let attachment: AttachmentMeta
    var onOpen: () -> Void

    private var iconName: String {
        if attachment.isImage { return "photo" }
        if attachment.isVideo { return "video" }
        return "doc"
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.fileName)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray5)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Block View

/// Row for a not-yet-uploaded attachment (queued or in-flight send).
/// The file lives only in `message.inputAttachments` (app Caches) until the
/// send task / queue drain copies it to uploads and swaps in the real
/// `AttachmentMeta`s — until then there is no minis:// URL to open, so the
/// row is display-only, dimmed like upstream's QueuedAttachmentPreview.
private struct PendingAttachmentRowView: View {
    let attachment: InputAttachment

    private var iconName: String {
        switch attachment.kind {
        case .image: return "photo"
        case .video: return "video"
        case .document: return "doc"
        }
    }

    private var sizeString: String {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: attachment.cacheURL.path)[.size] as? Int) ?? 0
        guard bytes > 0 else { return "等待发送" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(sizeString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray5)))
        .opacity(0.7)
    }
}

private struct BlockView: View {
    @ObservedObject var block: AssistantBlock

    var body: some View {
        switch block.kind {
        case .text:
            if !block.content.isEmpty {
                MarkdownText(content: block.content)
            }
        case .thinking:
            // [iOS15-thinking-style] Match upstream ThinkingBlockView container:
            // blue 0.06 background, 12pt rounded corners, blue 0.15 hairline.
            DisclosureGroup {
                Text(block.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } label: {
                Text("思考过程")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.blue)
            }
            .font(.caption)
            .padding(10)
            .background(Color.blue.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.15), lineWidth: 0.5)
            )
        case .shellTool(let command):
            ToolBlockView(icon: "terminal", color: .green, title: "执行命令", detail: command, content: block.content)
        case .fileReadTool(let path):
            ToolBlockView(icon: "doc.text", color: .cyan, title: "读取文件", detail: path, content: block.content)
        case .fileWriteTool(let path):
            ToolBlockView(icon: "doc.text.fill", color: .blue, title: "写入文件", detail: path, content: block.content)
        case .fileEditTool(let path):
            ToolBlockView(icon: "square.and.pencil", color: .orange, title: "编辑文件", detail: path, content: block.content)
        case .browserTool(let action):
            ToolBlockView(icon: "globe", color: .blue, title: "浏览 \(action)", detail: "", content: block.content)
        case .readImageTool(let path):
            ToolBlockView(icon: "photo", color: .purple, title: "查看图片", detail: path, content: block.content)
        case .memoryTool(let action):
            ToolBlockView(icon: "brain.head.profile", color: .pink, title: "记忆 \(action)", detail: "", content: block.content)
        case .vaultTool(let action):
            ToolBlockView(icon: "key.fill", color: .blue, title: "保险库 \(action)", detail: "", content: block.content)
        case .delegateTool(let title):
            ToolBlockView(icon: "person.2.fill", color: .purple, title: title, detail: "", content: block.content)
        case .info:
            if !block.content.isEmpty {
                Text(block.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct ToolBlockView: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let content: String

    var body: some View {
        DisclosureGroup {
            if !content.isEmpty {
                Text(content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            // [iOS15-tool-capsule] Match upstream ToolCapsuleView: gray pill,
            // fixed 36pt height, hairline border. Applied to the label only so
            // the expanded detail content is not height-clipped.
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color(UIColor.systemGray6))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(ChatColors.toolBorder, lineWidth: 0.5))
        }
        .padding(.vertical, 2)
    }
}

/// Matches upstream TypingIndicator: "<soul> is thinking" + 3 bouncing dots.
private struct TypingIndicatorView: View {
    @State private var dotOffsets = [false, false, false]

    private var soulName: String {
        let n = SoulStore.cachedMetadata.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Minis" : n
    }

    var body: some View {
        HStack(spacing: 0) {
            Text("\(soulName) is thinking")
            ForEach(0..<3, id: \.self) { i in
                Text(".")
                    .offset(y: dotOffsets[i] ? -3 : 1)
            }
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(ChatColors.tertiaryText)
        .onAppear {
            for i in 0..<3 {
                withAnimation(
                    .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.15)
                ) {
                    dotOffsets[i] = true
                }
            }
        }
    }
}

/// 观察最后一条消息的内容变化，流式输出时触发滚动到底部。
/// ChatMessage 是 ObservableObject，直接观察其 @Published content。
private struct LastMessageScrollTrigger: View {
    @ObservedObject var message: ChatMessage
    let onChange: () -> Void

    init(message: ChatMessage?, onChange: @escaping () -> Void) {
        // message 为 nil 时用一个空占位（不会触发）
        self.message = message ?? ChatMessage(role: .user, content: "")
        self.onChange = onChange
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: message.content) { _ in
                onChange()
            }
    }
}
