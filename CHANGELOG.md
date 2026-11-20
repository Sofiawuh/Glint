# Changelog

本项目的所有重要版本变更、新特性汇总与修复记录均归档于此。

## [Unreleased]

### Added
- 展开的翻译结果与多轮会话窗口新增图钉按钮：钉住后点击窗口外仍保持显示；未钉住时仅隐藏并保留内存上下文，可从菜单栏“显示上次窗口”恢复。紧凑提问卡片也会保留未发送草稿，但不提供图钉。`×` 与 Escape 继续作为取消请求并清除会话的明确关闭操作。
- 新增 Azure Text Translation 专用划词翻译链路：自动识别源语言，含中文字符时译为英文，其他文本译为简体中文。
- 新增 Azure OpenAI `/openai/v1/` 专用提问、追问与截图链路，并使用 `api-key` 请求头和 Azure Deployment Name。
- Azure 设置页为 Translator 与 GPT 分别提供“测试连接”，直接验证未保存的 Endpoint、Key、Region 与部署名称。
- 首次切换到 Azure 配置结构时自动将旧配置原样备份为 `config.pre-azure-backup.json`，且不覆盖已有备份。
- 初始化项目 Universal Harness 目录结构、架构全景图与工程规范。
- 新增多协议适配层（支持 `OpenAI 兼容`、`Anthropic 兼容`、`Gemini 兼容` 三种接口格式），内置官方支持 **DeepSeek**、**Gemini**（`gemini-3.8-flash`）、**Vertex AI**（`aiplatform.googleapis.com`）与 **MiMo** 四大服务商及前置彩色品牌 Logo。
- 新增「在开机时启动」（`LaunchAtLogin`）能力。
- 新增「语言」偏好设置标签页：内置 11 种常用目标语言（简体中文、繁体中文、英语、日语、韩语、俄语、法语、德语、西班牙语等），翻译与解释共用 `<languages>` 语言占位符，支持用户自定义编辑翻译与解释 Prompt（删除 `<languages>` 占位符后自动按自定义固定指令生效），彻底移除旧版「单汉字即判中译英」的误判逻辑。
- 全新设计 Claude 暖纸书卷风（`#FAF9F5` + 开口灵光气泡 + `#D97757` 赤陶星芒 `✦`）品牌矢量 Logo（`images/logo.svg`）、macOS 原生应用图标（`Glint.icns`）与 18×18 自适应明暗菜单栏矢量图标（`BrandLogo.swift`）。

### Changed
- 偏好设置收缩为“基础 / 权限 / Azure”三页，移除用户可见的 DeepSeek、Gemini、Vertex AI、MiMo、Anthropic 与自定义兼容协议选择。
- **划词提问与截图提问改为「内存上下文暂存 + 用户自定义 Prompt」交互**：划词悬浮条右侧按钮改为「提问」，点击「提问」或完成 `⌃⌥E` 框选截图后先将文本/图片上下文暂存于内存并弹出紧凑提问卡片（展示摘要或缩略图预览并自动聚焦输入框，空输入禁用发送按钮并拦截回车误触），提交非空 Prompt 后不附带任何默认解释 System Prompt，直接将上下文与用户 Prompt 一并流式发送并原地向下生长为多轮会话窗；偏好设置「语言」页同步移除废弃的「解释 Prompt」配置。
- **项目正式定名为 `Glint`**：应用包名统一为 `Glint.app` / `Glint.dmg`（Bundle ID `com.yoryon.glint`，源码目录 `glint-app/`），配置与日志目录统一为 `~/.config/glint/`，开机自启 LaunchAgent 统一为 `com.yoryon.glint.plist`。
- 重写 `README.md` 门面文档（居中品牌 Logo、三合一动态演示视频 `images/demo.mp4` / `images/demo.gif`、Core ideas、Get started、Learn more），集中展示任意应用划词翻译、划词解释与 `⌃⌥E` 截图解释三大核心工作流。
- 精简菜单栏下拉菜单，并加入仅在存在隐藏内容窗时启用的“显示上次窗口”；偏好设置窗口升级为 macOS 原生工具栏图标样式布局。
- 改进划词气泡与浮窗落点定位逻辑，精确锚定于鼠标光标右下角。

### Fixed
- 修复 Azure GPT 新模型因请求显式携带 `temperature` 而返回 `unsupported_value` 的问题；连接探测、文字问答、追问与截图理解统一使用服务端默认采样参数。
- 修复双显示器/多显示器下触发截图解释（`⌃⌥E`）时遮罩窗口被系统单屏空间裁切与 `visibleFrame` 收缩、导致只能截取单个显示器局部区域的 Bug：改为按每块显示器独立创建全屏遮罩窗口（`CaptureWindow`），支持在任意显示器上首击直接拖选，并在截图所在显示器弹出解释浮窗。

## [1.0.0] - 2026-07-07

### Added
- 原生 macOS 菜单栏划词助手（`glint-app`）：支持划词「🌐 翻译」与「💡 解释」（SSE 流式打字机输出 + 多轮上下文追问）。
- 完整块级 Markdown 富文本渲染（`Markdown.swift`）：支持标题、多级嵌套列表、GFM 表格、引用、任务列表及圆角底色代码块。
- 多模态「📷 截图解释」（`Screenshot.swift`）：支持 `⌃⌥E` 框选屏幕区域交由视觉模型讲解并追问。
- 多厂商配置管理 GUI（`Config.swift` / `Settings.swift`）：内置 DeepSeek 与小米 MiMo，支持自定义任意 OpenAI 兼容接口。
- 结果与会话浮窗支持自由拖拽缩放、尺寸上限记忆与随内容自适应生长。
