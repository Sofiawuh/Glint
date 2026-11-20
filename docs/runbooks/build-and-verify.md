# 构建、安装与验收手册 (Build & Verify Runbook)

本手册规范 [glint-app/](../../glint-app) 的本地编译、签名校验、安装替换与自验收流程。

## 1. 几何、Markdown 与 Azure 协议单测验收

通过 `harness run` 在隔离沙盒中编译并执行测试：

```bash
# 几何定位测试
harness run geometry-tests --timeout 30s -- bash -c 'swiftc -o "$HARNESS_WORK_DIR/geo_test" glint-app/Geometry.swift glint-app/geometry_tests.swift -framework AppKit && "$HARNESS_WORK_DIR/geo_test"'

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

# 2. 停止运行中的进程、替换安装 /Applications/Glint.app 并重启
pkill -x Glint || true
rm -rf /Applications/Glint.app
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
  ```
- **运行状态与日志核查**：
  - 检查进程存活：`pgrep -fl /Applications/Glint.app/Contents/MacOS/Glint`
  - 检查运行日志：`tail -n 50 ~/.config/glint/glint.log`
