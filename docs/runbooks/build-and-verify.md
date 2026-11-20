# 构建、安装与验收手册 (Build & Verify Runbook)

本手册规范 [glint-app/](../../glint-app) 的本地编译、签名校验、安装替换与自验收流程。

## 1. 几何、Markdown 与 Azure 协议单测验收

通过 `harness run` 在隔离沙盒中编译并执行测试：

```bash
# 几何定位测试
harness run geometry-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/geo_test" glint-app/Geometry.swift glint-app/geometry_tests.swift -framework AppKit && "$HARNESS_WORK_DIR/geo_test"'

# 文本选区证据与控件拖动过滤
harness run selection-detection-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/selection_detection_test" glint-app/SelectionDetection.swift glint-app/selection_detection_tests.swift -framework Foundation -framework CoreGraphics && "$HARNESS_WORK_DIR/selection_detection_test"'

# 跨应用候选排序、未知角色拖选/双击降级和文件/图片剪贴板过滤
harness run selection-compatibility-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/selection_compatibility_test" glint-app/SelectionDetection.swift glint-app/selection_compatibility_tests.swift -framework Foundation -framework CoreGraphics && "$HARNESS_WORK_DIR/selection_compatibility_test"'

# 旧 AX 选区不得因拖动或双击重新进入复制降级
harness run selection-clipboard-fallback-regression-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/selection_clipboard_fallback_regression_test" glint-app/SelectionDetection.swift glint-app/selection_clipboard_fallback_regression_tests.swift -framework Foundation -framework CoreGraphics && "$HARNESS_WORK_DIR/selection_clipboard_fallback_regression_test"'

# 剪贴板恢复只能覆盖本事务自己的复制代次
harness run clipboard-restoration-generation-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/clipboard_restoration_generation_test" glint-app/SelectionDetection.swift glint-app/clipboard_restoration_generation_tests.swift -framework Foundation -framework CoreGraphics && "$HARNESS_WORK_DIR/clipboard_restoration_generation_test"'

# clipboard-only 入口失效后允许重新选择同应用同文本
harness run selection-clipboard-dedup-invalidation-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/selection_clipboard_dedup_invalidation_test" glint-app/SelectionDetection.swift glint-app/selection_clipboard_dedup_invalidation_tests.swift -framework Foundation -framework CoreGraphics && "$HARNESS_WORK_DIR/selection_clipboard_dedup_invalidation_test"'

# 微型入口悬停、展开、收回和代际令牌状态机
harness run selection-entry-lifecycle-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/selection_entry_lifecycle_test" glint-app/SelectionDetection.swift glint-app/SelectionEntryLifecycle.swift glint-app/selection_entry_lifecycle_tests.swift -framework Foundation -framework CoreGraphics && "$HARNESS_WORK_DIR/selection_entry_lifecycle_test"'

# 10×10 pt 赤陶色方块、22×22 pt 命中区、描边与阴影样式契约
harness run selection-entry-style-tests --timeout 30s -- bash -c 'swiftc -parse-as-library -o "$HARNESS_WORK_DIR/selection_entry_style_test" glint-app/SelectionEntryStyle.swift glint-app/selection_entry_style_tests.swift -framework AppKit && "$HARNESS_WORK_DIR/selection_entry_style_test"'

# 内部模拟复制、Escape 与普通用户按键复验策略
harness run selection-entry-keyboard-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/selection_entry_keyboard_test" glint-app/SelectionDetection.swift glint-app/SelectionEntryLifecycle.swift glint-app/SelectionEntryKeyboard.swift glint-app/selection_entry_keyboard_tests.swift -framework Foundation -framework CoreGraphics && "$HARNESS_WORK_DIR/selection_entry_keyboard_test"'

# Markdown 渲染测试
harness run markdown-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/md_test" glint-app/Markdown.swift glint-app/markdown_tests.swift -framework AppKit && "$HARNESS_WORK_DIR/md_test"'

# Azure Translator / Azure OpenAI v1 适配测试
harness run azure-services-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/azure_test" glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/azure_services_tests.swift -framework Carbon -framework Foundation && "$HARNESS_WORK_DIR/azure_test"'

# 结果窗口图钉 / 隐藏 / 恢复生命周期测试
harness run popup-lifecycle-tests --timeout 30s -- bash -c 'swiftc -parse-as-library -o "$HARNESS_WORK_DIR/popup_test" glint-app/PopupLifecycle.swift glint-app/popup_lifecycle_tests.swift && "$HARNESS_WORK_DIR/popup_test"'

# 截图快捷键值、迁移与切换事务
harness run hotkey-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/hotkey_test" glint-app/Config.swift glint-app/ScreenshotHotKey.swift glint-app/HotKey.swift glint-app/hotkey_tests.swift -framework Carbon -framework Foundation && "$HARNESS_WORK_DIR/hotkey_test"'

# 设置窗口录制生命周期
harness run hotkey-recording-lifecycle-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/hotkey_recording_lifecycle_test" glint-app/ScreenshotHotKey.swift glint-app/HotKey.swift glint-app/hotkey_recording_lifecycle_tests.swift -framework Carbon -framework Foundation && "$HARNESS_WORK_DIR/hotkey_recording_lifecycle_test"'

# Carbon 注册与注销生命周期（使用本地可注入边界，不注册真实系统快捷键）
harness run carbon-hotkey-lifecycle-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/carbon_hotkey_lifecycle_test" glint-app/ScreenshotHotKey.swift glint-app/HotKey.swift glint-app/carbon_hotkey_lifecycle_tests.swift -framework Carbon -framework Foundation && "$HARNESS_WORK_DIR/carbon_hotkey_lifecycle_test"'
```

## 2. 应用打包与安装替换

每次修改 [glint-app/](../../glint-app) 下的 Swift 源码后，必须按顺序执行：

```bash
# 1. 编译 Universal 二进制并打包 Glint.app 与 Glint.dmg
cd glint-app && bash build.sh 'Glint Self Signed'

# 2. 停止运行中的进程，将旧安装移动到临时备份目录，再替换并重启
pkill -x Glint || true
GLINT_BACKUP_DIR="$(mktemp -d /tmp/glint-install-backup.XXXXXX)"
if [ -d /Applications/Glint.app ]; then
  mv /Applications/Glint.app "$GLINT_BACKUP_DIR/Glint.app"
fi
cp -R Glint.app /Applications/Glint.app
codesign --verify --deep --strict --verbose=2 /Applications/Glint.app
open /Applications/Glint.app
```

## 3. UI 渲染与进程自验收

- **本地 UI 自测（无需联网）**：
  ```bash
  GLINT_UITEST=translate /Applications/Glint.app/Contents/MacOS/Glint
  GLINT_UITEST=hotkey_settings GLINT_UITEST_DIR=/tmp/glint-hotkey-settings /Applications/Glint.app/Contents/MacOS/Glint
  GLINT_UITEST=pin_restore GLINT_UITEST_DIR=/tmp/glint-pin-restore /Applications/Glint.app/Contents/MacOS/Glint
  GLINT_UITEST=selection_entry GLINT_UITEST_DIR=/tmp/glint-selection-entry /Applications/Glint.app/Contents/MacOS/Glint
  ```
- **运行状态与日志核查**：
  - 检查进程存活：`pgrep -fl /Applications/Glint.app/Contents/MacOS/Glint`
  - 检查运行日志：`tail -n 50 ~/.config/glint/glint.log`
- **跨应用选区矩阵**：使用自行构造的非敏感测试文字，分别验证 Safari、Chrome、微信、企业微信、VS Code 和 TextEdit 的拖选与双击；同时验证网页/编辑器滚动条、消息列表滚动、Finder 桌面文件/图标与桌面拖框均不显示入口。日志只核对 `path`、`role`、`range`、`bounds` 等布尔信息，不得记录选中文字或剪贴板正文。
