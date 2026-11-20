<div align="center">

<img src="images/logo.svg" width="116" height="116" alt="Glint Logo">

# Glint

**划词即译 · 划词提问 · 截图提问 —— 原生丝滑的 macOS 桌面 AI 助手**

拖选、双击/三击或键盘扩选产生新文本选区后，选区右下角会出现一个赤陶色微型方块入口；主动悬停才展开「翻译 / 提问」。按下截图快捷键（默认 ⌃⌥E，可在设置中直接录制修改）可框选屏幕任意区域，将文字或截图暂存为上下文并输入你的 Prompt 发送给大模型。<br>
自带 API Key **直连你自己的 Azure 服务**，无中间服务器、不中转、不收集任何数据。

![macOS](https://img.shields.io/badge/macOS-12.0%2B%20Universal-141413?style=flat-square&logo=apple&logoColor=FAF9F5)
![Swift](https://img.shields.io/badge/Swift-5%20%7C%20AppKit-D97757?style=flat-square&logo=swift&logoColor=white)
![Azure](https://img.shields.io/badge/Azure-Translator%20%7C%20OpenAI%20v1-0078D4?style=flat-square&logo=microsoftazure&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-3DA639?style=flat-square)

<br>

<a href="images/demo.mp4">
  <img src="images/demo.gif" width="760" alt="Glint 演示：1. 到处都能划词翻译 · 2. 到处都能划词解释 · 3. 到处都能用自定义快捷键截图解释">
</a>

</div>

## Core ideas

- **任意选区轻提示，悬停再操作** —— 在任意应用中通过拖选、双击选词、三击选段、`Shift + 方向键` 扩选或 `⌘A` 产生新选区，只在真实选区右下角显示 10 pt 赤陶色方块入口；主动悬停后才展开操作，不遮挡阅读，也不会因拖动滚动条或表格列宽误弹。
- **跨屏框选，看图精讲** —— 按下快捷键框选屏幕任意区域，无论是报错日志、架构图、论文公式还是外文界面，都能直接交由多模态模型为您拆解，并支持在面板底部连续追问。
- **暖纸书卷风阅读体验** —— 采用柔和护眼的暖米白纸感界面与精细的富文本排版，流式输出实时呈现，浮窗随内容自然延展，让技术与长文阅读更加从容。
- **Azure 双服务分工** —— 普通划词翻译调用 Azure Text Translation；上下文提问、多轮追问与截图理解调用 Azure OpenAI 新版 `/openai/v1/`。
- **纯粹原生，本机直连** —— 采用纯原生 Swift 与 AppKit 构建，轻量流畅且无第三方框架负担；所有配置与密钥仅保存在本机，内容仅在主动触发时直发你的 Azure 资源。

| 交互场景 | 触发方式 | 行为说明 |
| :--- | :--- | :--- |
| **划词翻译** | 以鼠标或键盘产生新文本选区 → 悬停右下角方块 → 点击 **「翻译」** | Azure Translator 自动识别源语言；中文译英文，其他语言译简体中文 |
| **划词提问** | 以鼠标或键盘产生新文本选区 → 悬停右下角方块 → 点击 **「提问」** | 将选中内容暂存内存并弹出紧凑输入框，输入非空 Prompt 后连同上下文流式提问 |
| **多轮追问** | 会话浮窗底部输入框 → 回车 | 围绕当前选中文本或截图内容继续深入提问 |
| **截图提问** | 按下截图快捷键（默认 ⌃⌥E）→ 框选区域 | 可在「设置 → 基础」直接录制快捷键；框选画面暂存内存并弹出输入框，输入自定义 Prompt 后由多模态模型回答 |
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
   - 在 **「设置… → 权限」** 页开启 **「辅助功能」**（全局划词监听必需）与 **「屏幕录制」**（截图解释必需）。
   - 在 **「设置… → 基础」** 页可勾选 **「在开机时启动」**，并查看 Azure 配置概览。

## Learn more

- **工程与架构文档**：
  - [项目定位与开发红线 (PROJECTS.md)](PROJECTS.md)
  - [全局架构现状与核心数据流 (docs/architecture/overview.md)](docs/architecture/overview.md)
  - [构建、安装与自验收手册 (docs/runbooks/build-and-verify.md)](docs/runbooks/build-and-verify.md)
- **架构决策记录 (ADR)**：
  - [ADR-0001：划词气泡与浮窗固定锚定于鼠标光标右下角](docs/adr/0001-cursor-bottom-right-placement.md)
  - [ADR-0003：Azure Translator 与 Azure OpenAI v1 专用双服务架构](docs/adr/0003-azure-only-services.md)
- **版本与开源协议**：
  - [版本变更记录 (CHANGELOG.md)](CHANGELOG.md) · 基于 [MIT License](LICENSE) 开源。
