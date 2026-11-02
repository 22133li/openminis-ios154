# Minis v1.15 迁移决策点（待父代理/用户拍板）

规则：以下各点在合并时一律未自行改变上游行为——能保留上游 1.15 的保留上游；属平台强制适配的，用与 1.14 线一致的既有模式做了最小处理并在此报备。每点给出方案 A（当前树状态）与方案 B（备选）及影响，供翻案。

## D1 ProviderInstanceDetailView：ModelEntryDetailSheet 工具栏恢复（保留上游 1.15）
- 文件：src/ios/Views/Providers/ProviderInstanceDetailView.swift（批次 6）。
- 我们 1.14 线：把该 sheet 的 Cancel/Save 工具栏整段删除（16 行，连同 .scrollDismissesKeyboard(.interactively)、presentationDetents 一并删，无替代实现）。
- 上游 1.15：改动了同一工具栏——按钮动作加 `Self.endEditing()`（iPad sheet 键盘崩溃修复 [T-ipad-sheet-keyboard-crash]），scrollDismissesKeyboard 改 `.immediately`。
- 冲突点：同一代码区两种改法不能叠加（我方是整段删除，上游是在其上做功能修复）。按决策规则①保留上游 1.15：工具栏恢复，仅做平台必需处理——placement 改名为 .navigationBarLeading/.navigationBarTrailing（15.4 编译）、略去 `.scrollDismissesKeyboard(.immediately)` 一行（iOS 16+ API，15 无替身）。
- 方案 A（当前）：工具栏在位（15.4 上 Cancel/Save 可用，endEditing 修复在位）；代价：偏离我方 1.14 线的已验证状态（当年删工具栏的原因未在日志中留档，若是 15.4 上工具栏有具体故障，恢复后可能复现）；且上游源码断言测试 SheetKeyboardDismissTests 对该 sheet 断言 `.scrollDismissesKeyboard(.immediately)` 原文在位，本适配下不成立（API 不存在，不可两全）。
- 方案 B：恢复我方整段删除。影响：丢掉上游的 iPad 键盘崩溃修复与 sheet 内 Cancel/Save（改走滑动关闭/系统手势），与 1.14 线行为一致。

## D2 project.pbxproj：MinisTestHost 部署目标设为 15.4（判断项）
- 文件：src/ios/Minis.xcodeproj/project.pbxproj（批次 8）。
- 背景：MinisTestHost 是上游 1.15 新增 target，我方 1.14 线无对照值（1.15 原为 16.0）。合并时跟随 MinisTests/MinisUITests 的模式一并设为 15.4，已在 MERGE-LOG E 节显式记录。
- 方案 A（当前）：15.4——测试宿主与被测 App 同部署目标，15.4 真机可跑测试。
- 方案 B：改回 16.0——若父代理不打算在 15.4 上跑 MinisTests，16.0 更贴上游原意；不影响 App 本体六个 target 的部署目标。

## D3 ContentView 导航回退连带改写 NavDiag 诊断助手（强制适配，待追认）
- 文件：src/ios/Views/ContentView/ContentView+Navigation.swift（批次 11）。
- 背景：我方核心回退把 `navigationPath` 的类型由 NavigationPath 改为 [String]。上游 1.15 新增的 NavDiag 诊断子系统（ids/describe/write/observe 四个静态函数）以 NavigationPath 为参数类型、并用 `path.codable` 做 JSON 往返提取元素 id——该类型在 15.4 不存在，助手无法原样保留。
- 当前处理：四函数签名改 [String]；ids() 简化为恒等返回（数组本身即自底向上的 id 列表，与原 codable 往返的结果等价）；describe/write/observe 的日志格式与判定逻辑逐字保留；正文 onChange 里另一处 codable 诊断串改 joined(separator:)（仅日志文本）。
- 方案 A（当前）：诊断子系统完整保留、行为等价。
- 方案 B：整段移除 NavDiag 及其调用点。影响：丢掉上游 1.15 的导航诊断能力（[NavDiag] 日志、未授权路径写入检测），其余功能无差。

## D4 会话行：滑动操作与行导航的落点变化（待追认）
- 文件：src/ios/Views/ContentView/Sidebar/SessionListRows.swift（批次 11）。
- 背景：上游 1.15 把会话行重构为独立 struct（SessionStackRow / SessionSplitRow），行导航改走 Button + SessionMenuActionChannel(.open)，并已自行移除隐藏 NavigationLink(value:)（[T-nav-ghost-row-link]，附了详细的幽灵行 bug 考证）。
- 我方 1.14 的四个相关 hunk 处理：①删隐藏 NavigationLink(value:)——上游已删，无落点，未硬塞；②onTapGesture 调 openSession——上游的 .open 通道即等价机制，无落点，未硬塞；③.draggable → .onDrag——两 struct 各一处落点（基线第三处在文件夹分组行，已被上游并入这两 struct，语义覆盖）；④微信式左滑 Delete/Select（.swipeActions + sessionSwipeActions 助手）——在两 struct 内以 sessionSwipeActionButtons 助手重新实现（捕获各行自身的 menuActions 通道与 session.id，动作走同一 .delete/.select 通道、删除仍走同一确认 sheet 流程），并挂在 .onDrag 之后，与我方 1.14 的链上位置一致。
- 方案 A（当前）：左滑操作在 1.15 新行结构上保留，机制等价。
- 方案 B：去掉 .swipeActions（只留 .onDrag）。影响：15.4 上失去左滑删除/选择入口（长按菜单里仍有同名动作），更贴上游 1.15 原貌。

## D5 ChatInputBar：PastableTextView 的 iOS 16 版 sizeThatFits 保留 + @available 标注（待追认）
- 文件：src/ios/Views/Chat/ChatInputBar.swift（批次 5）。
- 背景：我方 1.14 线把该方法整段删除（靠 UIView 自身 intrinsicContentSize）；上游 1.15 给该方法加了新逻辑（[T-composer-placeholder-room] minHeight）。15.4 运行时永不调用此方法（iOS 16+ UIViewRepresentable 要求），保留与删除在 15.4 上行为一致；差别在 16+ 行为与未来维护。
- 当前处理：保留上游 1.15 方法体，加 `@available(iOS 16, *)`（与本文件 FlowLayout16 及上游自家 SelectableMarkdownView+Sizing.swift 的标注法一致）。
- 方案 A（当前）：16+ 用上游新逻辑；15.4 与 1.14 线行为一致（方法不触发）。
- 方案 B：恢复我方整段删除。影响：16+ 丢上游 placeholder-room 修复；与上游的偏离面更大。

## D6 MinisApp：回前台清徽章取上游台账模型（待追认）
- 文件：src/ios/MinisApp.swift（批次 7）。
- 背景：我方 1.14 线回前台时直接 `applicationIconBadgeNumber = 0`；上游 1.15 改为台账模型 `BackgroundKeepAliveManager.shared.clearUnseenBadge()`（只清「未读」部分、保留运行中任务计数）。
- 当前处理：取上游 1.15（台账模型已在 BackgroundKeepAliveManager 全面合入，直接清零会与其计数行为打架；计数语义属上游行为、投递 API 才是平台适配——投递点已在 BackgroundKeepAliveManager 内按 #available 分流）。
- 方案 A（当前）：回前台后徽章 = 运行中任务数（上游 1.15 行为）。
- 方案 B：恢复直接清零。影响：与台账模型不一致，BackgroundKeepAliveManager 后续按台账重算时可能把徽章再改回去，出现闪烁/不一致。

## D7 1.15 新功能的两处降级（多行输入与 ViewThatFits，待追认）
- 涉及：Views/Chat/UserAskCardView.swift、Views/Chat/AIChatView/Sheets/SubAgentRunDetail.swift、Views/Rootfs/RootfsManagementView.swift、Views/Settings/EnvironmentVariablesView.swift（TextField axis）；Views/Chat/ChatExportRenderer.swift、Views/Chat/UserAskCardView.swift（ViewThatFits）。均属审计批次 12–13。
- 背景：`TextField(axis: .vertical)` 与区间 lineLimit、ViewThatFits 均为 iOS 16+，15.4 无同名替身。我方 1.14 线对同类字段（文件夹描述）的既有处理就是去 axis + lineLimit 改单值。
- 当前处理：TextField 去 axis、lineLimit 区间改上限单值（输入、提交、校验逻辑全保留，仅多行自动生长降级为单行横向滚动）；ViewThatFits 用 #available 分流，15.4 固定取第一候选布局（导出副标题的单行版、提问卡的单行按钮排——均为上游设计的第一候选，仅在极窄宽度/超大字体时失去自适应换行）。
- 方案 A（当前）：功能完整、布局在常规宽度下与上游一致。
- 方案 B：为多行字段换 UITextView 包装（PastableTextView 式）恢复多行生长。影响：改动面大、样式需逐个对齐（背景、占位符、焦点行为），且偏离「最小改动」；ViewThatFits 无对应替身，B 对其不适用。
