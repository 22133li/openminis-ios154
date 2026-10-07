import SwiftUI

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
    var maxContentWidth: CGFloat
    var floatingBarHeight: CGFloat
    var inputBarHeight: CGFloat

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(vm.messages) { message in
                    MessageRowView(message: message, onRetry: {
                        onRetryMessage?(message.id)
                    })
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowBackground(Color.clear)
                    .id(message.id)
                }
                // 底部 spacer：确保 scrollTo(.bottom) 时最后一条消息不会被输入栏遮住
                Color.clear
                    .frame(height: floatingBarHeight + inputBarHeight + 24)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            // 底部留出输入栏高度，避免最后一条消息被遮住
            // (+12pt 缓冲：几何测量有舍入误差，home indicator 区域也需要留白)
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: floatingBarHeight + inputBarHeight + 12)
            }
            .onChange(of: vm.messages.count) { _ in
                scrollToBottom(proxy: proxy)
            }
            // 流式输出时：直接观察最后一条消息的 content 变化
            //（ChatMessage 是 ObservableObject，content 是 @Published）
            .background(
                LastMessageScrollTrigger(message: vm.messages.last) {
                    scrollToBottom(proxy: proxy)
                }
            )
            .onReceive(vm.forceScrollToBottom) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = vm.messages.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

// MARK: - Markdown Text (iOS 15 backport: AttributedString markdown parsing)

private struct MarkdownText: View {
    let content: String
    
    var body: some View {
        if let attributed = try? AttributedString(markdown: content, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnly)) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(verbatim: content)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Message Row

private struct MessageRowView: View {
    @ObservedObject var message: ChatMessage
    var onRetry: (() -> Void)?

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(verbatim: message.content)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(18)
                    if !message.attachments.isEmpty {
                        Text("附件 \(message.attachments.count) 个")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
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
                            onRetry?()
                        }
                        .font(.caption)
                    }
                }
                // Streaming indicator
                if message.isAwaitingModelResponse {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("思考中…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Block View

private struct BlockView: View {
    @ObservedObject var block: AssistantBlock

    var body: some View {
        switch block.kind {
        case .text:
            if !block.content.isEmpty {
                MarkdownText(content: block.content)
            }
        case .thinking:
            DisclosureGroup("思考过程") {
                Text(block.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .font(.caption)
        case .shellTool(let command):
            ToolBlockView(icon: "terminal.fill", title: "执行命令", detail: command, content: block.content)
        case .fileReadTool(let path):
            ToolBlockView(icon: "doc.fill", title: "读取文件", detail: path, content: block.content)
        case .fileWriteTool(let path):
            ToolBlockView(icon: "square.and.pencil", title: "写入文件", detail: path, content: block.content)
        case .fileEditTool(let path):
            ToolBlockView(icon: "pencil", title: "编辑文件", detail: path, content: block.content)
        case .browserTool(let action):
            ToolBlockView(icon: "globe", title: "浏览 \(action)", detail: "", content: block.content)
        case .readImageTool(let path):
            ToolBlockView(icon: "photo.fill", title: "查看图片", detail: path, content: block.content)
        case .memoryTool(let action):
            ToolBlockView(icon: "brain.head.profile", title: "记忆 \(action)", detail: "", content: block.content)
        case .delegateTool(let title):
            ToolBlockView(icon: "person.2.fill", title: title, detail: "", content: block.content)
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
                    .foregroundColor(.blue)
                Text(title)
                    .font(.subheadline)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
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
