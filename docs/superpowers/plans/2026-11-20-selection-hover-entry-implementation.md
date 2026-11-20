# 文本选区微型悬停入口实施计划

对应规格：[文本选区微型悬停入口设计](../specs/2026-11-20-selection-hover-entry-design.md)

## 目标

把“拖动超过阈值后直接显示翻译/提问胶囊”替换为“确认有效文本选区后显示微型入口，用户明确移入并悬停后才展开动作”。同时从选区证据和 Accessibility 控件角色两层排除滚动条、列宽、滑块、分隔条等非文本拖动，不改变 Azure、截图快捷键、会话窗口、图钉和恢复语义。

## 任务 1：由全新独立测试代理建立黑盒契约

新增领域测试，测试代理只依据规格定义外部行为，不读取真实 Azure 配置，也不为现有实现细节拼凑断言。

- `glint-app/selection_detection_tests.swift`：覆盖有效选区变化、空文本、零长度范围、旧选区未变化、控件角色及祖先排除、剪贴板降级资格。
- `glint-app/selection_entry_lifecycle_tests.swift`：覆盖入口初显不自动展开、明确移入、`180 ms` 展开、`400 ms` 收回、重新进入取消收回、代际令牌、新选区替换、外部点击和动作提交。
- 扩展 `glint-app/geometry_tests.swift`：覆盖真实选区右下角锚定、右侧空间不足时移到左侧、底部夹紧、负坐标外接屏、展开方向和连续命中区域。

先使用最小 `swiftc` 命令分别编译运行，确认失败原因准确落在缺失的新领域契约，并保存红灯输出。

## 任务 2：实现选区快照与纯判定层

新增 `glint-app/SelectionDetection.swift`：

- 定义 `SelectionSnapshot`、按下前选区指纹、AX 角色路径和候选结果。
- 将“文本是否非空、范围是否非零、选区是否变化、角色是否排除、是否允许剪贴板降级”实现为不依赖 AppKit 窗口的纯判定函数。
- 排除滚动条、滚动条拇指、Slider、Splitter、Incrementor、列头、行头、标尺、调整柄、工具栏拖动区和窗口调整区。
- 信息不足时返回忽略；只有合格文本角色且不属于控件拖动时才允许模拟 `⌘C`。

新增 `glint-app/AccessibilitySelectionReader.swift`：

- 鼠标按下时通过 Accessibility 命中测试记录前台应用、元素身份、角色祖先链和旧选区指纹。
- 鼠标释放后优先读取 `kAXSelectedTextAttribute`、`kAXSelectedTextRangeAttribute`、`kAXBoundsForRangeParameterizedAttribute`。
- AX 只有文本没有边界时保留释放点兜底；AX 无法取词但允许降级时才调用现有剪贴板复制逻辑。
- 日志只记录判定路径、角色和是否取得范围/边界，不记录完整选中文字。

运行选区检测测试，确认判定层转绿。

## 任务 3：实现入口生命周期和几何

新增 `glint-app/SelectionEntryLifecycle.swift`：

- 状态为 `hidden`、`marker`、`hoverPending`、`expanded`、`collapsePending`。
- 创建入口后必须先观察到明确鼠标移动和从外部进入，不能因为释放点位于入口附近自动展开。
- 悬停 `180 ms` 展开；离开统一命中区域 `400 ms` 收回；重新进入取消收回。
- 所有延迟转换携带代际令牌，旧选区计时器不能修改新入口。
- 新选区、外部点击、Escape、动作提交和选区失效按规格隐藏或替换。

扩展 `glint-app/Geometry.swift`：

- 新增纯几何结果，包含微型入口矩形、展开胶囊矩形、展开方向和连续悬停命中区域。
- 优先使用 AX 选区联合边界右下角；无边界时使用释放点。
- 在右侧空间不足时把入口放到选区左下侧，并在所有方向夹紧 `visibleFrame`。

运行生命周期和几何测试，确认全部转绿。

## 任务 4：实现专用非激活入口面板

新增 `glint-app/SelectionEntryController.swift`：

- 持有一个专用 borderless、non-activating `NSPanel`，同一窗口内切换微型入口和展开胶囊。
- 微型入口绘制约 `16 × 16 pt` 赤陶色圆角方块与白色四角星芒，命中区约 `22 × 22 pt`。
- 展开态复用现有 `ActionPillButton` 的视觉和动作含义，但入口面板不调用 `NSApp.activate` 或 `makeKeyAndOrderFront`。
- 通过局部/全局鼠标移动事件驱动生命周期；入口与按钮之间使用连续命中区域。
- 点击翻译或提问时先关闭入口，再把不可变快照交给现有 `PopupController` 的公开动作入口。
- 提供无需联网的 UI 自测模式，输出微型入口和悬停展开两张快照。

调整 `PopupController`：

- 移除旧的“选区后直接显示完整胶囊”入口职责。
- 提供接收文本并启动翻译、接收文本并打开提问卡片的窄接口。
- 保持现有内容窗激活、图钉、恢复、流式请求和代际隔离逻辑不变。

## 任务 5：重接全局事件 Tap

修改 `glint-app/main.swift`：

- 事件 Tap 增加鼠标移动和 Escape 所需事件，但回调继续只做轻量采集与主线程派发。
- 左键按下时先处理入口/内容窗外部点击，再记录按下选区上下文。
- 左键释放时异步读取释放后选区，只有判定成功才请求 `SelectionEntryController` 展示入口。
- 非文本拖动不得进入剪贴板复制降级；普通点击和未变化选区不得刷新入口。
- `PopupController` 被钉住时忽略新选区；入口面板内部点击不能被识别为外部点击或新划词。
- `gFetchInFlight` 继续保护可能使用剪贴板的读取链路，CGEventTap 不同步等待。

## 任务 6：构建接线与文档同步

- 把新增 Swift 文件加入 `glint-app/build.sh` 的 Universal Binary 编译源列表。
- 更新 `README.md`、`PROJECTS.md`、`docs/architecture/overview.md`、`docs/runbooks/build-and-verify.md`、`CHANGELOG.md` 和 DMG 安装说明中的划词交互。
- 不修改 Azure Endpoint/Key、截图快捷键配置或用户现有 `⌃⇧Q` 保存值。

## 任务 7：完整验收

依次执行：

- 新增的选区检测、入口生命周期和几何黑盒测试。
- Azure、Popup、快捷键、Carbon、Markdown 既有测试。
- 全源 macOS 12 Swift typecheck、`git diff --check`。
- UI 自测输出微型入口和展开胶囊快照并检查窗口未激活语义。
- 使用 `Glint Self Signed` 构建 `arm64 + x86_64` Universal App 和 DMG。
- 停止旧进程、替换 `/Applications/Glint.app`、重新启动。
- 验证签名 designated requirement、双架构、进程、辅助功能授权、事件 Tap、截图快捷键注册和运行日志。
- 手工验证网页/TextEdit 选区；Excel 和浏览器横向滚动条、列宽调整不得误触发。

## 任务 8：独立审查、GitHub 与合并

- 由独立只读代理按 P0/P1/P2 审查代码、测试、焦点行为、AX 降级和多屏几何。
- 修复全部 P0/P1/P2；重复审查直到返回 `APPROVE`。
- 提交功能代码，推送 `feature/selection-hover-entry`，创建并检查 Pull Request。
- 确认 GitHub 差异和检查结果无误后，按用户既有授权合并 `main`。
