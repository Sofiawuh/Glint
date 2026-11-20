# 跨应用文本选区兼容层实施计划

## 目标

在不使用应用白名单的前提下，让 Safari、Chrome、微信、企业微信、VS Code 和标准文本应用中的鼠标文本选区都能显示现有右下角入口，同时继续排除桌面文件、图标、滚动条、列宽、滑块、分隔条和窗口调整操作。

## 约束

- 遵守 [跨应用文本选区兼容层设计](../specs/2026-11-20-cross-app-selection-compatibility-design.md)。
- 严格 TDD：先由全新独立测试代理人只修改测试并确认红灯，再由主代理人修改生产代码。
- 不读取、输出或记录用户真实选中文本、聊天内容、Azure Key、Endpoint 或请求正文。
- 不更改当前截图快捷键 `⌃⇧Q`。
- 每次源码改动后都使用 `Glint Self Signed` 构建、替换 `/Applications/Glint.app` 并验收。
- 最终提交前必须由独立只读代理人审查，P0/P1/P2 均为零。

## 任务 1：独立黑盒契约红灯

**文件：**

- 修改 `glint-app/selection_detection_tests.swift`。
- 视交付结果必要时新增 `glint-app/selection_compatibility_tests.swift`。

**步骤：**

1. 对候选选区排序建立纯数据契约：焦点元素无结果、命中元素或父级 WebArea 有结果时应选择后者；范围 + 边界优先于仅有文本。
2. 对剪贴板降级准入策略建立契约：未知角色上的明确拖选、双击和三击允许；零位移单击拒绝。
3. 验证排除角色永远不允许剪贴板降级。
4. 验证剪贴板没有新变更、文本空白、包含文件 URL/文件列表/图像类型时拒绝。
5. 验证 clipboard-only 快照保留来源应用、使用鼠标释放点，且相同文本与应用不重复触发。
6. 先运行新测试并保留缺失类型/决策的准确红灯输出。

## 任务 2：纯选区候选与降级策略

**文件：**

- 修改 `glint-app/SelectionDetection.swift`。

**步骤：**

1. 新增可测试的候选数据结构与排序函数，不引用 `AXUIElement`。
2. 将现有排除角色判断收敛为候选与剪贴板降级共用的纯函数。
3. 实现鼠标手势、角色链、剪贴板变更和类型集合综合决策。
4. 扩展 snapshot/evidence 模型以标识 AX 或 clipboard-only 来源，但不将原文或指纹写入日志。
5. 运行任务 1 新测试直至全绿。

## 任务 3：多层 Accessibility 候选读取

**文件：**

- 修改 `glint-app/AccessibilitySelectionReader.swift`。

**步骤：**

1. 将命中测试返回的释放元素与角色链一起保留。
2. 收集焦点元素、释放点命中元素及各自有限父链，根据元素身份去重。
3. 对每个候选读取文本、范围和边界，交给纯排序策略选择最佳结果。
4. 保持前台应用身份、元素身份、Quartz 边界和释放点坐标一致。
5. 类型检查 arm64 与 x86_64 macOS 12 目标。

## 任务 4：剪贴板结果与主控接线

**文件：**

- 修改 `glint-app/main.swift`。
- 必要时新增剪贴板快照的纯数据辅助类型文件并加入 `glint-app/build.sh`。

**步骤：**

1. 让取词降级返回“是否产生新 changeCount、纯文本、本次剪贴板类型集合”，而不只返回字符串。
2. 依据任务 2 策略判断是否接受 clipboard-only 快照。
3. 只有降级准入时才发送内部标记的 `⌘C`，无论结果如何都恢复剪贴板。
4. 保持选区观察代际门禁；旧复制结果不得替换新选区。
5. clipboard-only 入口在新鼠标按下、Escape、用户键盘输入和前台应用切换时直接作废。
6. 日志仅记录路径、角色、范围/边界布尔值和降级决策，不记录文本。

## 任务 5：文档与回归

**文件：**

- 修改 `README.md`、`PROJECTS.md`、`CHANGELOG.md`。
- 修改 `docs/architecture/overview.md`、`docs/runbooks/build-and-verify.md`。

**步骤：**

1. 记录多层 AX 搜索、受保护剪贴板降级和非文本对象排除。
2. 运行全部选区、几何、样式、生命周期、键盘、Markdown、Azure、Popup 和快捷键回归。
3. 运行 arm64 与 x86_64 macOS 12 全源类型检查及 `git diff --check`。

## 任务 6：固定签名安装与应用矩阵

1. 使用 `bash build.sh 'Glint Self Signed'` 构建 Universal App 与 DMG。
2. 安全备份旧 `/Applications/Glint.app`，替换并重启。
3. 验证签名、Designated Requirement、`arm64 + x86_64`、进程、`AX_TRUSTED=true`、Event Tap 和快捷键仍为 `⌃⇧Q`。
4. 使用非敏感测试文本完成 Safari、Chrome、微信、企业微信、VS Code、TextEdit 和 Finder 桌面验收矩阵。
5. 核对日志不含选中文本、聊天内容、Endpoint、Key 或请求正文。

## 任务 7：独立复审、提交与集成

1. 由独立只读代理人复审最新 diff，必须输出 `APPROVE` 且 P0/P1/P2 全为零。
2. 修复所有 P0/P1/P2 后重复完整测试、构建、安装与复审。
3. 提交功能代码、测试与文档。
4. 推送 `fix/cross-app-selection-compatibility`，创建 PR，检查 GitHub diff 与 checks，确认无误后合并 `main`。
