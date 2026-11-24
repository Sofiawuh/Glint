# Glint 安全单键快捷键实施计划

日期：2026-11-24  
对应设计：[2026-11-24-single-key-hotkeys-design.md](../specs/2026-11-24-single-key-hotkeys-design.md)

## 阶段 1：黑盒测试红灯

由全新上下文的独立测试代理只修改测试文件，覆盖：

- `ScreenshotHotKey` 允许无修饰键的 `kVK_ANSI_Grave` 与 `F1–F20`；
- 普通字母、数字、方向键、空格、回车、Tab、其他标点和数字键盘键在无修饰键时无效；
- 普通键搭配受支持修饰键时维持现有有效行为；
- `TextCommandHotKey.default` 改为无修饰键 `kVK_ANSI_Grave`；
- 旧默认 `⌃⌥T` 迁移到新默认，其他文字自定义键、截图键与 Azure 配置保持不变；
- 相同单键的文字命令与截图候选仍被冲突保护拒绝；
- 录制无效单键的内联指导文案及清除契约。

主代理亲自执行测试并确认当前实现准确红灯后，才允许修改生产代码。

## 阶段 2：快捷键值与配置迁移

1. 在 `ScreenshotHotKey.swift` 集中维护无修饰键允许集合：反引号物理键与 `F1–F20`。
2. 调整 `isValid` 与 `recordingDecision`，保留 Escape、删除键和物理修饰键的现有语义。
3. 将 `TextCommandHotKey.default` 改为 `kVK_ANSI_Grave / modifiers = 0`，保留旧默认常量供迁移比较。
4. 在 `AppConfig` 解码/加载边界执行一次性值迁移：仅旧默认 `⌃⌥T` 变为新默认；其他配置字段原样保留。
5. 确保启动注册与切换事务将 `modifiers = 0` 原样传递给 Carbon。

## 阶段 3：录制器反馈与设置 UI

1. 录制控件主提示改为“请按快捷键…”。
2. 无效单键时保持录制状态，并在对应录制器下方显示“可单独按 ` 或 F1–F20；其他按键需搭配修饰键”。
3. 有效提交、取消、恢复默认、切换 Tab、窗口失焦或关闭时清除旧错误。
4. 文字命令说明显示新默认；截图说明继续使用截图默认。
5. 更新 UI smoke test，使两套录制器、单键显示和错误状态具备可执行验收。

## 阶段 4：文档同步

更新当前态文档中的默认快捷键和录制规则：

- `README.md`；
- `PROJECTS.md`；
- `CHANGELOG.md`；
- `docs/architecture/overview.md`；
- `docs/runbooks/build-and-verify.md`；
- `glint-app/build.sh` 安装说明；
- 已批准设计状态。

历史规格、计划和 ADR 保持原文，不回写旧时结论。

## 阶段 5：完整验证与安装

1. 重跑新增单键测试以及现有文字快捷键、截图快捷键、录制生命周期、Carbon 生命周期、Azure、取词、面板、几何、Markdown 和浮窗测试。
2. 运行 `arm64-apple-macos12.0` 与 `x86_64-apple-macos12.0` 全应用类型检查。
3. 使用 `Glint Self Signed` 构建 Universal `Glint.app` 与 `Glint.dmg`。
4. 停止当前 Glint，将 `/Applications/Glint.app` 移入独立 `/tmp` 备份目录，安装新版本并验证签名、架构和进程。
5. 使用隔离临时 Home 运行快捷键设置页 UI smoke test，避免加载真实 Azure 配置或 Key。
6. 由独立只读复审代理给出精确 `APPROVE / P0=0 / P1=0 / P2=0` 后才提交生产改动。

## 阶段 6：GitHub 合并

1. 提交生产、测试和文档改动并推送 `feature/single-key-hotkeys`。
2. 创建 PR，核对远端 diff、基线、可合并状态和 checks。
3. 使用 merge commit 合并到 `main`；不 squash、不 rebase、不删除功能分支。
4. 本地切回 `main` 并 fast-forward 到远端合并提交。
5. 增量更新 Obsidian 文件清单与任务日志。

