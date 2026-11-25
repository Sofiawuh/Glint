# PROJECTS.md

## 1. 项目定位

`Glint` 是一款纯原生 AppKit（Swift 5）编写的 macOS 菜单栏 AI 文字翻译、文字提问与截图讲解助手（最低支持 macOS 12.0，Universal Binary `arm64 + x86_64`）。核心能力包括：
- **文字命令翻译 / 提问**：用户在任意应用中选中文字后，按可独立录制的全局文字命令快捷键（默认为数字 `1` 左侧的 `` ` `` 键），Glint 优先读取当前 `AXSelectedText`，必要时执行完整备份/安全恢复剪贴板的受保护复制降级，并在鼠标右下直接显示「翻译」「提问」；普通拖选、双击、键盘扩选、滚动和窗口调整不会自动弹出入口。翻译进入原文 / 译文双编辑工作台，基础翻译始终只调用 Azure Text Translation，非空译文直接显示；只有用户主动点击排版或润色时才调用 Azure GPT，并直接采用非空普通文本结果。工作台还支持重新翻译、纯文本 + RTF 复制与 Azure Speech 双语朗读；提问支持流式 Markdown 与多轮上下文追问。
- **截图解释**：通过可在设置中直接录制的全局热键（默认 `⌃⌥E`）框选屏幕区域，调用多模态大模型看图讲解并支持继续追问。
- **进程内最近结果**：菜单栏最多保留 10 条已完成文字翻译或文字问答的只读纯文本快照，并受 10 MB 总预算限制；历史不含截图、凭据、网络任务或可继续追问的 Azure messages，退出进程即清空。
- **Azure 三服务直连**：基础文字翻译直连 Azure Text Translation；智能排版、智能润色、提问、追问与截图理解直连 Azure OpenAI v1；原文 / 译文朗读直连 Azure Speech。Speech 设置只要求 Portal Endpoint 与 Key，运行时自动解析区域和 Voice；三个 API Key 进入 macOS Keychain，`~/.config/glint/config.json` 只保存 Endpoint、Region、Deployment 等非敏感配置。无中间服务器，合成音频只保存在当前进程内存。

## 2. 仓库范围与命名约定

- **主工程目录**：[glint-app/](glint-app) 为唯一主力维护的原生 macOS 应用源码目录（直接通过 `swiftc` 编译打包生成 `Glint.app` 与 `Glint.dmg`，无 `.xcodeproj` 依赖）。
- **Bundle 与日志标识**：应用 Bundle Identifier 固定为 `com.yoryon.glint`，自签名证书名称优先匹配 `Glint Self Signed`（避免重装丢失 macOS 辅助功能与屏幕录制授权），运行日志固定写入 `~/.config/glint/glint.log`。

## 3. 项目特异身份红线

- **语言红线**：始终用中文回复 `nanzhi`。只有在用户明确要求其他语言，或代码、命令、日志、文件内容需要原样保留时，才使用非中文片段。
- **构建产物同步红线**：每次修改 `Glint` 的应用源码后，都必须更新本机 App，运行 `cd glint-app && bash build.sh` 生成最新 `Glint.app` 与 `Glint.dmg`。
- **本机安装替换红线**：如果 `/Applications/Glint.app` 已存在，且用户没有明确要求只改源码，则必须停止正在运行的进程、替换 `/Applications/Glint.app`、再重新打开。
- **自验收红线**：每次更新 App 后都要自己验收。至少确认编译/打包通过、安装版签名可验证、进程已重新启动；涉及 UI 的改动还要尽量做可执行的 UI/日志验收。
