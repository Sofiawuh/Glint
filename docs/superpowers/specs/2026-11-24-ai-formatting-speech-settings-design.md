# Glint AI 智能排版、智能润色与 Speech 设置设计

日期：2026-11-24  
状态：待书面复核

## 1. 目标

本版本解决两个已经复现的问题：

1. 现有本地规则无法稳定恢复邮件、网页、PDF 和长文本中的真实段落、列表与签名，导致 `customer.In addition`、`2141.It appears`、项目符号挤在同一段等排版错误；
2. Azure Speech 当前要求用户填写完整 TTS Endpoint 和自由文本 Voice，容易把 Azure Portal 的通用终结点填入 Endpoint、把 Region 填入 Voice，并且失败提示无法指出真正错误字段。

版本新增两个相互独立的 Azure GPT 能力：

- **智能排版**：只恢复文本结构，不改变文字内容；
- **智能润色**：在保留事实信息的前提下改善语法、用词、语气和可读性。

同时将 Speech 默认设置改为 Region、API Key 和 Voice 选择，由 Glint 自动生成标准 TTS REST Endpoint。

## 2. 用户界面与默认行为

### 2.1 基础设置

“翻译排版”改为“默认文本处理”，提供三个互斥选项：

1. `严格保留`：仅规范换行编码和尾随空格，不调用 GPT；
2. `智能排版`：Translator 完成翻译后，调用一次 Azure GPT，同时整理原文与译文结构，不修改文字；
3. `智能润色`：Translator 完成翻译后，调用一次 Azure GPT；原文只做智能排版，译文在排版基础上润色。

现有 `智能排版` 用户升级后继续映射为新的 `智能排版`，现有 `严格保留` 保持不变。新安装默认使用 `智能排版`。

### 2.2 翻译工作台

原文和译文编辑区继续保留编辑、复制和朗读能力，并新增明确的手动 AI 操作：

- 原文：`智能排版`、`智能润色`；
- 译文：`智能排版`、`智能润色`。

自动处理遵守基础设置；手动操作只处理用户点击的编辑区。用户主动点击原文的“智能润色”时，才允许改变原文表达。

按钮在请求期间显示处理中状态并防止重复提交，但另一侧编辑、复制和停止朗读仍可用。AI 成功前保留当前编辑内容，失败、取消、响应过期或校验不通过时不得覆盖编辑器。

### 2.3 状态提示

工作台使用可理解的阶段提示：

- `正在翻译…`
- `正在智能排版…`
- `正在智能润色译文…`
- `Azure GPT 未配置，已使用基础排版`
- `AI 排版校验失败，已保留原结果`
- `AI 润色失败，已保留原结果`

提示不得包含 Key、完整正文或 Endpoint 查询参数。

## 3. 翻译与 AI 数据流

### 3.1 自动处理

`严格保留`：

```text
选中文字
→ 最低限度规范化
→ Azure Translator
→ 显示原文与译文
```

`智能排版`：

```text
选中文字
→ 本地基础规范化
→ Azure Translator
→ 一次 Azure GPT 请求
→ 返回 formatted_source + formatted_translation
→ 忠实性校验
→ 显示原文与译文
```

`智能润色`：

```text
选中文字
→ 本地基础规范化
→ Azure Translator
→ 一次 Azure GPT 请求
→ 返回 formatted_source + polished_translation
→ 忠实性与事实保护校验
→ 显示原文与译文
```

Translator 仍是唯一默认翻译引擎。GPT 不替代 Translator，也不决定目标语言。

### 3.2 GPT 请求协议

复用已配置的 Azure OpenAI `/openai/v1/chat/completions` 和部署名称。自动处理使用一次请求同时提交原文与 Translator 译文，要求模型只返回严格 JSON：

```json
{
  "formatted_source": "...",
  "formatted_translation": "..."
}
```

智能润色模式仍使用相同字段名，其中 `formatted_source` 只能排版，`formatted_translation` 允许润色。请求采用低随机性设置，不请求流式输出，不记录正文。

手动处理只提交当前编辑区文本，并返回一个结构化文本字段。请求开始时捕获编辑器版本；如果用户在等待期间修改了文本，晚到响应必须丢弃。

### 3.3 智能排版边界

智能排版仅允许：

- 插入、删除或调整空格与换行；
- 使用现有标记恢复标题、段落、列表、引用、代码、简单表格和邮件签名结构；
- 修复标点后缺少空格造成的单词粘连。

智能排版不得新增、删除、改写或重排任何非空白字符。校验时分别移除输入和输出中的 Unicode 空白字符，两者剩余字符序列必须完全一致。校验失败即拒绝 GPT 输出。

### 3.4 智能润色边界

智能润色允许改善：

- 语法与拼写；
- 用词和句式；
- 语气、流畅度和专业程度；
- 段落、标题、列表与签名结构。

智能润色不得虚构、删除或修改以下事实与不可变信息：

- 人名、组织名和资源名；
- 案件号、订单号、工单号和其他标识符；
- 数字、金额、百分比、日期与时间；
- URL、邮箱、IP、路径、变量名和代码；
- 原有列表项目表达的事实数量与顺序。

请求前提取上述保护项，请求后验证所有保护项仍存在且出现次数不减少。正文为空、JSON 无法解析、字段缺失或保护项校验失败时拒绝输出。润色属于语言改写，无法用字符完全相等校验，因此界面必须保留用户执行前内容，失败时原样恢复。

## 4. 回退与成本控制

- Azure GPT 未配置时，Translator 翻译不得被阻断；智能排版回退到现有本地基础排版，智能润色跳过并明确提示；
- GPT 网络错误、非 2xx、响应为空、JSON 错误或校验失败时，不用失败内容覆盖编辑器；
- 自动智能排版或润色每次翻译最多增加一次 GPT 请求；
- 手动智能排版或润色每次用户点击增加一次 GPT 请求；
- 长文本超过模型预算时按稳定段落边界分批，每批独立校验，任一批失败则整次 AI 结果不落入编辑器；
- 最近结果只在 Translator 成功并完成本次允许的处理后写入；手动 AI 成功后更新同一条记录，不新增重复记录。

## 5. Azure Speech 设置重构

### 5.1 默认表单

Speech 设置组改为：

- `Region`：例如 `eastasia`，自动去除首尾空格并转为小写；
- `API Key`：安全输入，不写日志；
- `Voice`：下拉选择，默认 `自动匹配语言`；
- `测试连接`：使用固定短文本发起最小真实合成请求，不包含用户正文，也不自动保存。

普通用户不再填写完整 Endpoint。Glint 根据 Region 自动生成：

```text
https://<region>.tts.speech.microsoft.com/cognitiveservices/v1
```

Region 只接受字母、数字和连字符，不能为空。Voice 下拉至少提供：

- 自动匹配语言；
- 简体中文女声、简体中文男声；
- 英语女声、英语男声；
- 日语女声；
- 韩语女声；
- 自定义 Neural Voice。

自动匹配继续按当前朗读内容的语言代码选择 Neural Voice。固定 Voice 只在用户明确选择时覆盖自动匹配。

### 5.2 自定义 Voice

选择“自定义 Neural Voice…”后显示独立输入框，并校验 Azure Neural Voice 命名格式。Region 不得再出现在 Voice 输入框中；无效 Voice 的错误提示必须指向 Voice，不得笼统提示 Endpoint 或 Key。

### 5.3 旧配置迁移

配置模型新增 `region`，并保持向后兼容：

- 旧 Endpoint 符合 `https://<region>.tts.speech.microsoft.com/cognitiveservices/v1` 时，自动提取 Region；
- 旧 Endpoint 是 `https://<region>.api.cognitive.microsoft.com/` 时，提取 Region 并规范为标准 TTS Endpoint；
- 旧 Voice 是 `auto`、空值或合法 Neural Voice 时原样迁移；
- 旧 Voice 等于已识别 Region（例如 `eastasia`）或格式无效时，迁移为 `auto`；
- 迁移不得修改或输出 API Key；
- 保存新配置后只持久化 Region、Key 和 Voice 所需字段，运行时生成 Endpoint。

### 5.4 测试连接与错误信息

测试连接必须分阶段校验并返回具体信息：

- `请填写 Speech Region`
- `Speech Region 格式不正确`
- `请填写 Speech API Key`
- `Voice 格式不正确`
- `Speech Key 无效或资源区域不匹配`
- `该 Voice 在当前区域不可用`
- `网络错误：…`
- `✓ Azure Speech 连接成功`

客户端字段校验失败时不得发送网络请求。HTTP 和网络错误继续通过脱敏器处理。

## 6. 组件边界

- `TranslationAIService`：构造排版/润色请求、解析严格 JSON、处理分批与错误；
- `TranslationContentValidator`：智能排版字符忠实校验、润色保护项提取与校验；
- `TranslationService`：继续负责 Translator 请求，并编排 Translator 与可选 AI 后处理；
- `TranslationWorkbench`：保存当前编辑状态、处理代际、AI 操作状态和最近结果更新；
- `AzureSpeechConfig`：保存 Region、Key、Voice，迁移旧配置并生成运行时 Endpoint；
- `Settings`：显示 Speech 新表单、Voice 下拉和精确连接探测结果。

各组件通过明确输入输出协作；UI 不自行拼接 GPT JSON 或 Speech Endpoint，网络服务不直接修改编辑器状态。

## 7. 隐私与安全

- Key 只保存在现有本机配置中，不写入日志、测试、设计文档或错误提示；
- GPT 请求包含用户主动翻译或主动润色的正文，这是功能必要行为；界面不额外上传剪贴板历史；
- Translator、GPT 和 Speech 错误必须脱敏 Key、Endpoint 查询参数和正文；
- 音频继续只保存在内存中；
- 测试全部使用虚构 Endpoint、Key 与正文；
- UI smoke 必须设置独立 `GLINT_CONFIG_DIR`，不得加载用户真实配置。

## 8. 测试与验收

按照仓库 TDD 约束，业务实现前由全新上下文的独立测试 Agent 编写黑盒契约测试并先确认失败。至少覆盖：

- 三种默认文本处理模式的迁移、保存与路由；
- 智能排版请求、严格 JSON 解析、字符忠实校验与失败回退；
- 智能润色保护项提取、计数校验、空响应与失败不覆盖；
- 自动处理只增加一次 GPT 请求，手动处理只作用于指定编辑区；
- 请求期间用户编辑导致晚到响应失效；
- Speech Region 自动生成 TTS Endpoint；
- Portal 通用 Endpoint、标准 TTS Endpoint 与无效 Voice 的旧配置迁移；
- Voice 自动匹配、固定 Voice、自定义 Voice 与精确字段错误；
- Speech 真实探测请求不含用户正文；
- Translator、提问、截图、快捷键、最近结果、复制、朗读和既有配置不回归；
- Universal Binary、固定签名、隔离 UI smoke 和 `/Applications/Glint.app` 安装通过。

提交前执行独立只读终审，必须达到 `APPROVE` 且 `P0=0 / P1=0 / P2=0`。发布使用功能分支、GitHub PR 和 merge commit 合并 `main`，不 squash、不 rebase，并保留功能分支。

## 9. 不在本版本范围内

- 不让 GPT 取代 Azure Translator；
- 不恢复源应用中的字体、颜色、图片、分页或复杂 HTML/CSS；
- 不提供云端历史同步或持久化会话；
- 不动态下载 Azure 全量声音目录；
- 不改变快捷键、截图、提问和最近 10 条仅内存历史的现有产品规则。
