# Azure 专用版实施计划

## 1. 配置与协议层

- 在 `glint-app/Config.swift` 中以 `AzureTranslatorConfig`、`AzureOpenAIConfig` 取代用户可见的多服务商配置模型。
- Translator 提供：配置校验、中文字符目标语言判断、`/translate?api-version=3.0&to=` URL 构造、Key/Region 请求头、JSON Body、响应与 Azure 错误解析。
- Azure OpenAI 提供：`/openai/v1` Endpoint 规范化、`/chat/completions` URL 构造、`api-key` 请求头、Chat Completions Body、非流式/SSE 解析和 Azure 错误解析。
- `AppConfig` 持久化两组 Azure 配置与截图开关；旧 provider 字段不迁移。保持提示上下文、启动项与窗口行为代码不变。

## 2. 设置与运行链路

- 将 `Settings.swift` 的“服务商”页改为“Azure”页，分成 Translator 与 GPT 两个区域；字段分别为 Endpoint、Key、Region，以及 Endpoint、Key、Deployment Name、支持截图。
- 每个区域提供“测试连接”按钮，直接读取未保存表单值。Translator 测试翻译固定文本，GPT 测试执行最小非流式对话；测试期间按钮禁用并显示进行中、成功或脱敏失败状态。
- `main.swift::translate` 改为 Translator 请求；`chatStream` 改为 Azure GPT SSE 请求；截图入口在 GPT 未启用视觉时给出设置提示。
- HTTP 非 2xx 和流式错误统一通过 Azure 错误解析输出中文提示，不打印 Key。

## 3. TDD 顺序

1. 独立测试代理先改写协议测试，覆盖目标语言、Translator 请求、GPT 请求、响应/SSE、错误脱敏、配置编码解码与探测请求；运行并确认在现有实现上失败。
2. 实现 `Config.swift` 直到协议测试通过。
3. 改造 `Settings.swift` 与 `main.swift`，编译检查 UI/调用链。
4. 更新 `docs/architecture/overview.md`、`README.md`、`CHANGELOG.md` 和构建验收手册中的协议说明。

## 4. 验收

- 运行 Azure 协议测试、几何测试与 Markdown 测试。
- 执行 `glint-app/build.sh` 生成 Universal `Glint.app` 与 DMG。
- 停止旧进程、替换 `/Applications/Glint.app`、验证签名并重新启动。
- 使用本地 UI 冒烟入口和运行日志确认设置窗口、进程与基础浮窗可用。
- 检查 Git diff、凭据模式与提交历史，确认无真实 Endpoint、Key 或 Token。
- 提交并推送 `feature/azure-services` 到 `Sofiawuh/Glint`。

