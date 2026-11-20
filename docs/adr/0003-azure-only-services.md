# ADR-0003: Azure Translator 与 Azure OpenAI v1 专用双服务架构

- **状态 (Status)**：Accepted
- **日期 (Date)**：2026-11-20
- **取代 (Supersedes)**：[ADR-0002](superseded/0002-multi-provider-protocol-adapter.md)

## 1. 背景

该 Fork 仅服务于用户自己的 Azure 资源，不需要继续维护 DeepSeek、Gemini、Vertex AI、MiMo、Anthropic 或任意兼容网关。普通文本翻译与上下文生成任务也具有不同的延迟、成本和接口契约，因此不再共用一个模型服务商抽象。

## 2. 决策

1. 划词翻译固定调用 Azure Text Translation REST API v3。客户端本地判断目标语言：文本含中文字符时使用 `en`，其他文本使用 `zh-Hans`，源语言由服务端自动检测。
2. 提问、追问、润色和截图理解固定调用 Azure OpenAI 新版 `/openai/v1/chat/completions`，使用 `api-key` 认证与 Azure Deployment Name，复用 OpenAI Chat Completions 消息及 SSE 增量结构。
3. `AppConfig` 只持久化 `AzureTranslatorConfig` 与 `AzureOpenAIConfig`。设置页只显示两组 Azure 配置及各自的真实连接探测，不提供服务商与协议选择。
4. 连接探测使用未保存表单值发起最小真实请求，结果就地显示且不回显密钥；探测成功不会自动保存。
5. 配置仍由客户端直接保存到 `~/.config/glint/config.json`，本次不引入代理服务器或 Keychain。

## 3. 后果

- 用户配置路径清晰，Translator 与 GPT 的 Endpoint、Key、Region、部署名称不会混用。
- 普通翻译不再消耗 GPT Token，AI 会话继续支持流式输出和截图上下文。
- 旧多厂商配置不迁移，旧协议选项不再出现在应用界面；该 Fork 不承诺与上游多服务商配置保持兼容。
- 协议黑盒测试集中在 `glint-app/azure_services_tests.swift`，覆盖请求、解析、错误脱敏、持久化和连接探测契约。

