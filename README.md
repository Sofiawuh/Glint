<div align="center">

<img src="images/logo.svg" width="116" height="116" alt="Glint Logo">

# Glint

**文字即译 · 文字提问 · 截图提问 —— 原生丝滑的 macOS 桌面 AI 助手**

在任意应用中选中文字后，按文字命令快捷键（默认 ⌃⌥T，可独立录制）即可在鼠标右下直接打开「翻译 / 提问」；不再自动监听拖选，也不依赖小方块或悬停。按下截图快捷键（默认 ⌃⌥E，可独立录制）可框选屏幕任意区域，将文字或截图暂存为上下文并输入你的 Prompt 发送给大模型。<br>
自带 API Key **直连你自己的 Azure 服务**，无中间服务器、不中转、不收集任何数据。

![macOS](https://img.shields.io/badge/macOS-12.0%2B%20Universal-141413?style=flat-square&logo=apple&logoColor=FAF9F5)
![Swift](https://img.shields.io/badge/Swift-5%20%7C%20AppKit-D97757?style=flat-square&logo=swift&logoColor=white)
![Azure](https://img.shields.io/badge/Azure-Translator%20%7C%20OpenAI%20v1-0078D4?style=flat-square&logo=microsoftazure&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-3DA639?style=flat-square)

<br>

<a href="images/demo.mp4">
  <img src="images/demo.gif" width="760" alt="Glint 演示：1. 跨应用文字翻译 · 2. 跨应用文字提问 · 3. 自定义快捷键截图提问">
</a>

</div>

## Core ideas

- **显式快捷键，跨应用稳定取词** —— 在 Safari、Chrome、微信、企业微信、VS Code、邮件和标准文本应用中，先选中文字，再按默认 `⌃⌥T`。Glint 优先读取当前 Accessibility 选区，必要时使用完整备份与安全恢复剪贴板的受保护复制；普通拖选、双击、滚动条、表格列宽和窗口调整不会自动弹窗。
- **跨屏框选，看图精讲** —— 按下快捷键框选屏幕任意区域，无论是报错日志、架构图、论文公式还是外文界面，都能直接交由多模态模型为您拆解，并支持在面板底部连续追问。
- **暖纸书卷风阅读体验** —— 采用柔和护眼的暖米白纸感界面与精细的富文本排版，流式输出实时呈现，浮窗随内容自然延展，让技术与长文阅读更加从容。
- **Azure 双服务分工** —— 文字翻译调用 Azure Text Translation；上下文提问、多轮追问与截图理解调用 Azure OpenAI 新版 `/openai/v1/`。
- **纯粹原生，本机直连** —— 采用纯原生 Swift 与 AppKit 构建，轻量流畅且无第三方框架负担；所有配置与密钥仅保存在本机，内容仅在主动触发时直发你的 Azure 资源。

| 交互场景 | 触发方式 | 行为说明 |
| :--- | :--- | :--- |
| **文字翻译** | 选中文字 → 按文字命令快捷键（默认 `⌃⌥T`）→ 点击 **「翻译」** | Azure Translator 自动识别源语言；中文译英文，其他语言译简体中文 |
| **文字提问** | 选中文字 → 按文字命令快捷键（默认 `⌃⌥T`）→ 点击 **「提问」** | 将选中内容暂存内存并弹出紧凑输入框，输入非空 Prompt 后连同上下文流式提问 |
| **多轮追问** | 会话浮窗底部输入框 → 回车 | 围绕当前选中文本或截图内容继续深入提问 |
| **截图提问** | 按下截图快捷键（默认 `⌃⌥E`）→ 框选区域 | 可在「设置 → 基础」独立录制；框选画面暂存内存并弹出输入框，输入自定义 Prompt 后由多模态模型回答 |
| **连接探测** | 菜单栏图标 → **「设置… → Azure」** | 分别测试 Translator 与 Azure GPT 的 Endpoint、Key、Region 和部署名称 |

## Get started

1. **安装或源码编译**
   - **直接安装**：前往 [Releases](https://github.com/nanzhi84/Glint/releases) 下载最新安装包，将 Glint 拖入「应用程序」文件夹（首次启动请**右键点击图标 → 打开**）。
   - **源码打包**：
     ```bash
     cd glint-app && bash build.sh
     ```
2. **配置 Azure 服务**
   - 点击屏幕右上角菜单栏 **Glint 图标** → **「设置…」** → **「Azure」**。
   - **Azure Text Translation**：填写 Translator Endpoint、API Key 与 Region（全局单服务资源可留空 Region）。
   - **Azure GPT**：填写形如 `https://<resource>.openai.azure.com/openai/v1` 的 Endpoint、API Key 与 Azure Deployment Name；部署支持图片时勾选截图能力。
   - 两组配置都可先点 **「测试连接」** 验证当前输入，再点击 **「保存」**。
3. **开启系统权限与开机自启**
   - 在 **「设置… → 权限」** 页开启 **「辅助功能」**（跨应用按需读取选中文字和复制降级所需）与 **「屏幕录制」**（截图提问必需）。
   - 在 **「设置… → 基础」** 页可分别录制文字命令与截图快捷键、勾选 **「在开机时启动」**，并查看 Azure 配置概览。

## Learn more

- **工程与架构文档**：
  - [项目定位与开发红线 (PROJECTS.md)](PROJECTS.md)
  - [全局架构现状与核心数据流 (docs/architecture/overview.md)](docs/architecture/overview.md)
  - [构建、安装与自验收手册 (docs/runbooks/build-and-verify.md)](docs/runbooks/build-and-verify.md)
- **架构决策记录 (ADR)**：
  - [ADR-0004：显式文字命令快捷键取代自动选区悬停入口](docs/adr/0004-explicit-text-command-hotkey.md)
  - [ADR-0003：Azure Translator 与 Azure OpenAI v1 专用双服务架构](docs/adr/0003-azure-only-services.md)
- **版本与开源协议**：
  - [版本变更记录 (CHANGELOG.md)](CHANGELOG.md) · 基于 [MIT License](LICENSE) 开源。
