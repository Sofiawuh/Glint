# 个人翻译工具简化链路实施计划

> 对应规格：[spec.md](spec.md)
> 状态：实施中
> 说明：当前会话没有可用的 `writing-plans` skill，本计划按已批准规格和仓库 TDD 规范编写。

## 1. 目标

将默认翻译与手动 AI 处理拆成两条简单、独立的运行链路：

```text
普通翻译：选中文字 → Azure Translator → 非空译文直接显示

手动处理：点击排版或润色 → Azure GPT → 非空普通文本直接更新对应编辑区
```

本次不再让占位符恢复、结构化 JSON、区块白名单或内容忠实校验决定结果是否可见。

## 2. 测试先行

- [ ] 由全新上下文的独立测试 Agent 编写业务黑盒契约。
- [ ] 实际运行新契约，确认当前实现红灯。
- [ ] 覆盖 Translator 非空响应直接成功，且含数字、日期、金额、URL、邮箱、路径和列表时不被拒绝。
- [ ] 覆盖 Translator 错误文案不再提 Azure GPT。
- [ ] 覆盖 GPT 接受任意非空普通文本，不要求 JSON 或区块。
- [ ] 覆盖双侧一键处理的独立成功语义，以及 GPT 失败保留原内容的中性反馈。

## 3. 普通翻译实现

- [ ] 在 `TranslationService.swift` 中让默认翻译退出 `TranslationDocument` 占位符主链路。
- [ ] 为正常文本生成单个 Translator 请求；超预算时只按长度切分，优先空行和换行。
- [ ] 使用 Azure Translator 普通响应解析，每个非空分片按原顺序直接拼接。
- [ ] 保留请求取消和代际控制，不引入内容级校验。
- [ ] 将 Translator 响应无文本与 GPT 无文本分为准确的错误类型和文案。

## 4. 手动 GPT 实现

- [ ] 将 `TranslationAIService.swift` 改为普通文本提示词和普通文本响应解析。
- [ ] 单侧排版或润色只发送当前编辑区文本，任意非空返回直接采用。
- [ ] 一键处理对原文与译文分别发请求，不再使用双侧 JSON 协议。
- [ ] 两侧独立提交结果：成功侧立即落地，失败侧保持原样。
- [ ] GPT 失败使用中性提示，不标记为普通翻译失败。
- [ ] `TranslationContentValidator` 和 `TranslationBlockRenderer` 可以保留兼容类型，但不再参与生产 AI 主链路。

## 5. UI 与状态接入

- [ ] 在 `main.swift` 中将 AI 成功结果直接写入 `TranslationWorkbench` 和编辑区纯文本。
- [ ] 保留重新翻译、双编辑、复制、朗读、最近结果和自适应窗口行为。
- [ ] 普通翻译完成状态固定为“翻译完成”，当前排版模式不触发自动 AI。
- [ ] GPT 失败不清空译文，不阻止复制、朗读或重新翻译。

## 6. 文档与回归

- [ ] 更新 `docs/architecture/overview.md`，删除结构化 JSON 和强制忠实校验作为当前架构事实的描述。
- [ ] 更新 `CHANGELOG.md` 与 `docs/runbooks/build-and-verify.md`。
- [ ] 运行新契约并转绿。
- [ ] 运行现有翻译工作台、复制、朗读、最近结果、自适应布局相关回归。
- [ ] 完成 `arm64` 与 `x86_64` 类型检查和 Universal 构建。

## 7. 安装与发布

- [ ] 使用 `Glint Self Signed` 对最新 App 签名并验证。
- [ ] 安全备份旧 `/Applications/Glint.app`，停止旧进程后替换并重新启动。
- [ ] 使用隔离配置和完全虚构文本完成 UI smoke，不读取真实剪贴板、邮件或凭据。
- [ ] 推送功能分支并创建 GitHub PR。
- [ ] 以 merge commit 合并到 `main`，不 squash、不 rebase，保留功能分支。
- [ ] 本地切回并同步 `main`，核对远端提交与安装版。
