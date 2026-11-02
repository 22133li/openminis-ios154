# Minis v1.15 迁移合并日志（iOS 15.4 适配：1.14 线 → 上游 v1.15）

- 上游 1.14 基线：`b4c0661`；我们 1.14 线最终适配树：`158c46c`（build121/1.37）；上游 v1.15：`6eda552`；迁移起点：`1b47955`（71 个无重叠适配文件已由父代理搬入，本日志不重复记录）。
- 方法：逐文件三方对照（base=b4c0661 / ours=158c46c / theirs=6eda552）。60 个同路径文件先做三方试合：41 个干净合入（批次 1），19 个手工解决（批次 2–8）；4 个被上游拆分的大文件按语义迁移（批次 9–11）；其后对 1.15 新增/大改代码做 iOS 16+ API 审计（批次 12–13）。
- 纪律：日志之外无变更；未 push；未动版本号与 .github/workflows。

## A. 三方干净合入（41 文件，批次 1 `b5d1472`）

合并方式均为：git 三方合入（上游 1.15 结构为底，叠加我方 1.14 适配 hunk，无冲突），合后逐个核验我方新增行无丢失。下表「我方改动摘要」取自我方 1.14 diff 的代表性新增行。

### deps/build_ffmpeg.sh
- 我方 1.14 改动（+9/-2）：# [mirror-fallback 2026-10-29] ffmpeg.org timed out / reset the downlo; # from CI runners twice in a row. MacPorts distfiles mirrors the ident; # tarball (SHA256 3b624649725ecdc565c903ca6643d41f33bd49239922e45c9b14
- 合并方式：三方合入，无判断分歧。

### src/ios/Agent/BrowserUse/BrowserManagementView.swift
- 我方 1.14 改动（+3/-3）：ToolbarItem(placement: .navigationBarTrailing) {; TextField("Enter custom user agent...", text: $customUA); .lineLimit(4)
- 合并方式：三方合入，无判断分歧。

### src/ios/Agent/BrowserUse/BrowserSheetView.swift
- 我方 1.14 改动（+94/-68）：@State private var takeoverEngaged = false; private var effectiveBusy: Bool {; if takeoverEngaged { return false }
- 合并方式：三方合入，无判断分歧。

### src/ios/Agent/Chat/AIChatViewModel+BackgroundTask.swift
- 我方 1.14 改动（+1/-0）：case .vaultTool: toolName = "vault"
- 合并方式：三方合入，无判断分歧。

### src/ios/Agent/Chat/AIChatViewModel+ConcurrentTools.swift
- 我方 1.14 改动（+1/-0）：
- 合并方式：三方合入，无判断分歧。

### src/ios/Agent/Chat/AIChatViewModel+ProviderFactory.swift
- 我方 1.14 改动（+22/-0）：func noModelResolutionHint() -> String {; let store = ProviderConfigStore.shared; if let sid = sessionId, let binding = store.binding(for: sid) {
- 合并方式：三方合入，无判断分歧。

### src/ios/Agent/Chat/AIChatViewModel+RequestBudget.swift
- 我方 1.14 改动（+17/-4）：if let container = FileManager.default.containerURL(; ) {; return container.appendingPathComponent("MinisFileProvider", isDirecto
- 合并方式：三方合入，无判断分歧。

### src/ios/Agent/Chat/AIChatViewModel+SSEStream.swift
- 我方 1.14 改动（+12/-0）：case "vault_list":; return .vaultTool(action: "List credentials"); case "vault_use_secret":
- 合并方式：三方合入，无判断分歧。

### src/ios/Agent/Chat/AIChatViewModel+TitleGeneration.swift
- 我方 1.14 改动（+1/-1）：?? Locale.current.languageCode
- 合并方式：三方合入，无判断分歧。

### src/ios/Agent/Chat/AIChatViewModel+ToolDefinitions.swift
- 我方 1.14 改动（+1/-0）：
- 合并方式：三方合入，无判断分歧。

### src/ios/Agent/Chat/ChatModels.swift
- 我方 1.14 改动（+19/-0）：var fileTapURL: URL? {; let rel = path.hasPrefix("/var/minis/") ? String(path.dropFirst("/var/; let parts = rel.split(separator: "/", omittingEmptySubsequences: true)
- 合并方式：三方合入，无判断分歧。

### src/ios/Agent/ISH/ISHExecutionCoordinator.swift
- 我方 1.14 改动（+1/-1）：var customEnv = EnvVarStore.shared.allAsDict()
- 合并方式：三方合入，无判断分歧。

### src/ios/Agent/Intents/ShortcutRunTracker.swift
- 我方 1.14 改动（+3/-0）：@available(iOS 16, *); @available(iOS 16, *); @available(iOS 16, *)
- 合并方式：三方合入，无判断分歧。

### src/ios/Agent/MessageList/MessageListInfrastructure.swift
- 我方 1.14 改动（+162/-0）：struct HostingCellConfiguration: UIContentConfiguration {; var rootView: AnyView; weak var hostParent: UIViewController?
- 合并方式：三方合入，无判断分歧。

### src/ios/Localizable.xcstrings
- 我方 1.14 改动（+14/-42）："" : {},; "." : {},; "·" : {},
- 合并方式：三方合入，无判断分歧。

### src/ios/NativeOffloads/HealthKitOffload.m
- 我方 1.14 改动（+0/-4）：
- 合并方式：三方合入，无判断分歧。

### src/ios/Providers/Voice/SystemVoiceCatalog.swift
- 我方 1.14 改动（+1/-1）：(Locale(identifier: tag).languageCode ?? "").lowercased()
- 合并方式：三方合入，无判断分歧。

### src/ios/Providers/Voice/VoiceProvider+System.swift
- 我方 1.14 改动（+0/-1）：
- 合并方式：三方合入，无判断分歧。

### src/ios/Providers/Voice/VoiceProviderResolver.swift
- 我方 1.14 改动（+1/-1）：try? await Task.sleep(nanoseconds: 200000000)
- 合并方式：三方合入，无判断分歧。

### src/ios/Shared/Config/Confirm/ConfigConfirmSheet.swift
- 我方 1.14 改动（+4/-6）：NavigationView {; ToolbarItem(placement: .navigationBarLeading) {; ToolbarItem(placement: .navigationBarTrailing) {
- 合并方式：三方合入，无判断分歧。

### src/ios/Shared/EnvVarRedactor.swift
- 我方 1.14 改动（+2/-0）：
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Chat/HelperSheet.swift
- 我方 1.14 改动（+3/-8）：NavigationView {; ToolbarItem(placement: .navigationBarLeading) {; ToolbarItem(placement: .navigationBarTrailing) {
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Chat/MinisMediaViews.swift
- 我方 1.14 改动（+2/-4）：if let url = meta.fileTapURL { openURL(url) }; let textView = UITextView()
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Chat/Voice/InlineVoiceInputView.swift
- 我方 1.14 改动（+2/-7）：NavigationView {; ))
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Chat/Voice/SpeechPlayerControl.swift
- 我方 1.14 改动（+4/-4）：try? await Task.sleep(nanoseconds: 250000000); try? await Task.sleep(nanoseconds: UInt64(Self.descentSettleMillis) * ; NavigationView {
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Chat/Voice/VoiceInputPanel.swift
- 我方 1.14 改动（+4/-4）：if let lang = loc.languageCode {; if let region = loc.regionCode {; ?? loc.languageCode.map { current.localizedString(forLanguageCode: $0)
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/MCP/MCPFormSheet.swift
- 我方 1.14 改动（+12/-26）：NavigationView {; TextField(AppLocalized("Optional description"), text: $note); .lineLimit(4)
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Providers/ModelQuickTestSheet.swift
- 我方 1.14 改动（+3/-3）：NavigationView {; ToolbarItem(placement: .navigationBarLeading) {; ToolbarItem(placement: .navigationBarTrailing) {
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Providers/UnifiedModelPicker.swift
- 我方 1.14 改动（+25/-21）：private static let searchDebounce: TimeInterval = 0.12; try? await Task.sleep(nanoseconds: UInt64(Self.searchDebounce * 1_000_; NavigationView {
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Rootfs/ISHTerminalView.swift
- 我方 1.14 改动（+12/-14）：.navigationBarItems(; leading: Group {; if showCloseButton {
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Rootfs/RootfsManagementView.swift
- 我方 1.14 改动（+2/-2）：NavigationView {; NavigationView {
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Settings/BackupDestinationDetailView.swift
- 我方 1.14 改动（+12/-12）：await BackupDestinations.listPackages(folderId: id); Text(AppLocalized("Configuration")); Text(AppLocalized("Test Connection"))
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Settings/BackupHistoryDetailView.swift
- 我方 1.14 改动（+9/-19）：.navigationBarItems(trailing: Group {; Button(role: .destructive) {; showDeleteConfirm = true
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Settings/BackupRestoreView.swift
- 我方 1.14 改动（+14/-16）：Text(AppLocalized("Backup Destinations")); Text(AppLocalized("Other Sources")); Text(AppLocalized("Cancel"))
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Settings/ConfigAuditView.swift
- 我方 1.14 改动（+1/-1）：Text(AppLocalized("Revert"))
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Settings/EnhancedBackgroundSettingsView.swift
- 我方 1.14 改动（+8/-8）：Text(AppLocalized("Rate")); Text(AppLocalized("Pitch")); Text(AppLocalized("Volume"))
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Settings/LogManagementView.swift
- 我方 1.14 改动（+20/-12）：Text(AppLocalized("Logs")).tag("logs"); Text(AppLocalized("Config Changes")).tag("config-audit"); Text(AppLocalized("Info")).tag(AppLogger.Level.info)
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Settings/RcloneAddServerView.swift
- 我方 1.14 改动（+11/-18）：NavigationView {; .navigationBarItems(; leading: Button("Cancel") { cancelAndDismiss() },
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Settings/StorageManagementView.swift
- 我方 1.14 改动（+4/-6）：Text(AppLocalized("Total")); Text(AppLocalized("Overview")); Text(AppLocalized("No sessions"))
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Skills/SkillsManagementView.swift
- 我方 1.14 改动（+117/-79）：if store.isLoading {; Section {; HStack {
- 合并方式：三方合入，无判断分歧。

### src/ios/Views/Sync/SyncMigrationDetailView.swift
- 我方 1.14 改动（+1/-3）：NavigationView {
- 合并方式：三方合入，无判断分歧。
## B. 手工解决的冲突文件（19 文件，批次 2–8）

### src/ios/Agent/Background/BackgroundKeepAliveManager.swift（批次 2 `983e64d`）
- 我方改动：徽章投递用 `UIApplication.applicationIconBadgeNumber`（UNUserNotificationCenter.setBadgeCount 为 iOS 16+）；`import UIKit`、NavigationView、Color.orange 去 .gradient 等。
- 合并方式：计数模型取上游 1.15 的 `AppBadge.total(running, enabled, unseen)`；投递点用 `if #available(iOS 16)` 分流（16+ 用上游 setBadgeCount 原样，15 用 applicationIconBadgeNumber = total）；其余我方 hunk 干净合入。文件内仅此一处 setBadgeCount 投递点，另一处只计算 total 作 content.badge，无 API 问题。

### src/ios/Agent/Chat/AIChatViewModel.swift（批次 2）
- 我方改动：3 个 hunk（retry 守卫报错文案、`.vaultTool` 的 kind 映射、`noModelResolutionHint()` 报错）。
- 合并方式：上游 1.15 把该文件尾部 6414 行拆走，冲突为整文件尾部假冲突，本体取 1.15；3 个 hunk 语义迁移到新落点（见 D 节）：+Send.swift、+DebugDumps.swift、+AgentLoop.swift。

### src/ios/Agent/Jobs/HelperRunner.swift（批次 2）
- 我方改动：工具 wire 名映射新增 `.vaultTool(let a): "vault:\(a)"`。
- 合并方式：上游把内联开关重构成 `AIChatViewModel.toolWireName`（新文件 Agent/Jobs/SubAgentTermination.swift，有 default 分支），我方 case 迁入该函数（见 D 节）。

### src/ios/Agent/Intents/SendPromptIntent.swift（批次 2）
- 我方改动：struct 与 perform() 加 `@available(iOS 16, *)`、title 改 `Foundation.LocalizedStringResource`、dialog 截断改 `String(responseText.prefix(500))`；文件尾的 ShortcutNotification / NotificationNavigationStore / ShortcutNotificationDelegate 三个助手在 1.14 线被「搬家」到新文件 src/ios/Shared/ShortcutHelpers.swift（因被非 AppIntents 代码引用，不能随 AppIntents 一起门控）。
- 合并方式：SendPromptIntent.swift 取 1.15 本体、截断尾部（保留末尾 doc 注释与我方一致）、叠加我方 3 处改动，1.15 新增的 `import UIKit` 保留；ShortcutHelpers.swift 的搬家内容替换为 1.15 最新版尾部内容（NotificationCategoryCenter 类别注册、徽章走 noteUnseenNotification() 台账、user_ask 通知处理、openSession 重构），保留我方 imports 头与 ShortcutHelpers.extractResponseText 扩展。依赖 NotificationCategoryCenter.swift、UserAskCenter.swift、userIsAway、QuotaStore 均已核实存在。

### src/ios/Agent/Session/SkillStore.swift（批次 3 `ba3d598`）
- 合并方式：parse 签名合成 `nonisolated static func parse(skillMD rawContent:)`——我方 nonisolated + 上游新参数名及其 CRLF/BOM 归一化。SkillsManagementView 依赖的 isLoading 与 async importFromArchive 在我方改动内、已随批次 1 合入。

### src/ios/Shared/EnvVarStore.swift（批次 3）
- 合并方式：我方 init 后台延迟加载结构内补上游新增的 `self.stateBook = Self.loadStateBook()`（stateBook 有默认值、类为 @MainActor，无额外风险）。

### src/ios/Shared/AppLocalization.swift（批次 3）
- 合并方式：取上游带标签签名 `AppLocalized(resource:)`（上游源码断言测试 ComposerTypingLagTests 要求该签名原文，必须保留）；函数体保留我方 iOS 15 实现（经 LocalizedStringResourceBackport 的 typealias 走 AppBundle.current.localizedString）。已 grep 确认两边均无生产代码以无标签方式调用此重载。

### src/ios/Views/Chat/AssistantBlockView.swift（批次 3）
- 合并方式：switch 同位置双方各加一 case，`.vaultTool` 胶囊（我方）与 `.userAskTool` 卡片（上游新功能）并存。

### src/ios/Views/Chat/SessionSkillsView.swift（批次 4 `2e7e3b8`）
- 合并方式：上游 1.15 已把批量 Enable/Disable All 从工具栏移入 section header 的 SessionBulkToggleHeader、工具栏只剩 Done；取上游结构 + 我方 placement 改名 `.navigationBarTrailing`；NavigationView 已合入。

### src/ios/Views/Chat/ToolLiveSheet.swift（批次 4）
- 合并方式：vaultTool（我方）与 userAskTool（上游）两 case 并存。

### src/ios/Views/Chat/ChatMessageViews.swift（批次 4）
- 合并方式：分支头取上游新增的 `,!snapshotRendering` 条件；`.glassEffect` 调用保持我方删除（CI 的 Xcode 16.4 / iOS 18 SDK 无此 iOS 26 API，留着必然编译失败）；其余我方改动（contextMenuWithPreview、onGeometryChangeBackport、vaultTool 分享文本段）已干净合入。

### src/ios/Views/Chat/ChatInputBar.swift（批次 5 `9f3edb4`）
- 我方改动主体（build121 定案结构）大部干净合入：FlowLayout 改名 FlowLayout16 并加 `@available(iOS 16.0, *)` + 同名 FlowLayout 包装（15 走 LazyVGrid）、TrailingTileRows 新增、VideoFileTransferable 删除。
- 冲突 1（附件 chip 预览）：取上游 1.15 的 onPreview 回调重构（旧 per-chip sheet 已被上游删除；我方 NavigationStack→NavigationView 在新结构无对应点；上游源码断言要求 `.onTapGesture { onPreview()}`，合并后已确认 `let onPreview` 在位、无残留 showPreview）。
- 冲突 2（UserAttachmentList）：保留我方 `#available(16)/TrailingTileRows` 双分支结构，tileContent 助手补上游 1.15 的 fileTile searchKey 传参（ChatSearchUnitKey 构造，与上游内联版一致；fileTile 的 searchKey 参数有默认值 nil）。
- 冲突 3（PastableTextView）：iOS 16 版 `sizeThatFits(_:uiView:context:)`（ProposedViewSize）保留上游 1.15 新版（含 [T-composer-placeholder-room] minHeight 逻辑），方法上加 `@available(iOS 16, *)` 守卫（与本文件 FlowLayout16 同模式；我方 1.14 线是整段删除、靠 UIView 自身 intrinsicContentSize，15 上该方法本就不触发）。此判断另见 DECISIONS D5 待追认。
- 附带（批次 11）：文件内 1.15 新增的 AttachmentPreviewSheet（附件预览 sheet）NavigationStack→NavigationView、`.topBarTrailing`→`.navigationBarTrailing`，同模式处理。

### src/ios/Views/MCP/SessionMCPsView.swift（批次 6 `c170f6c`）
- 合并方式：同 SessionSkillsView 模式（上游批量开关已移入 SessionBulkToggleHeader，取上游 + placement 改名）。

### src/ios/Views/Providers/ModelGroupDetailView.swift（批次 6；审计批次 12 补一处）
- 合并方式：我方 secondaryAction→automatic、NavigationView 已合入；上游新增 `.scrollDismissesKeyboard(.immediately)` 保持我方略去（iOS 16+ API 在 15 无替身，与我方删 `.interactively` 版同理）。批次 12 另删该文件 1.15 新增 sheet 的 `.presentationDetents([.medium, .large])` + `.presentationDragIndicator(.visible)` 两行。
- 注：EnvironmentVariablesView 的 1.15 新徽章行含 `.fontWeight(.medium)`，该 API 为 iOS 13+ 可用，故保留上游（与我方 1.14 线曾删某处 .fontWeight 的处理不矛盾——那几处是随结构删除附带去掉的，非可用性问题）。

### src/ios/Views/Settings/EnvironmentVariablesView.swift（批次 6；审计批次 12–13 补两处）
- 合并方式：我方 scrollContentBackground/presentationDetents 删除与 AppLocalized 包裹已干净合入；行内容取上游 1.15 新版徽章行。批次 12/13：将 1.15 新增的多行值字段 `TextField("Value", text: $value, axis: .vertical)` 去 axis、`.lineLimit(1...8)` 改 `.lineLimit(8)`（我方同类字段在 1.14 线即无 axis 形式）。上游源码断言测试 ShortcutEnvVarTests 以原文断言 axis 写法，该断言在 15.4 适配下必然不成立，属不可避免（API 不存在），在此注明。

### src/ios/Views/Settings/MemoryManagementView.swift（批次 6）
- 合并方式：上游 1.15 把 iOS 17 检查移入 `showsForceSync` 属性（内部在 <iOS 17 时 return false），解除了我方当年整段删工具栏的 buildLimitedAvailability 障碍，故恢复上游工具栏 + placement 改名 `.navigationBarTrailing`（15/16 上该工具栏不渲染、17+ 恢复上游功能）。

### src/ios/Views/Providers/ProviderInstanceDetailView.swift（批次 6）→ DECISIONS D1
- 冲突 1（导出分享按钮）：保留我方 `.navigationBarItems(trailing:)` 并补上游新增的 quotaConsoleURL sheet（MinisLinkPreviewView）。
- 冲突 2（ModelEntryDetailSheet 工具栏）：按决策点规则保留上游 1.15，详见 DECISIONS D1。

### src/ios/MinisApp.swift（批次 7 `4f0bc0f`）
- 冲突 1（启动处）：合成上游新增 `QuotaStore.shared.start()` + 我方 `registerFileProviderDomain()` 的 `if #available(iOS 16.0, *)` 守卫。
- 冲突 2（回前台清徽章）：取上游 1.15 的 `BackgroundKeepAliveManager.shared.clearUnseenBadge()`（徽章台账模型），不用我方 1.14 的 `applicationIconBadgeNumber = 0`——台账模型已在 BackgroundKeepAliveManager 全面合入，直接清零会与「保留运行中任务数」的 1.15 计数行为打架；计数属上游行为、投递 API 才是平台适配。此判断另见 DECISIONS D6 待追认。

### src/ios/Minis.xcodeproj/project.pbxproj（批次 8 `3bb0061`）→ 另见 E 节
- 以 1.15 版为底手工叠加（弃用三方试合结果）：部署目标逐 target 改回我方设置（含工程级配置）、补登记 6 个我方文件引用。MinisTestHost 的部署目标为判断项，见 DECISIONS D2。

### deps/build_ffmpeg.sh（批次 1）
- 三方合入：保留我方已验证的 MacPorts 镜像回退（CI 基建），上游新改动一并合入。

### src/ios/Localizable.xcstrings（批次 1）
- 按并集口径合入：1.15 为底 + 我方中文译文补入，同 key 冲突保留 1.15 英文原文；合并后经 python json.load 校验通过。

## C. 拆分文件的语义迁移（4 文件，批次 9–11）

### src/ios/Agent/MessageList/CollectionViewMessageListV3.swift → CollectionViewMessageListV3/ 目录（批次 9 `e35b05f`）
我方 7 个 hunk 落点：
- `case .vaultTool: return "assistantVaultBlock"` → Cells/BridgedAssistantBlockV3.swift（在 .memoryTool 后插入）。
- `.contextMenu` → `.contextMenuWithPreview` ×2 → Cells/BridgedAssistantBlockV3.swift（Copy All 的零尺寸 overlay 处）、Cells/BridgedAssistantFooterV3.swift（同模式 overlay 处；Footer 另一处 Copy Error 的 contextMenu 我方未改、保持原样）。
- UIHostingConfiguration → HostingCellConfiguration ×5 → Coordinator/MessageListV3Coordinator+CellConfiguration.swift（五处 `let config = UIHostingConfiguration {...}.minSize...; cell.applyContentConfiguration(config)` 逐处改写为 `cell.applyContentConfiguration(HostingCellConfiguration(rootView: AnyView(...), hostParent: viewController))`，body 原样保留；HostingCellConfiguration 定义在已合入的 MessageListInfrastructure.swift）。
- `.toolbar(.visible, for: .navigationBar)` → `.pinnedNavigationBarVisible()` → Sheets/MessageListV3SheetPresenters.swift，helper extension 附于该文件末尾（与我方 1.14 附于原文件末尾同位）。

### src/ios/Views/Chat/SelectableMarkdownView.swift → Views/Chat/Markdown/ 目录（批次 9）
我方 5 个 hunk 落点：
- VideoAttachment 的 `generator.image(at:)`（iOS 16 异步 API）→ `copyCGImage(at:actualTime:)` → Markdown/Attachments/VideoAttachment.swift。
- SelectableMarkdownTextView 的 [ios15-size-hook] sizeThatFits/intrinsicContentSize 两个 override（逐字取自我方）→ Markdown/TextKit/SelectableMarkdownTextView.swift（插于 traitCollectionDidChange 之前）。
- makeUIView 内 [ios15-size-hook] 预提交 `updateUIView(textView, context: context)` → Markdown/Bridge/SelectableMarkdownView.swift（return textView 之前）。
- Regex 字面量 `markdown.ranges(of: /.../)` → NSRegularExpression 等价式（逐字取自我方）→ 同上文件。
- 链接长按 alert 的「Open in Safari」路由（minis:// 与 file:// 走 self.openURL）→ Markdown/Bridge/SelectableMarkdownView+Coordinator.swift（Coordinator 的 openURL 属性已核实存在）。
- 注：上游 1.15 自己把 representable 的 sizeThatFits 拆到 Markdown/Bridge/SelectableMarkdownView+Sizing.swift 并加了 `@available(iOS 16.0, *)`，与我方处理方向一致，未动。

### src/ios/Views/Chat/AIChatView.swift → Views/Chat/AIChatView/ 目录（批次 10 `fbf59d2`、10b `71dfc18`）
我方 37 个 hunk 全部落点（按目标文件）：
- AIChatView.swift（主文件）：删 `@State selectedPhotoItems`；handlePHPickerResults + loadVideoFileURL + loadImageData 三个函数（逐字）插于 hasOverlayPresented 之后；删 missingMinisFileName 状态与文档注释（配套 LinkAndDrop 改造）；onDrop 加 #available(iOS 16) 守卫（[T-ios154-drop-crash]）；locateDownloadTarget sheet NavigationStack→NavigationView；删「File Not Found」SwiftUI .alert 块；previewAudioFile sheet 删 detents/dragIndicator；showFileBrowser sheet 改 NavigationView；showBrowserSheet 加 onDismiss（vm.resumeFromBrowserTakeover()）；showModelPicker 改 NavigationView 并删 detents；showTokenUsage 删 detents；photosPicker+onChange 与 .fileImporter 两段整体替换为 MinisPHPicker / MinisDocumentPicker 两个 .sheet（逐字取自我方）；terminal fullScreenCover 改 NavigationView；Task.sleep(for: .milliseconds(900)) → nanoseconds；文件末尾逐字附 MinisPHPicker + MinisDocumentPicker 两 struct（MinisDocumentPicker 在我方 1.14 线亦为只定义未引用，与原线一致；MinisPHPicker 被已合入的 SoulSettingsView 引用，必须在位）；topBanners 的 onGeometryChange（1.15 新增点）改 onGeometryChangeBackport（批次 10 内）。
- 批次 10b：browseMinisFolder sheet（1.15 新增）NavigationStack→NavigationView。
- AIChatView+LinkAndDrop.swift：minisURL(fromFileLink:)/minisURL(fromRelativeLink:) 两助手 + [T-link-fallback-86] scheme 归一化段替换原 `guard url.scheme == "minis"`；文件缺失分支改调 presentFileMissingAlert（UIKit 呈现，[T-link-alert-89]），presenter 函数逐字迁入。
- AIChatView+InputBar.swift：onGeometryChange ×2 → onGeometryChangeBackport；Task.sleep 380×2、320×1 → nanoseconds。
- AIChatView+MessagesArea.swift：onGeometryChange ×1 → Backport。（基线 4 个 onGeometryChange 点与 NavBarModifiers 1 个合计 5 处，全部改完。）
- AIChatView+InputPopups.swift：.scrollIndicators(.visible) ×2 删除；InputBarPopupSurface 的 .glassEffect 一行删除。
- Composer/ComposerSurface.swift：.glassEffect ×2 删除（FloatingCircleButtonSurface、ComposerSurface）。
- AIChatView+NavigationTitle.swift：thinking level sheet 的 .presentationDetents([.medium]) 删除。
- Toolbar/NavBarModifiers.swift：.toolbarBackgroundVisibility 一行、.toolbarBackground 两行删除；onGeometryChange → Backport。
- Toolbar/ChatToolbarHost.swift：ChatToolbarHost 的 .topBarTrailing → .navigationBarTrailing；ChatTrailingMenuButton 的 ProposedViewSize 版 sizeThatFits 整段删除（同我方 1.14；同文件 1.15 新增的 AnchorView 版 sizeThatFits 在审计批次 12 改为 @available 标注，见 F 节）。
- Sheets/MoveToSessionSheet.swift、Sheets/SpeechLanguagePickerSheet.swift（languageCode 三处改 Locale.languageCode 等价式、删 detents、删一处 .fontWeight(.semibold)）、Sheets/CompactSummarySheet.swift（placements ×2、删 detents）、Sheets/TokenUsageSheet.swift（placement）、Sheets/ProviderImportPrompt.swift（删 detents + dragIndicator）：均 NavigationStack→NavigationView 及相应删除。

### src/ios/Views/ContentView.swift → Views/ContentView/ 目录 + Settings 两文件（批次 11 `bb0862b`）
我方 69 个 hunk 按系统落点：
- 导航回退系统（核心）：`navigationPath: NavigationPath` → `[String]`（ContentView.swift 状态、pendingBackgroundNavigation 元组类型）；commitNavigationPath 签名与全部调用点（ContentView+Navigation.swift、+SessionActions.swift 的 `navigationPath = []`）；+Layout.swift 的 splitLayout 改 HStack(spacing: 0)（侧栏 .frame(width: 320) + Divider，删 columnVisibility 状态与其 .navigationSplitViewColumnWidth）、stackLayout 改 NavigationView + 隐藏 NavigationLink(isActive:) + 新 stackDestinationView（destination 内容逐字保留 1.15 版，含 HangDetector 标记与长注释，仅换投递机制）；ContentView.swift 的 onChange 诊断里 `navigationPath.codable` 编码串改 `navigationPath.joined(separator: ",")`（仅诊断日志文本，等价）。NavDiag 助手签名连带改型，见 DECISIONS D3。
- 设置导航回退：Views/Settings/SettingsSheet.swift（1.15 已把 SettingsSheet 移出 ContentView）：navPath 改 `[SettingsDestination]`、NavigationStack(path:) 改 NavigationView + 隐藏 NavigationLink + settingsDestinationView/destinationView(for:) 两助手逐字迁入（已逐 case 核对 1.15 的 navigationDestination switch 与我方 destinationView 完全一致，含 .logs 的 onAppear 清理与 .mcpServerDetail 注释）；删 Done 工具栏；`navPath = NavigationPath()` → `[]`（append 调用对数组同义，未动）。
- 工具 sheet 与正文 sheet（ContentView.swift）：rootfsManagement / syncMigrationDetail 改 NavigationView + Done 改 .navigationBarItems；browserManagement 改 NavigationView；terminal fullScreenCover 改 NavigationView；.presentationDetents([.medium]) ×3 与 ([.medium, .large]) ×1 删除。
- 入门 sheet（ContentView+EmptyState.swift）：showAddProvider / showSelectModels 改 NavigationView；showRestoreBackup 改 NavigationView 且 Close 工具栏（.cancellationAction）改 .navigationBarItems(leading:)；.font(.title2.bold()) → .font(.title2).bold()。
- 侧栏工具栏（ContentView+SidebarToolbar.swift）：.topBarLeading ×1、.topBarTrailing ×2 改 navigationBar*。
- 会话行（Sidebar/SessionListRows.swift）：两 struct（SessionStackRow、SessionSplitRow）的 .draggable(session.id) → .onDrag { NSItemProvider(object: session.id as NSString) }（基线第 3 处 draggable 在文件夹分组行，1.15 已被上游并入这两个 struct，两处落点覆盖三处语义）；各加 .swipeActions（Delete/Select）与 sessionSwipeActionButtons 助手（逐行 struct 内实现，捕获自身 menuActions 通道，见 DECISIONS D4）；SessionSplitRow 内一处 UnevenRoundedRectangle → BackportUnevenRoundedRectangle。我方 1.14 的「删隐藏 NavigationLink(value:) + onTapGesture 打开」两 hunk 在 1.15 无落点：上游已用 Button + SessionMenuActionChannel(.open) 重构行导航（[T-nav-ghost-row-link]），行为等价，未硬塞（见 DECISIONS D4）。
- 分组头（ContentView+SectionHeaders.swift）：两处 .dropDestination(for: String.self) → .onDrop(of: [UTType.text], delegate: SessionFolderDropDelegate(...))（逐字取自我方两段替换）；SessionFolderDropDelegate struct 逐字附于该文件末尾；补 import UniformTypeIdentifiers。
- 远程会话（ContentView+RemoteSessions.swift）：NavigationLink(value: "remote:...") → NavigationLink(destination: AIChatView(sessionId:remoteDeviceId:))。
- 表面与玻璃（Sidebar/SidebarSurfaces.swift）：SearchBarSurface 的 iOS 26 分支改 `if false` + 注释（逐字同我方）；FABGlassMorphID 整体改 content + 注释；FolderSurface/FolderCardBackground 的 AnyShape → BackportAnyShape、UnevenRoundedRectangle → BackportUnevenRoundedRectangle（shape 与 dropShape 共 6 处构造）。
- MacOS27（Support/MacOS27GlassWorkaround.swift）：MacOS27OpaqueNavigationBar 的 body 简化为 content（逐字同我方，上游的 scrollEdgeEffectHidden/toolbarBackground 分支整体去掉）。
- FAB（ContentView+FAB.swift）：fabCircleSurface 的 .glassEffect 四行调用删除（分支其余部分保留 1.15 版）。
- 文件夹 sheet（Sidebar/FolderPickerSheet.swift）：NavigationStack→NavigationView；描述 TextField 去 axis: .vertical、.lineLimit(1...2) → .lineLimit(2)；删一处 .fontWeight(.semibold)；Cancel 工具栏改 .navigationBarItems(trailing:)。
- 删除/导出/编辑 sheet（Sheets/DeleteConfirmSheet.swift：NavigationView + .font(.subheadline.bold()) ×2、.font(.body.bold()) ×1 改 .font(...).bold()；Sheets/ExportPreviewSheet.swift：NavigationView + 删 Done 工具栏；Sheets/SessionEditSheet.swift：NavigationView + Cancel/Save 工具栏改 .navigationBarItems(leading:trailing:)，Save 的 .bold() 随之去掉——navigationBarItems 无 ToolbarItem 的 .bold() 等价修饰，与我方 1.14 一致）。
- 导出文本（ContentView+Export.swift）：导出头部分隔线一行位置前移（逐字同我方：紧随标题行、Model/Created 之前）。
- 外观（Views/Settings/AppearanceSettingsView.swift）：语言行 checkmark 的 .fontWeight(.semibold) 一行删除（基线 ContentView 内嵌版的同名 hunk 落点；该文件在 1.15 已独立）。
- AlarmKit（ContentView+Navigation.swift）：_fetchAlarmsImpl 函数体加 `#if canImport(AlarmKit)` 包裹（iOS 18 SDK 无 AlarmKit 模块，@available(iOS 26) 标注挡不住模块缺失，与我方 1.14 同处理；函数调用点已有 #available 守卫）。
- ContentView.swift 顶部补 import UniformTypeIdentifiers（onDrop 的 UTType 用）。

## D. 跨文件落点（不在 64 清单内、但因迁移必须改动的文件）

- src/ios/Agent/Chat/AIChatViewModel+Send.swift：retry() 守卫报错文案（我方 AIChatViewModel hunk 迁入，保留上游新增的 settlePendingStop 行）。
- src/ios/Agent/Chat/AIChatViewModel+DebugDumps.swift：kind 开关补 `.vaultTool: return "vault"`。
- src/ios/Agent/Chat/AIChatViewModel+AgentLoop.swift："No model configured" 处改 `errorMessage = noModelResolutionHint()`。
- src/ios/Agent/Jobs/SubAgentTermination.swift：`AIChatViewModel.toolWireName` 开关补 `.vaultTool(let a): "vault:\(a)"`。
- src/ios/Shared/ShortcutHelpers.swift：SendPromptIntent 尾部助手的搬家落点，内容更新为 1.15 版（见 B 节 SendPromptIntent）。
- src/ios/Views/Settings/SettingsSheet.swift、src/ios/Views/Settings/AppearanceSettingsView.swift：ContentView 拆分/移位后的落点（见 C 节）。
- 审计批次改动的 1.15 新文件清单见 F 节（均不在 64 内，逐个注明处理）。

## E. project.pbxproj 核对结果（批次 8）

以 1.15 版为底，仅叠加两类改动（diff 共 64 行，+47/−17，大括号平衡已验）：
1. 部署目标逐 target 改回我方 1.14 线设置（工程级 + 目标级共 16 处配置）：Minis（工程级 E51000070/71 + 目标级 E51000072/73）15.4、MinisShare 15.4、MinisFileProvider **15.0**、AgentWidgetExtension 15.4、MinisTests 15.4、MinisUITests 15.4、MinisTestHost 15.4（判断项，见 D2；1.15 原为 16.0，我方 1.14 线无此 target）。改后全文件已无 16.0/16.2/26.2 的 IPHONEOS_DEPLOYMENT_TARGET 残留（grep 计数 0）。MARKETING_VERSION 未动（1.15 版现值 1.15 与 1.0 条目均保留，按令不动版本号）。
2. 补登记 6 个我方文件（UUID 沿用我方 E5BP 段，1.15 中无冲突）：Shared/ShapeBackport.swift、LabeledContentBackport.swift、GeometryChangeBackport.swift、LocalizedStringResourceBackport.swift、ShortcutHelpers.swift、ShortcutRunTracker.swift——各含 PBXBuildFile + PBXFileReference + Shared 组 children + 两个 Sources 阶段（Minis 与 MinisUITests，与我方 1.14 线注册的两个 target 一致；相位 UUID 跨版本稳定已核对）。Shared 组为非同步组、必须显式登记；Terminal、MinisUITests、MinisTests、AIChatView、ContentView、Markdown、MinisTestHost、CollectionViewMessageListV3 为 PBXFileSystemSynchronizedRootGroup（磁盘文件自动纳入），故 MinisUITests 的 SmokeTests.swift 无引用条目属正常。我方 1.14 线另加的空 PBXGroup「Email」（E5EML00030）无功能作用，未搬。

## F. iOS 16+ API 审计（批次 12 `88b8e5b`、13 `51ef085`）

范围：src/ios 全部 Swift 源码（1.15 新增/大改文件为重点，含 64 清单外新文件）。模式类（参照 local-ios15-porting-availability skill）：NavigationStack / NavigationPath / NavigationSplitView / navigationDestination、.topBarLeading/.topBarTrailing、ProposedViewSize 与 representable 版 sizeThatFits、Layout 协议、onGeometryChange、scrollDismissesKeyboard、presentationDetents/presentationDragIndicator、scrollContentBackground、glassEffect、.fileImporter、UIHostingConfiguration、loadTransferable、setBadgeCount、AnyLayout、AnyShape/UnevenRoundedRectangle、.draggable/.dropDestination、PhotosPicker、Task.sleep(for:)、TextField axis、lineLimit 区间式、Regex 字面量、Language.languageCode、AppIntents、ShareLink、ViewThatFits、ContentUnavailableView、onScrollGeometryChange/containerRelativeFrame/scrollPosition、PhaseAnimator/KeyframeAnimator、symbolEffect、contentTransition、SwiftData/TipKit/Charts、NetworkExtension 入口。

处理结果：
- 已在合并中处理（不重复列）：64 文件内的全部命中（NavigationStack/Path、detents、glassEffect、onGeometryChange、UIHostingConfiguration、轴/区间 lineLimit、Regex、setBadgeCount 分流等），见 A–C 节。
- 审计新改（批次 12–13，均为 64 清单外的 1.15 新代码，全部套用既有守卫/替身模式）：
  - NavigationStack → NavigationView：Sheets/RetryLogSheet.swift（CollectionViewMessageListV3 拆分目录内）、Views/Chat/ChatShareSelectionView.swift ×2、Views/Chat/UserAskCardView.swift、Views/Providers/QuotaDetailSheet.swift、Views/Providers/UnifiedModelPicker.swift 的 1.15 新增 provider-edit sheet。
  - detents/dragIndicator 删除：RetryLogSheet、UnifiedModelPicker 的 quota sheet、ModelGroupDetailView 的图标 sheet（见 B 节）。
  - glassEffect 删除：ChatShareSelectionView 的 ChatShareFloatingButtonSurface 一行（iOS 26 分支内，与既往同理：符号不在 iOS 18 SDK 中）。
  - TextField axis 去除 + lineLimit 区间改上限值：UserAskCardView（3...8 → 8）、SubAgentRunDetail（1...4 → 4）、RootfsManagementView 的 DNS 字段（2...6 → 6）、EnvironmentVariablesView 值字段（1...8 → 8，见 B 节）。多行生长行为在 15.4 降级为单行，见 DECISIONS D7。
  - Layout 协议：SubAgentRunDetail 的 ChipFlow 按 ChatInputBar FlowLayout 同模式拆为 ChipFlow16（@available(iOS 16.0, *)）+ 同名 ChipFlow 包装（15 走 LazyVGrid adaptive 列），两处调用点未动。
  - representable sizeThatFits 加 `@available(iOS 16.0, *)`：ChatExportRenderer.swift（UILabel 版）、ChatToolbarHost.swift 的 AnchorView 版（与上游自家 SelectableMarkdownView+Sizing.swift 的标注法一致）。
  - AppIntents：1.15 新增 SaveEnvVarIntent.swift 补 `@available(iOS 16, *)`（struct 与 perform 两处）+ title 改 Foundation.LocalizedStringResource（同目录其他 Intent 的既有模式）；其余 import AppIntents 的文件逐个核过门控（含 @available(iOS 17.0, *) 的 RetryRunIntent、UserMessageEntity、AudioTogglePlaybackIntent，均完好）。
  - ShareLink → 按钮 + MinisShareSheet（UIKit 包装，全 App 通用）：ChatShareSelectionView 工具栏分享项（新增 @State shareSheetURL 与 .sheet 呈现，disabled 逻辑与图标不变）。
  - ViewThatFits → #available 分流、15 取第一候选：ChatExportRenderer 的副标题行（导出页宽固定，第一候选即单行版）、UserAskCardView 的按钮行（第一候选即单行布局）。见 DECISIONS D7。
  - symbolEffect / contentTransition：BrowserSheetView 已有 symbolEffectPulseIfAvailable 守卫、AgentLiveActivityWidget 整体 @available(iOSApplicationExtension 16.2, *)，均完好未动。
- 审计确认无需改动：
  - .fileImporter ×3（Providers/AddProviderView.swift、Providers/ProviderInstancesView.swift、Settings/BackupRestoreView.swift）：与我方 1.14 线出厂状态逐字一致（15.4 无回调问题出在 AIChatView 的多 sheet 叠加场景，该三处为独立设置页 sheet，我方线已验证保留），保留上游原样。
  - AnyShapeStyle ×5：iOS 15 起可用，且 1.14 基线与我方线计数一致，非问题。
  - .cancellationAction/.confirmationAction/.primaryAction 等 placement：iOS 15 起可用，非问题（仅 .topBarLeading/.topBarTrailing 为 16+，已全清）。
  - 上游源码断言测试（MinisTests/Standalone）以字符串断言上游源码原文（如 SheetKeyboardDismissTests 断言 .scrollDismissesKeyboard(.immediately) 在位、ShortcutEnvVarTests/UserAskDictationTests 断言 axis 写法、TopBannersTests 断言 onGeometryChange 原文）：这些断言对象均是 15.4 不存在的 API，适配后必然不成立，无法两全；App 本体不受影响，在此集中注明。
- 审计后复扫（生产代码、排除注释与测试）：NavigationStack 0、NavigationPath 类型引用 0（仅 commitNavigationPath 函数名保留）、glassEffect 调用 0、axis: .vertical 0、区间 lineLimit 0、.topBar* 0、ProposedViewSize 仅存于 @available(iOS 16) 标注的声明内、Layout 协议仅 FlowLayout16/ChipFlow16 两处且均已门控、冲突标记 `<<<<<<<` 全树 0。

## G. 提交清单（15 个合并提交，不含父代理的 71 文件搬入提交 1b47955）

1. `b5d1472` 批次 1：三方干净合入 41 文件
2. `983e64d` 批次 2：冲突解决 4 文件（+3 个跨文件落点）
3. `ba3d598` 批次 3：冲突解决 4 文件
4. `2e7e3b8` 批次 4：冲突解决 3 文件
5. `9f3edb4` 批次 5：ChatInputBar
6. `c170f6c` 批次 6：冲突解决 5 文件
7. `4f0bc0f` 批次 7：MinisApp
8. `3bb0061` 批次 8：project.pbxproj
9. `e35b05f` 批次 9：拆分迁移 I（CollectionViewMessageListV3、SelectableMarkdownView）
10. `fbf59d2` 批次 10：拆分迁移 II（AIChatView）
11. `71dfc18` 批次 10b：browseMinisFolder sheet 补改
12. `bb0862b` 批次 11：拆分迁移 III（ContentView）
13. `88b8e5b` 批次 12：审计修复 I
14. `51ef085` 批次 13：审计修复 II

（编号 1–14 为批次 1–13 与 10b 共 14 个代码提交，加上本日志与 DECISIONS 的文档提交（批次 14），合计 15 个提交。）

## H. 验证说明

- 本机为 Linux、无 Xcode，未做本地编译；验证手段为：三方试合逐 hunk 核验、每批 git diff 全量复核、关键结构（pbxproj 大括号平衡、拆分文件 brace 平衡、xcstrings JSON 校验）、全树模式复扫、vaultTool 全部引用点一致性核对（ChatModels 定义、+BackgroundTask、+SSEStream ×2、+DebugDumps kind、SubAgentTermination 的 toolWireName、AssistantBlockView、ChatMessageViews 分享段、ToolLiveSheet、BridgedAssistantBlockV3 的 "assistantVaultBlock" 标识，共 10 处）。
- 构建验证留待 CI（父代理环节）。

## CI 诊断（2026-11-03）
- run 41462912253 两次尝试均在同一位置静默失败：流式日志停在 SwiftDriverJobDiscovery「Compiling bridging header」，无任何 error 行，xcodebuild 退出码 65。仅改 CI 工作流（非 App 源码）：xcodebuild 输出落盘 build-xcodebuild.log、失败也上传 artifact（含 ~/Library/Logs/DiagnosticReports 拷贝），用于抓真实失败原因。

## CI 修复轮 1（2026-11-03，针对 run 41479264302 完整日志的 24 条错误）
诊断结论纠正：前两轮并非构建机中断——流式日志被截断，落盘日志显示真实编译错误 24 条 / 17 文件。逐项处理（全部带 [ios15-backport] 注释）：
- 合并损伤 2 处：UserAskCardView 删除重复 else 块（10 行）；SettingsSheet 删除重复的 @State showFeedbackDialog 声明。
- ToolFoldPlanner：我方独有枚举 case .vaultTool（凭证保险库）加入可折叠工具组（上游 1.15 无此 case，其 switch 因此不穷尽）。
- MinisApp：ShortcutRunTracker（上游标 iOS 16+）调用点加 #available 守卫，iOS 15 不跑孤儿扫描。
- HelperRunner：SendPromptIntent.extractResponseText 加 #available 分支，iOS 15 走既有 ShortcutHelpers 同名实现。
- ChatExportRenderer：UITextView.textLayoutManager（iOS 16+）两处改走 textViewUsesTextKit1() 助手（15 上恒为 TextKit 1，与上游判空等价）。
- ContentView+SessionList：navigationSplitViewColumnWidth 改 15 守卫版（15 上保持默认列宽）。
- AlwaysOnOverlay：persistentSystemOverlays 改 15 守卫版（15 上无对应 API、保持系统默认）。
- ToolLiveSheet：contextMenu(preview:) 改 ToolPreviewContextMenu15 修饰符（15 上同菜单、无预览卡）。
- ScheduledTaskDetailView：accessibilityActions 改 RunNowAccessibility15 修饰符（15 上用具名无障碍动作，条件相同）。注：MinisTests 的 ScheduledRunNowTests 有一处源码字符串断言与此不符，该测试不在出包构建路径内。
- UnifiedModelPicker 两处 ViewThatFits：按工程内既有 15 替身模式（ChatExportRenderer/UserAskCardView）加 #available 分支，15 上固定第一候选（单行）。
- ChatToolbarHost / MemoryManagementView：工具栏内条件 ToolbarItem 在 15 工具链下与两个 toolbar(content:) 重载歧义；改为 item 常驻、条件移入 item 内部（隐藏时为空）。
- BackgroundKeepAliveManager：BGContinuedProcessingTask 为 iOS 26 API、iOS 18 SDK 中不存在；submitContinuedTask / continuedTaskStarted / tickContinuedProgress 三个函数、evaluate 内的提交调用、finishContinuedTask 的完成尾段全部加 #if compiler(>=6.2) 编译期守卫。iOS 15 上该功能本就被 #available(iOS 26) 挡住，行为不变。
- ContentView：body 为约 880 行单一修饰链，Swift 6.1 类型检查超时；拆为 bodyBase + body 两段，修饰符与顺序逐字不变。
