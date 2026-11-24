# 构建、安装与验收手册 (Build & Verify Runbook)

本手册规范 [glint-app/](../../glint-app) 的本地编译、签名校验、安装替换与自验收流程。

## 1. 单元与协议测试

通过 `harness run` 在隔离沙盒中编译并执行测试：

```bash
# 安全单键规则、零修饰键注册与截图快捷键既有契约
harness run hotkey-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/hotkey_test" glint-app/TranslationFormatting.swift glint-app/TranslationDocument.swift glint-app/SecureCredentialStore.swift glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/TextCommandHotKey.swift glint-app/HotKey.swift glint-app/hotkey_tests.swift -framework Carbon -framework Foundation -framework Security && "$HARNESS_WORK_DIR/hotkey_test"'

# 文字命令快捷键、配置迁移、冲突与切换事务
harness run text-command-hotkey-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/text_command_hotkey_test" glint-app/TranslationFormatting.swift glint-app/TranslationDocument.swift glint-app/SecureCredentialStore.swift glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/TextCommandHotKey.swift glint-app/HotKey.swift glint-app/text_command_hotkey_tests.swift -framework Carbon -framework Foundation -framework Security && "$HARNESS_WORK_DIR/text_command_hotkey_test"'

# 录制提示、非法单键错误与状态清理
harness run hotkey-recording-feedback-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/hotkey_recording_feedback_test" glint-app/ScreenshotHotKey.swift glint-app/hotkey_recording_feedback_tests.swift -framework Carbon -framework Foundation && "$HARNESS_WORK_DIR/hotkey_recording_feedback_test"'

# AX 优先、受保护复制过滤与剪贴板事务
harness run selected-text-extractor-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/selected_text_extractor_test" glint-app/SelectedTextExtractor.swift glint-app/selected_text_extractor_tests.swift -framework Foundation && "$HARNESS_WORK_DIR/selected_text_extractor_test"'

# 鼠标附近布局、请求代际、双按钮动作与关闭行为
harness run text-command-panel-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/text_command_panel_test" glint-app/TextCommandPanelLifecycle.swift glint-app/Geometry.swift glint-app/text_command_panel_tests.swift -framework AppKit && "$HARNESS_WORK_DIR/text_command_panel_test"'

# 显式入口路由：选区手势保持静默，只有文字快捷键开始取词
harness run text-command-entry-contract-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/text_command_entry_contract_test" glint-app/ScreenshotHotKey.swift glint-app/TextCommandEntryPolicy.swift glint-app/text_command_entry_contract_tests.swift -framework Carbon -framework Foundation && "$HARNESS_WORK_DIR/text_command_entry_contract_test"'

# 内容浮窗与截图坐标几何
harness run geometry-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/geometry_test" glint-app/Geometry.swift glint-app/geometry_tests.swift -framework AppKit && "$HARNESS_WORK_DIR/geometry_test"'

# Markdown 渲染
harness run markdown-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/markdown_test" glint-app/Markdown.swift glint-app/markdown_tests.swift -framework AppKit && "$HARNESS_WORK_DIR/markdown_test"'

# Azure Translator / Azure OpenAI v1 协议
harness run azure-services-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/azure_test" glint-app/TranslationFormatting.swift glint-app/TranslationDocument.swift glint-app/SecureCredentialStore.swift glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/TextCommandHotKey.swift glint-app/HotKey.swift glint-app/azure_services_tests.swift -framework Carbon -framework Foundation -framework Security && "$HARNESS_WORK_DIR/azure_test"'

# Azure Keychain 迁移、私有 API 禁止与空屏幕安全
harness run azure-keychain-migration-tests --timeout 30s -- bash -c 'swiftc -parse-as-library -o "$HARNESS_WORK_DIR/azure_keychain_migration_test" glint-app/TranslationFormatting.swift glint-app/TranslationDocument.swift glint-app/SecureCredentialStore.swift glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/TextCommandHotKey.swift glint-app/HotKey.swift glint-app/azure_keychain_migration_contract_tests.swift -framework Carbon -framework Foundation -framework Security && "$HARNESS_WORK_DIR/azure_keychain_migration_test"'
harness run background-cursor-public-api-tests --timeout 30s -- bash -c 'swiftc -parse-as-library -o "$HARNESS_WORK_DIR/background_cursor_public_api_test" glint-app/background_cursor_public_api_contract_tests.swift && "$HARNESS_WORK_DIR/background_cursor_public_api_test" glint-app/main.swift'
harness run text-command-screen-safety-tests --timeout 30s -- bash -c 'swiftc -parse-as-library -o "$HARNESS_WORK_DIR/text_command_screen_safety_test" glint-app/Geometry.swift glint-app/text_command_screen_safety_contract_tests.swift -framework AppKit && "$HARNESS_WORK_DIR/text_command_screen_safety_test"'

# 结果窗口图钉 / 隐藏 / 恢复
harness run popup-lifecycle-tests --timeout 30s -- bash -c 'swiftc -parse-as-library -o "$HARNESS_WORK_DIR/popup_test" glint-app/PopupLifecycle.swift glint-app/popup_lifecycle_tests.swift && "$HARNESS_WORK_DIR/popup_test"'
harness run popup-pin-control-tests --timeout 30s -- bash -c 'swiftc -parse-as-library -o "$HARNESS_WORK_DIR/popup_pin_control_test" glint-app/PopupLifecycle.swift glint-app/popup_pin_control_contract_tests.swift && "$HARNESS_WORK_DIR/popup_pin_control_test"'

# 当前进程最近结果：内存上限、准入、菜单、隐私与只读浏览状态
harness run recent-results-tests --timeout 30s -- bash -c 'swiftc -parse-as-library -o "$HARNESS_WORK_DIR/recent_results_test" glint-app/RecentResults.swift glint-app/recent_results_contract_tests.swift -framework Foundation && "$HARNESS_WORK_DIR/recent_results_test"'
harness run recent-results-app-tests --timeout 30s -- bash -c 'swiftc -parse-as-library -o "$HARNESS_WORK_DIR/recent_results_app_test" glint-app/RecentResults.swift glint-app/RecentResultsPresentation.swift glint-app/recent_results_app_contract_tests.swift -framework Foundation && "$HARNESS_WORK_DIR/recent_results_app_test"'

# 设置窗口录制与 Carbon 生命周期
harness run hotkey-recording-lifecycle-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/hotkey_recording_lifecycle_test" glint-app/ScreenshotHotKey.swift glint-app/HotKey.swift glint-app/hotkey_recording_lifecycle_tests.swift -framework Carbon -framework Foundation && "$HARNESS_WORK_DIR/hotkey_recording_lifecycle_test"'
harness run carbon-hotkey-lifecycle-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/carbon_hotkey_lifecycle_test" glint-app/ScreenshotHotKey.swift glint-app/HotKey.swift glint-app/carbon_hotkey_lifecycle_tests.swift -framework Carbon -framework Foundation && "$HARNESS_WORK_DIR/carbon_hotkey_lifecycle_test"'

# 智能排版、文档拆片与重组、工作台状态、富文本复制、翻译偏好与 Azure Speech
harness run translation-formatting-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/translation_formatting_test" glint-app/TranslationFormatting.swift glint-app/translation_formatting_contract_tests.swift -framework Foundation && "$HARNESS_WORK_DIR/translation_formatting_test"'
harness run translation-document-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/translation_document_test" glint-app/TranslationDocument.swift glint-app/translator_document_contract_tests.swift -framework Foundation && "$HARNESS_WORK_DIR/translation_document_test"'
harness run translation-workbench-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/translation_workbench_test" glint-app/RecentResults.swift glint-app/TranslationFormatting.swift glint-app/TranslationWorkbench.swift glint-app/translation_workbench_contract_tests.swift -framework Foundation && "$HARNESS_WORK_DIR/translation_workbench_test"'
harness run translation-clipboard-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/translation_clipboard_test" glint-app/TranslationClipboard.swift glint-app/translation_clipboard_contract_tests.swift -framework AppKit && "$HARNESS_WORK_DIR/translation_clipboard_test"'
harness run translation-preferences-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/translation_preferences_test" glint-app/TranslationFormatting.swift glint-app/TranslationDocument.swift glint-app/SecureCredentialStore.swift glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/TextCommandHotKey.swift glint-app/HotKey.swift glint-app/translation_preferences_contract_tests.swift -framework Carbon -framework Foundation -framework Security && "$HARNESS_WORK_DIR/translation_preferences_test"'
harness run azure-speech-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/azure_speech_test" glint-app/TranslationFormatting.swift glint-app/TranslationDocument.swift glint-app/SecureCredentialStore.swift glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/TextCommandHotKey.swift glint-app/HotKey.swift glint-app/azure_speech_contract_tests.swift -framework Carbon -framework Foundation -framework Security && "$HARNESS_WORK_DIR/azure_speech_test"'

# Azure GPT 结构化协议、内容保护、结构化报告、工作台唯一入口与 Translator/GPT 编排
harness run translation-processing-modes-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/translation_processing_modes_test" glint-app/TranslationFormatting.swift glint-app/TranslationDocument.swift glint-app/SecureCredentialStore.swift glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/TextCommandHotKey.swift glint-app/HotKey.swift glint-app/translation_processing_modes_contract_tests.swift -framework Carbon -framework Foundation -framework Security && "$HARNESS_WORK_DIR/translation_processing_modes_test"'
harness run translation-structure-preservation-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/translation_structure_preservation_test" glint-app/TranslationFormatting.swift glint-app/translation_structure_preservation_contract_tests.swift -framework Foundation && "$HARNESS_WORK_DIR/translation_structure_preservation_test"'
harness run translation-ai-protocol-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/translation_ai_protocol_test" glint-app/TranslationFormatting.swift glint-app/TranslationDocument.swift glint-app/SecureCredentialStore.swift glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/TextCommandHotKey.swift glint-app/HotKey.swift glint-app/TranslationAIService.swift glint-app/translation_ai_protocol_contract_tests.swift -framework Carbon -framework Foundation -framework Security && "$HARNESS_WORK_DIR/translation_ai_protocol_test"'
harness run translation-content-validation-tests --timeout 30s -- bash -c 'swiftc -parse-as-library -o "$HARNESS_WORK_DIR/translation_content_validation_test" glint-app/TranslationContentValidator.swift glint-app/translation_content_validation_contract_tests.swift -framework Foundation && "$HARNESS_WORK_DIR/translation_content_validation_test"'
harness run translation-ai-batching-tests --timeout 30s -- bash -c 'swiftc -parse-as-library -o "$HARNESS_WORK_DIR/translation_ai_batching_test" glint-app/TranslationFormatting.swift glint-app/TranslationDocument.swift glint-app/TranslationContentValidator.swift glint-app/SecureCredentialStore.swift glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/TextCommandHotKey.swift glint-app/HotKey.swift glint-app/TranslationAIService.swift glint-app/TranslationBlockRenderer.swift glint-app/TranslationService.swift glint-app/translation_ai_batching_contract_tests.swift -framework AppKit -framework Carbon -framework Security && "$HARNESS_WORK_DIR/translation_ai_batching_test"'
harness run translation-structured-report-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/translation_structured_report_test" glint-app/TranslationFormatting.swift glint-app/TranslationDocument.swift glint-app/TranslationContentValidator.swift glint-app/SecureCredentialStore.swift glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/TextCommandHotKey.swift glint-app/HotKey.swift glint-app/TranslationAIService.swift glint-app/TranslationBlockRenderer.swift glint-app/TranslationClipboard.swift glint-app/translation_structured_report_contract_tests.swift -framework AppKit -framework Carbon -framework Security && "$HARNESS_WORK_DIR/translation_structured_report_test"'
harness run translation-service-orchestration-tests --timeout 30s -- bash -c 'swiftc -parse-as-library -o "$HARNESS_WORK_DIR/translation_service_orchestration_test" glint-app/TranslationFormatting.swift glint-app/TranslationDocument.swift glint-app/TranslationContentValidator.swift glint-app/SecureCredentialStore.swift glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/TextCommandHotKey.swift glint-app/HotKey.swift glint-app/TranslationAIService.swift glint-app/TranslationBlockRenderer.swift glint-app/TranslationService.swift glint-app/translation_service_orchestration_contract_tests.swift -framework AppKit -framework Carbon -framework Security && "$HARNESS_WORK_DIR/translation_service_orchestration_test"'
harness run translation-workbench-orchestration-tests --timeout 30s -- bash -c 'swiftc -parse-as-library -o "$HARNESS_WORK_DIR/translation_workbench_orchestration_test" glint-app/TranslationFormatting.swift glint-app/RecentResults.swift glint-app/TranslationWorkbench.swift glint-app/translation_workbench_orchestration_contract_tests.swift -framework Foundation && "$HARNESS_WORK_DIR/translation_workbench_orchestration_test"'
harness run translation-workbench-controls-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/translation_workbench_controls_test" glint-app/TranslationFormatting.swift glint-app/TranslationDocument.swift glint-app/TranslationWorkbench.swift glint-app/RecentResults.swift glint-app/TranslationClipboard.swift glint-app/Markdown.swift glint-app/TranslationWorkspaceView.swift glint-app/TranslationAIService.swift glint-app/TranslationContentValidator.swift glint-app/TranslationBlockRenderer.swift glint-app/SecureCredentialStore.swift glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/TextCommandHotKey.swift glint-app/HotKey.swift glint-app/translation_workbench_controls_contract_tests.swift -framework AppKit -framework Carbon -framework Security && "$HARNESS_WORK_DIR/translation_workbench_controls_test"'
harness run translation-workspace-layout-policy-tests --timeout 30s -- bash -c 'swiftc -parse-as-library -o "$HARNESS_WORK_DIR/translation_workspace_layout_policy_test" glint-app/TranslationFormatting.swift glint-app/TranslationDocument.swift glint-app/TranslationWorkbench.swift glint-app/RecentResults.swift glint-app/TranslationClipboard.swift glint-app/Markdown.swift glint-app/TranslationWorkspaceView.swift glint-app/TranslationAIService.swift glint-app/TranslationBlockRenderer.swift glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/TextCommandHotKey.swift glint-app/HotKey.swift glint-app/translation_workspace_layout_policy_contract_tests.swift -framework AppKit -framework Carbon && "$HARNESS_WORK_DIR/translation_workspace_layout_policy_test"'
harness run translation-workspace-frame-ownership-tests --timeout 30s -- bash -c 'swiftc -parse-as-library -o "$HARNESS_WORK_DIR/translation_workspace_frame_ownership_test" glint-app/TranslationFormatting.swift glint-app/TranslationDocument.swift glint-app/TranslationWorkbench.swift glint-app/RecentResults.swift glint-app/TranslationClipboard.swift glint-app/Markdown.swift glint-app/TranslationWorkspaceView.swift glint-app/TranslationAIService.swift glint-app/TranslationBlockRenderer.swift glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/TextCommandHotKey.swift glint-app/HotKey.swift glint-app/translation_workspace_frame_ownership_contract_tests.swift -framework AppKit -framework Carbon && "$HARNESS_WORK_DIR/translation_workspace_frame_ownership_test"'
harness run translation-workspace-panel-layout-state-tests --timeout 30s -- bash -c 'swiftc -parse-as-library -o "$HARNESS_WORK_DIR/translation_workspace_panel_layout_state_test" glint-app/TranslationFormatting.swift glint-app/TranslationDocument.swift glint-app/TranslationWorkbench.swift glint-app/RecentResults.swift glint-app/PopupLifecycle.swift glint-app/TranslationClipboard.swift glint-app/Markdown.swift glint-app/TranslationWorkspaceView.swift glint-app/TranslationAIService.swift glint-app/TranslationBlockRenderer.swift glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/TextCommandHotKey.swift glint-app/HotKey.swift glint-app/translation_workspace_panel_layout_state_contract_tests.swift -framework AppKit -framework Carbon && "$HARNESS_WORK_DIR/translation_workspace_panel_layout_state_test"'
harness run translation-workspace-presentation-tests --timeout 30s -- bash -c 'swiftc -parse-as-library -o "$HARNESS_WORK_DIR/translation_workspace_presentation_test" glint-app/TranslationFormatting.swift glint-app/TranslationDocument.swift glint-app/TranslationWorkbench.swift glint-app/RecentResults.swift glint-app/TranslationClipboard.swift glint-app/Markdown.swift glint-app/TranslationWorkspaceView.swift glint-app/TranslationAIService.swift glint-app/TranslationBlockRenderer.swift glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/TextCommandHotKey.swift glint-app/HotKey.swift glint-app/translation_workspace_presentation_contract_tests.swift -framework AppKit -framework Carbon && "$HARNESS_WORK_DIR/translation_workspace_presentation_test"'
harness run speech-settings-migration-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/speech_settings_migration_test" glint-app/TranslationFormatting.swift glint-app/TranslationDocument.swift glint-app/SecureCredentialStore.swift glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/TextCommandHotKey.swift glint-app/HotKey.swift glint-app/azure_speech_settings_migration_contract_tests.swift -framework Carbon -framework Foundation -framework Security && "$HARNESS_WORK_DIR/speech_settings_migration_test"'
```

若当前机器没有 `harness`，使用 `perl alarm` 或等价进程超时包装逐条执行，并在交付记录中如实说明。

## 2. 双架构类型检查

```bash
cd glint-app
SRCS=(main.swift Geometry.swift SelectedTextExtractor.swift TextCommandPanelLifecycle.swift TextCommandEntryPolicy.swift AccessibilitySelectionReader.swift TextCommandPanelController.swift Markdown.swift Screenshot.swift SecureCredentialStore.swift Config.swift ScreenshotHotKey.swift TextCommandHotKey.swift HotKey.swift HotKeyRecorderControl.swift Settings.swift BrandLogo.swift PopupLifecycle.swift RecentResults.swift RecentResultsPresentation.swift TranslationFormatting.swift TranslationDocument.swift TranslationService.swift TranslationWorkbench.swift TranslationClipboard.swift TranslationWorkspaceView.swift TranslationAIService.swift TranslationContentValidator.swift TranslationBlockRenderer.swift)
swiftc "${SRCS[@]}" -target arm64-apple-macos12.0 -swift-version 5 -framework AppKit -framework ApplicationServices -framework AVFoundation -framework Carbon -framework Security -typecheck
swiftc "${SRCS[@]}" -target x86_64-apple-macos12.0 -swift-version 5 -framework AppKit -framework ApplicationServices -framework AVFoundation -framework Carbon -framework Security -typecheck
```

## 3. 应用打包与安装替换

每次修改 [glint-app/](../../glint-app) 下的 Swift 源码后，必须按顺序执行：

```bash
cd glint-app && bash build.sh 'Glint Self Signed'

pkill -x Glint || true
GLINT_BACKUP_DIR="$(mktemp -d /tmp/glint-install-backup.XXXXXX)"
if [ -d /Applications/Glint.app ]; then
  mv /Applications/Glint.app "$GLINT_BACKUP_DIR/Glint.app"
fi
cp -R Glint.app /Applications/Glint.app
codesign --verify --deep --strict --verbose=2 /Applications/Glint.app
open /Applications/Glint.app
```

## 4. UI 与进程验收

- **本地 UI 自测（不读取真实选区、不联网）**：

  ```bash
  GLINT_CONFIG_DIR="$(mktemp -d /tmp/glint-config-text-command-panel.XXXXXX)" GLINT_UITEST=text_command_panel GLINT_UITEST_DIR=/tmp/glint-text-command-panel /Applications/Glint.app/Contents/MacOS/Glint
  GLINT_CONFIG_DIR="$(mktemp -d /tmp/glint-config-hotkey-settings.XXXXXX)" GLINT_UITEST=hotkey_settings GLINT_UITEST_DIR=/tmp/glint-hotkey-settings /Applications/Glint.app/Contents/MacOS/Glint
  GLINT_CONFIG_DIR="$(mktemp -d /tmp/glint-config-translate.XXXXXX)" GLINT_UITEST=translate GLINT_UITEST_DIR=/tmp/glint-translation-workspace /Applications/Glint.app/Contents/MacOS/Glint
  GLINT_CONFIG_DIR="$(mktemp -d /tmp/glint-config-settings.XXXXXX)" GLINT_UITEST=settings GLINT_UITEST_DIR=/tmp/glint-azure-settings /Applications/Glint.app/Contents/MacOS/Glint
  GLINT_CONFIG_DIR="$(mktemp -d /tmp/glint-config-pin-restore.XXXXXX)" GLINT_UITEST=pin_restore GLINT_UITEST_DIR=/tmp/glint-pin-restore /Applications/Glint.app/Contents/MacOS/Glint
  GLINT_CONFIG_DIR="$(mktemp -d /tmp/glint-config-recent-results.XXXXXX)" GLINT_UITEST=recent_results GLINT_UITEST_DIR=/tmp/glint-recent-results /Applications/Glint.app/Contents/MacOS/Glint
  ```

  `GLINT_CONFIG_DIR` 只用于显式测试隔离；未设置时生产环境仍使用 `~/.config/glint`。每次自测创建独立临时配置目录，避免读取或覆盖真实 Azure 配置。

- **运行状态与日志核查**：
  - 签名：`codesign --verify --deep --strict --verbose=2 /Applications/Glint.app`
  - 架构：`lipo -archs /Applications/Glint.app/Contents/MacOS/Glint`
  - 进程：`pgrep -fl /Applications/Glint.app/Contents/MacOS/Glint`
  - 日志：`tail -n 50 ~/.config/glint/glint.log`

- **跨应用矩阵**：使用自行构造的非敏感测试文字，在 Safari、Chrome、微信、企业微信、VS Code 和 TextEdit 中验证“选中文字 → 按文字快捷键 → 显示双按钮”；再验证普通拖选、双击、滚动条、消息列表滚动、Finder 文件/图标与桌面拖框均不会自动显示入口。日志只能核对来源类型和状态，不得记录选中文字或剪贴板正文。
