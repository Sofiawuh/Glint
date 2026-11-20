# 自定义截图快捷键实施计划

对应规格：[自定义截图快捷键录制设计](../specs/2026-11-20-screenshot-hotkey-recorder-design.md)

## 目标

在不改变截图、划词、弹窗和 Azure 调用链的前提下，把固定 `⌃⌥E` 改为基础设置页可直接录制、立即生效、重启持久化的截图快捷键。所有切换失败必须保留当前可用快捷键。

## 任务 1：先建立黑盒契约

由全新独立测试代理新增 `glint-app/hotkey_tests.swift`，只定义公开行为，不读取真实配置或 Azure Key。

覆盖：

- 默认值、修饰键标准化、显示顺序和特殊键显示。
- 非法组合、Escape、Forward Delete、Backspace 的录制决定。
- AppConfig 旧 JSON 缺少快捷键字段时的兼容迁移与 Azure 字段保留。
- Codable 保存/加载快捷键。
- 注册失败、保存失败、旧键注销失败、候选清理失败时的事务结果。
- 候选注册后未提交前不可触发截图。
- 当前快捷键在录制态被转发为相同值，而不是执行截图。

先运行最小 `swiftc` 测试命令并确认失败原因准确落在缺失的新契约。

## 任务 2：实现快捷键领域层

新增 `glint-app/ScreenshotHotKey.swift`：

- `ScreenshotHotKey`：键码、Carbon 修饰键、默认值、标准化、合法性、Codable、当前键盘布局显示。
- 录制输入决定：提交、取消、恢复默认、继续等待、非法后继续录制。
- 特殊键稳定显示；Escape、Forward Delete、Backspace 保留为录制控制键。

修改 `glint-app/Config.swift`：

- `AppConfig` 增加 `screenshotHotKey`。
- 显式 `Codable` 解码缺失字段为默认值。
- `load()` 同步快捷键字段。
- 提供可回滚的快捷键配置更新入口，同时保留现有 Azure 保存行为。

运行领域与配置测试，先让模型/迁移相关用例转绿。

## 任务 3：实现 Carbon 生命周期与切换事务

新增 `glint-app/HotKey.swift`，从 `main.swift` 移出固定热键封装：

- 检查 `InstallEventHandler` 与 `RegisterEventHotKey` 的状态。
- 注册失败清理 action。
- `invalidate()` 可观察、幂等，成功后才移除 action。
- 支持已注册但未激活的候选实例。
- 强持有注销失败的活动或候选实例。

实现可测试的 `ScreenshotHotKeyManager`：

- 启动时注册保存值，失败后回退默认值。
- 候选先注册为未激活，再保存配置、注销旧键、激活候选。
- 保存、注销或补偿失败时按规格恢复，并在极端状态锁定继续修改。
- 录制期间把当前热键事件转发给录制器，不执行截图。

运行真实 Carbon 冲突测试与事务状态测试。

## 任务 4：实现原生录制控件与设置接线

新增 `glint-app/HotKeyRecorderControl.swift`：

- 原生 `NSControl`，支持焦点环、录制态、悬停态和紧凑符号显示。
- 点击后捕获键盘输入；非法普通键显示行内错误并继续录制。
- Escape 取消；Forward Delete/Backspace 恢复默认。
- 失焦或窗口关闭取消录制并恢复当前值。

修改 `glint-app/Settings.swift`：

- 基础页增加录制控件、说明和行内状态。
- 通过 `AppDelegate`/`ScreenshotHotKeyManager` 开始录制桥接和提交候选。
- 每次打开设置时刷新当前有效快捷键。
- 设置 UI 自测覆盖录制状态、相同值、取消、恢复默认、失败提示和布局。

修改 `glint-app/main.swift`：

- `AppDelegate` 持有并启动 `ScreenshotHotKeyManager`。
- 截图回调仍进入现有 `onScreenshotExplain()`。
- 权限提示动态显示当前快捷键。

## 任务 5：同步构建和文档

- 将新 Swift 文件加入 `glint-app/build.sh` 编译源列表。
- README、PROJECTS、安装说明和架构文档把固定 `⌃⌥E` 改为“默认快捷键”或动态设置说明。
- 不修改 Azure 协议、弹窗生命周期和截图实现。

## 任务 6：完整验收

依次运行：

- 快捷键黑盒测试。
- Azure、Popup、Geometry、Markdown 既有测试。
- 全源 macOS 12 Swift typecheck。
- `git diff --check`。
- 设置页 UI 烟测。
- 使用 `Glint Self Signed` 构建 Universal App 和 DMG。
- 停止旧进程、替换 `/Applications/Glint.app`、重新启动。
- 验证签名 designated requirement、`arm64 + x86_64`、进程、`AX_TRUSTED=true`、事件 tap 和当前快捷键注册日志。
- 手工切换一个非默认快捷键并重启验证持久化，再恢复用户选择的最终快捷键。

## 任务 7：独立审查与交付

- 由独立只读代理按 P0/P1/P2 审查代码、测试、回滚语义和 UI。
- 修复所有 P0/P1/P2 后再提交。
- 推送功能分支，检查 GitHub 差异与 CI；确认无误后按用户既有授权合并 `main`。
