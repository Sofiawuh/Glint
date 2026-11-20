# Azure GPT Temperature 兼容修复设计

## 1. 背景与问题

Glint 的 Azure GPT 连接探测当前发送 `temperature: 0`，正式流式聊天发送 `temperature: 0.5`。用户的 `gpt-5.6-sol` Azure 部署返回 `unsupported_value`，说明该部署不接受请求中显式指定的 `temperature`。

Translator 连接测试已经成功，因此本次问题不涉及 Translator、Azure GPT Endpoint、API Key 或 Deployment Name。

## 2. 目标

- 让 Azure GPT 连接探测兼容不接受 `temperature` 的模型部署。
- 让正式文字问答、追问和截图理解使用同一兼容请求格式。
- 不增加模型专用配置，不产生失败后的额外重试请求。

## 3. 设计

`AzureOpenAIConfig.buildRequest` 构造 Azure OpenAI v1 Chat Completions 请求时不再接收或发送 `temperature`。

请求体继续包含：

- `model`
- `messages`
- `max_completion_tokens`
- `stream`

连接探测继续发送最小非流式消息，并将输出上限保持为 8 tokens。正式对话继续使用现有输出上限和 SSE 流式响应。模型采样行为使用 Azure 部署的服务端默认值。

## 4. 不变范围

- Azure Text Translation 请求和连接探测不变。
- Azure GPT Endpoint 规范化、`api-key` 请求头和 Deployment Name 不变。
- SSE 增量解析、普通响应解析和 Azure 错误脱敏不变。
- 图片消息结构和“支持截图/图片理解”开关不变。
- 设置页面字段和保存格式不变。
- 不加入失败重试或“发送 temperature”设置开关。

## 5. 测试与验收

协议测试必须验证：

1. Azure GPT 正式流式请求体不含 `temperature`。
2. Azure GPT 非流式连接探测请求体不含 `temperature`。
3. `model`、`messages`、`max_completion_tokens` 和 `stream` 仍正确。
4. 原有 Azure、几何和 Markdown 测试继续通过。
5. 应用使用固定的 `Glint Self Signed` 身份重新构建、签名并安装。

用户在新版本中使用当前表单值再次点击 Azure GPT“测试连接”，不应再收到与 `temperature` 有关的 `unsupported_value`。真实 Azure 成功结果以该在线探测为最终验收。

## 6. 失败与回退

若部署随后拒绝其他请求字段，Glint 继续显示经过 Key 脱敏的 Azure 错误，不自动重复请求。若需要回退，可恢复本次单一请求字段变更；配置文件格式不受影响。
