# PROJECTS.md

## 1. 项目定位

`Glint` 是一款纯原生 AppKit（Swift 5）编写的 macOS 菜单栏 AI 划词翻译、解释与截图讲解助手（最低支持 macOS 12.0，Universal Binary `arm64 + x86_64`）。核心能力包括：
- **划词即译 / 即问**：全局监听鼠标拖选、双击/三击、键盘扩选与 `⌘A` 产生的新文本选区，只在真实选区右下角显示 10 pt 赤陶色方块入口，用户主动悬停后展开「翻译」「提问」；通过焦点元素、鼠标命中元素及有限父链组成通用 Accessibility 候选层，必要时只对明确拖选或双击/三击执行受保护的复制降级，并拒绝文件、图片、滚动条、列宽、滑块和窗口调整控件，结果支持流式 Markdown 富文本渲染和多轮上下文追问。
- **截图解释**：通过可在设置中直接录制的全局热键（默认 `⌃⌥E`）框选屏幕区域，调用多模态大模型看图讲解并支持继续追问。
- **Azure 双服务直连**：划词翻译直连 Azure Text Translation，提问、追问与截图理解直连 Azure OpenAI v1；配置持久化于本机 `~/.config/glint/config.json`，无中间服务器。

## 2. 仓库范围与命名约定

- **主工程目录**：[glint-app/](glint-app) 为唯一主力维护的原生 macOS 应用源码目录（直接通过 `swiftc` 编译打包生成 `Glint.app` 与 `Glint.dmg`，无 `.xcodeproj` 依赖）。
- **Bundle 与日志标识**：应用 Bundle Identifier 固定为 `com.yoryon.glint`，自签名证书名称优先匹配 `Glint Self Signed`（避免重装丢失 macOS 辅助功能与屏幕录制授权），运行日志固定写入 `~/.config/glint/glint.log`。

## 3. 项目特异身份红线

- **语言红线**：始终用中文回复 `nanzhi`。只有在用户明确要求其他语言，或代码、命令、日志、文件内容需要原样保留时，才使用非中文片段。
- **构建产物同步红线**：每次修改 `Glint` 的应用源码后，都必须更新本机 App，运行 `cd glint-app && bash build.sh` 生成最新 `Glint.app` 与 `Glint.dmg`。
- **本机安装替换红线**：如果 `/Applications/Glint.app` 已存在，且用户没有明确要求只改源码，则必须停止正在运行的进程、替换 `/Applications/Glint.app`、再重新打开。
- **自验收红线**：每次更新 App 后都要自己验收。至少确认编译/打包通过、安装版签名可验证、进程已重新启动；涉及 UI 的改动还要尽量做可执行的 UI/日志验收。
