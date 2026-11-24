# 翻译工作台自适应尺寸实施计划

> 设计依据：[spec.md](spec.md)
> 状态：实施中

## 1. 建立红灯契约

- 由全新上下文的独立测试 Agent 只依据规格编写测试。
- 使用虚构短文、中等邮件和长文样本。
- 覆盖推荐高度、屏幕安全边距、View 不自行改 frame、手动缩放优先、body 与 panel 同步，以及动画/恢复后的 autoresizing。
- 在不修改生产代码的情况下运行并保存红灯结论。

## 2. 分离推荐高度与实际 frame

- 保留 `TranslationWorkspaceView` 的推荐高度计算能力。
- 将推荐高度改为 430–760 pt 的量化连续策略。
- `configure()`、`updateTexts()`、`updateReports()` 和编辑回调不再修改 `frame.height`。
- 暴露完整内容更新后的推荐高度变化回调；普通逐字编辑只更新推荐值，不触发窗口跳动。

## 3. 将面板设为唯一尺寸所有者

- 新翻译保留保存宽度，但初始高度只按当前内容与屏幕安全范围计算。
- `PopupController` 接收完整内容更新后的推荐高度。
- 未发生手动缩放时，按顶部锚点计算目标 frame，并在当前屏幕可见区域内平滑扩缩。
- 程序化调整更新 `programmaticSize`，不得被 `windowDidEndLiveResize` 误判为用户操作。
- 手动缩放后设置 `userResized`，当前窗口停止内容驱动的尺寸变化。

## 4. 统一 active body 同步

- 增加一个只负责翻译工作台的同步函数，将 active body frame 设为 paper bounds，并确保 `.width`、`.height` autoresizing。
- 在初次安装、窗口缩放、缩放结束、隐藏恢复、当前窗口恢复和展示动画完成时调用。
- 展示动画 completion 即使过期，也先恢复其 body 的 frame/mask，再决定是否更新 active body。
- 过期动画不得覆盖当前工作台。

## 5. 回归、构建与发布

- 将独立测试从红灯修复到绿灯，并运行现有翻译工作台、AI 排版和布局策略契约。
- 执行 `arm64` 与 `x86_64` 类型检查。
- 更新架构活文档、CHANGELOG 和规格状态。
- 构建 Universal `Glint.app` 与 `Glint.dmg`，使用 `Glint Self Signed` 签名并验证。
- 备份并安全替换 `/Applications/Glint.app`，重新启动。
- 使用虚构内容完成短、中、长文本以及手动拉伸、历史切换、隐藏恢复的隔离 UI smoke。
- 精确提交生产修改，推送功能分支，创建 PR，并使用 merge commit 合并 `main`。
