from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parent.parent
CONFIG_SWIFT = REPO_ROOT / "glint-app" / "Config.swift"
MAIN_SWIFT = REPO_ROOT / "glint-app" / "main.swift"
SETTINGS_SWIFT = REPO_ROOT / "glint-app" / "Settings.swift"
WORKSPACE_SWIFT = REPO_ROOT / "glint-app" / "TranslationWorkspaceView.swift"


class TestAzureTranslationLanguageRouting(unittest.TestCase):
    def test_workspace_exposes_automatic_and_common_fixed_target_languages(self) -> None:
        source = WORKSPACE_SWIFT.read_text(encoding="utf-8")
        self.assertIn(
            '"自动识别（中文 → 英语，其他 → 简体中文）"',
            source,
        )
        for code in (
            "zh-Hans",
            "zh-Hant",
            "en",
            "ja",
            "ko",
            "fr",
            "de",
            "es",
            "ru",
            "pt",
        ):
            self.assertIn(f'("{code}",', source)

    def test_automatic_target_rule_is_owned_by_azure_translation_preferences(self) -> None:
        config = CONFIG_SWIFT.read_text(encoding="utf-8")
        self.assertIn("struct TranslationPreferences", config)
        self.assertIn("AzureTranslatorConfig.targetLanguage(for: text)", config)
        self.assertIn('return "en"', config)
        self.assertIn('return "zh-Hans"', config)


class TestRemovedLegacyPromptSurface(unittest.TestCase):
    def test_runtime_has_no_legacy_provider_or_translation_prompt_store(self) -> None:
        config = CONFIG_SWIFT.read_text(encoding="utf-8")
        for legacy_symbol in (
            "LegacyAppConfig",
            "struct Provider:",
            "defaultTranslatePrompt",
            "resolvedTranslatePrompt",
            "setLanguageAndTranslatePrompt",
        ):
            self.assertNotIn(legacy_symbol, config)

    def test_target_language_is_configured_in_workbench_not_settings(self) -> None:
        settings = SETTINGS_SWIFT.read_text(encoding="utf-8")
        workspace = WORKSPACE_SWIFT.read_text(encoding="utf-8")
        main = MAIN_SWIFT.read_text(encoding="utf-8")

        self.assertNotIn("解释 Prompt", settings)
        self.assertNotIn("resolvedTranslatePrompt", main)
        self.assertIn("targetLanguagePopup", workspace)
        self.assertIn('setAccessibilityLabel("目标语言")', workspace)


if __name__ == "__main__":
    unittest.main()
