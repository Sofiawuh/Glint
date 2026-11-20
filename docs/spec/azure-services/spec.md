# Azure 专用版设计规格

> 状态：已批准
> 关联任务：个人 Azure 改造（仓库未启用 GitHub Issues）
> 影响架构：`docs/architecture/overview.md` 中的设置、配置、翻译与模型请求链路

## 1. 目标

将 Glint 收缩为用户个人使用的 Azure 专用 macOS 客户端：普通划词翻译固定调用 Azure Text Translation；提问、解释、润色、追问与截图理解固定调用 Azure OpenAI 新版 `/openai/v1/` Chat Completions 接口。用户只需在设置页填写两组 Azure 连接信息，不再选择 DeepSeek、Gemini、标准 OpenAI、Anthropic 或兼容协议。

## 2. 用户可见行为

### 2.1 划词翻译

- 文本包含中文字符时，目标语言为英文 `en`。
- 其他文本的目标语言为简体中文 `zh-Hans`。
- 源语言由 Azure Translator 自动检测，不额外发起语言检测请求。
- 翻译请求使用 Translator REST API `POST /translate?api-version=3.0&to=<target>`。
- 配置缺失、认证失败、区域错误、限流和服务端错误必须显示可操作的中文提示。

### 2.2 Azure GPT

- Endpoint 由用户填写 Azure OpenAI v1 根地址，例如 `https://<resource>.openai.azure.com/openai/v1`。
- 客户端规范化后请求 `POST <endpoint>/chat/completions`。
- `model` 字段填写 Azure Deployment Name。
- API Key 使用 `api-key` 请求头，不发送 provider-specific `thinking` 字段。
- 非流式响应用于需要一次性结果的 AI 调用；SSE 流式响应用于提问、解释和多轮追问。
- 截图请求沿用 OpenAI `image_url` Data URL 消息结构，由“支持截图”开关决定是否允许。

## 3. 设置与配置模型

设置页只保留两组配置：

1. **Azure Text Translation**
   - Endpoint
   - API Key
   - Region
2. **Azure GPT**
   - Endpoint
   - API Key
   - Deployment Name
   - 支持截图

每组配置提供独立的“测试连接”按钮。测试必须使用设置页当前输入值（无需先保存），按钮在请求期间进入加载/禁用状态，并在原位显示成功或可操作的失败原因。

配置继续写入 `~/.config/glint/config.json`。本次不引入 Keychain，不迁移旧多服务商配置，也不保证旧配置字段继续生效。源码、测试、文档、日志和 Git 历史不得包含真实凭据。

首次发现旧版或不可解码的 `config.json` 时，应用必须先原样备份为同目录 `config.pre-azure-backup.json`，且不得覆盖已经存在的备份，然后再写入 Azure 默认配置。

## 4. 内部边界

- `AzureTranslatorConfig` 负责 Translator 连接信息、目标语言判断、请求构造与响应解析。
- `AzureOpenAIConfig` 负责 Azure OpenAI v1 Endpoint 规范化、请求构造、非流式解析和 SSE 增量解析。
- `AppConfig` 聚合并持久化上述两组 Azure 配置。
- `translate` 仅调用 Translator；`chatStream` 与截图会话仅调用 Azure OpenAI。
- 网络错误解析统一提取 Azure JSON 错误中的 `error.code` 与 `error.message`，不得回显 API Key 或 Authorization 信息。
- Translator 连接测试发送最小真实翻译请求，将固定文本 `test` 翻译为简体中文；Azure GPT 连接测试发送非流式最小对话并验证能够解析回复。测试会产生极少量真实 Azure 调用。
- 连接测试只验证当前填写值，不自动保存配置；成功后用户仍需点击设置页“保存”。

## 5. 失败模式

- Translator 的 Endpoint/Key 或 GPT 的 Endpoint/Key/Deployment Name 为空时，在发请求前提示检查对应必填项。
- Endpoint 无法构成 HTTPS URL 时拒绝请求。
- Translator Region 允许为空，以兼容全局单服务资源；用户填写时发送 `Ocp-Apim-Subscription-Region`。
- HTTP 非 2xx 时解析 Azure 错误正文；正文不可解析时显示状态码与通用建议。
- Azure GPT 流式响应中断时保留已显示内容，并给出中断原因。
- 不在 Translator 失败时静默回退 GPT，避免意外成本和掩盖配置问题。
- 连接测试期间禁止重复点击；关闭设置窗口或再次测试时，过期回调不得覆盖最新状态。

## 6. 验收标准

- Translator 请求路径、查询参数、Key/Region 请求头和 JSON Body 正确。
- 中文文本目标为 `en`，非中文文本目标为 `zh-Hans`。
- Azure OpenAI 请求路径、`api-key` 请求头、Deployment Name 与消息体正确，且不存在 `thinking` 字段。
- 非流式响应与 SSE 增量能解析为可显示文本。
- 设置页能够保存、重新加载并分别编辑两组配置。
- 两个“测试连接”按钮均使用未保存表单值；成功、配置缺失、Endpoint 非法、401/403、404、429 和服务端错误均有明确状态反馈，且反馈中不含 Key。
- 旧服务商选项不再出现在设置界面。
- 几何、Markdown 和 Azure 协议测试通过。
- Universal Binary 构建、应用签名验证、本机安装、进程启动和本地 UI 冒烟验收通过。

