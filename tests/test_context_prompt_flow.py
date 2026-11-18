import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parent.parent
CONFIG_SWIFT = REPO_ROOT / "glint-app" / "Config.swift"
MAIN_SWIFT = REPO_ROOT / "glint-app" / "main.swift"
GLINT_APP_BIN = REPO_ROOT / "glint-app" / "Glint.app" / "Contents" / "MacOS" / "Glint"

_SWIFT_COMMON_HELPERS = r'''import Foundation

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ label: String) {
    guard lhs == rhs else {
        fail("\(label): expected \(rhs), got \(lhs)")
    }
}

func extractText(from content: Any?) -> String {
    if let text = content as? String {
        return text
    }
    if let parts = content as? [[String: Any]] {
        return parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }
    return ""
}

func assertNoSystemMessages(in messages: [[String: Any]], context: String) {
    for (idx, msg) in messages.enumerated() {
        if let role = msg["role"] as? String, role == "system" {
            fail("\(context): unexpected system role at index \(idx)")
        }
    }
}

func loadTestProviders() -> (openai: Provider, anthropic: Provider, gemini: Provider) {
    let glintConfigDir = ("~/.config/glint" as NSString).expandingTildeInPath
    let glintConfigPath = glintConfigDir + "/config.json"
    let fm = FileManager.default
    try! fm.createDirectory(atPath: glintConfigDir, withIntermediateDirectories: true)

    let configJSON = """
    {
      "active": "OpenAI",
      "providers": [
        {
          "name": "OpenAI",
          "format": "openai",
          "baseURL": "https://api.openai.com/v1",
          "apiKey": "sk-openai-test",
          "model": "gpt-4o",
          "vision": true
        },
        {
          "name": "Anthropic",
          "format": "anthropic",
          "baseURL": "https://api.anthropic.com",
          "apiKey": "sk-ant-test",
          "model": "claude-sonnet-4-20250514",
          "vision": true
        },
        {
          "name": "Gemini",
          "format": "gemini",
          "baseURL": "https://generativelanguage.googleapis.com/v1beta",
          "apiKey": "gem-test-key",
          "model": "gemini-2.5-flash",
          "vision": true
        }
      ]
    }
    """
    try! configJSON.write(toFile: glintConfigPath, atomically: true, encoding: .utf8)
    AppConfig.shared.load()

    guard let openai = AppConfig.shared.providers.first(where: { $0.name == "OpenAI" }),
          let anthropic = AppConfig.shared.providers.first(where: { $0.name == "Anthropic" }),
          let gemini = AppConfig.shared.providers.first(where: { $0.name == "Gemini" }) else {
        fail("Failed to load test providers from isolated config.json")
    }
    return (openai, anthropic, gemini)
}

func buildRequestJSON(provider: Provider, messages: [[String: Any]]) -> [String: Any] {
    let requestOpt: URLRequest? = try? provider.buildRequest(
        messages: messages,
        temperature: 0.7,
        maxTokens: 1024,
        stream: true
    )
    guard let request = requestOpt else {
        fail("Provider.buildRequest returned nil for \(provider.name)")
    }
    guard let url = request.url, url.scheme == "https" else {
        fail("Invalid request URL for \(provider.name): \(String(describing: request.url))")
    }
    guard let body = request.httpBody, !body.isEmpty else {
        fail("Empty request body for \(provider.name)")
    }
    guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        fail("Request body is not a JSON dictionary for \(provider.name)")
    }
    return json
}
'''


def _compile_and_run_swift_probe(probe_source: str) -> subprocess.CompletedProcess[str]:
    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = Path(tmp_dir)
        home_dir = tmp_path / "home"
        home_dir.mkdir(parents=True, exist_ok=True)
        probe_file = tmp_path / "main.swift"
        probe_bin = tmp_path / "probe_context_prompt"
        probe_file.write_text(probe_source, encoding="utf-8")

        compile_proc = subprocess.run(
            [
                "swiftc",
                "-framework",
                "Foundation",
                str(CONFIG_SWIFT),
                str(probe_file),
                "-o",
                str(probe_bin),
            ],
            capture_output=True,
            text=True,
            check=False,
            timeout=30,
        )
        if compile_proc.returncode != 0:
            return compile_proc

        env = {
            **os.environ,
            "HOME": str(home_dir),
            "CFFIXED_USER_HOME": str(home_dir),
        }
        return subprocess.run(
            [str(probe_bin)],
            capture_output=True,
            text=True,
            env=env,
            check=False,
            timeout=30,
        )


class TestPromptContextMessageAssembly(unittest.TestCase):
    def test_payload_and_conversation_turn_support_value_equality(self) -> None:
        probe_source = (
            _SWIFT_COMMON_HELPERS
            + r"""
let textA = PromptContextPayload.text("hello")
let textB = PromptContextPayload.text("hello")
let textC = PromptContextPayload.text("world")
let imgA = PromptContextPayload.imageDataURL("data:image/png;base64,AAA=")
let imgB = PromptContextPayload.imageDataURL("data:image/png;base64,AAA=")
let imgC = PromptContextPayload.imageDataURL("data:image/png;base64,BBB=")

assertEqual(textA, textB, "identical .text payloads")
assertEqual(imgA, imgB, "identical .imageDataURL payloads")
guard textA != textC else { fail("distinct .text payloads should not be equal") }
guard imgA != imgC else { fail("distinct .imageDataURL payloads should not be equal") }
guard textA != imgA else { fail(".text and .imageDataURL payloads should not be equal") }

let turnA = ConversationTurn(role: "user", content: "explain")
let turnB = ConversationTurn(role: "user", content: "explain")
let turnC = ConversationTurn(role: "assistant", content: "explain")
let turnD = ConversationTurn(role: "user", content: "refactor")

assertEqual(turnA, turnB, "identical ConversationTurn values")
guard turnA != turnC else { fail("turns with different roles should not be equal") }
guard turnA != turnD else { fail("turns with different content should not be equal") }

print("VALUE_EQUALITY_OK")
"""
        )
        proc = _compile_and_run_swift_probe(probe_source)
        self.assertEqual(
            proc.returncode,
            0,
            f"Payload and ConversationTurn Equatable probe failed:\n{proc.stderr}",
        )
        self.assertIn("VALUE_EQUALITY_OK", proc.stdout)

    def test_can_submit_prompt_rejects_blank_and_accepts_non_empty_input(self) -> None:
        probe_source = (
            _SWIFT_COMMON_HELPERS
            + r"""
guard !PromptContextBuilder.canSubmitPrompt("") else {
    fail("empty string must not be submittable")
}
guard !PromptContextBuilder.canSubmitPrompt("   \n\t ") else {
    fail("whitespace-only string must not be submittable")
}
guard PromptContextBuilder.canSubmitPrompt("  帮我重构这个函数  ") else {
    fail("non-empty prompt with surrounding spaces must be submittable")
}
guard PromptContextBuilder.canSubmitPrompt("x") else {
    fail("single character prompt must be submittable")
}

print("CAN_SUBMIT_PROMPT_OK")
"""
        )
        proc = _compile_and_run_swift_probe(probe_source)
        self.assertEqual(
            proc.returncode,
            0,
            f"canSubmitPrompt probe failed:\n{proc.stderr}",
        )
        self.assertIn("CAN_SUBMIT_PROMPT_OK", proc.stdout)

    def test_preview_snippet_trims_whitespace_and_truncates_with_ellipsis(
        self,
    ) -> None:
        probe_source = (
            _SWIFT_COMMON_HELPERS
            + r"""
let trimmedShort = PromptContextBuilder.previewSnippet(
    for: "  \n  hello world \t\n  ",
    maxLines: 3,
    maxChars: 80
)
assertEqual(trimmedShort, "hello world", "short trimmed snippet")

let multiShort = PromptContextBuilder.previewSnippet(
    for: "\n  line one\nline two  \n",
    maxLines: 3,
    maxChars: 80
)
guard !multiShort.hasPrefix(" "), !multiShort.hasPrefix("\n"),
      !multiShort.hasSuffix(" "), !multiShort.hasSuffix("\n"),
      multiShort.contains("line one"), multiShort.contains("line two"),
      !multiShort.contains("…") else {
    fail("short multi-line snippet altered unexpectedly: \(multiShort)")
}

let cappedLines = PromptContextBuilder.previewSnippet(
    for: "  first line\nsecond line\nthird line\nfourth line  ",
    maxLines: 2,
    maxChars: 200
)
guard cappedLines.contains("first line"),
      cappedLines.contains("second line"),
      !cappedLines.contains("third line"),
      !cappedLines.contains("fourth line"),
      cappedLines.hasSuffix("…"),
      cappedLines.components(separatedBy: "\n").count <= 2 else {
    fail("maxLines truncation failed: \(cappedLines)")
}

let cappedChars = PromptContextBuilder.previewSnippet(
    for: "  abcdefghijklmnopqrstuvwxyz0123456789  ",
    maxLines: 5,
    maxChars: 12
)
guard cappedChars.hasSuffix("…"),
      cappedChars.hasPrefix("abcdefghijk"),
      !cappedChars.contains("0123456789"),
      cappedChars.count <= 13 else {
    fail("maxChars truncation failed: \(cappedChars)")
}

print("PREVIEW_SNIPPET_OK")
"""
        )
        proc = _compile_and_run_swift_probe(probe_source)
        self.assertEqual(
            proc.returncode,
            0,
            f"previewSnippet probe failed:\n{proc.stderr}",
        )
        self.assertIn("PREVIEW_SNIPPET_OK", proc.stdout)

    def test_build_messages_returns_empty_array_for_empty_turns(self) -> None:
        probe_source = (
            _SWIFT_COMMON_HELPERS
            + r"""
let textMessages = PromptContextBuilder.buildMessages(
    context: .text("let value = 42"),
    turns: []
)
guard textMessages.isEmpty else {
    fail("buildMessages(.text) with empty turns must return []")
}

let imageMessages = PromptContextBuilder.buildMessages(
    context: .imageDataURL("data:image/png;base64,iVBORw0KGgo="),
    turns: []
)
guard imageMessages.isEmpty else {
    fail("buildMessages(.imageDataURL) with empty turns must return []")
}

print("EMPTY_TURNS_OK")
"""
        )
        proc = _compile_and_run_swift_probe(probe_source)
        self.assertEqual(
            proc.returncode,
            0,
            f"Empty turns buildMessages probe failed:\n{proc.stderr}",
        )
        self.assertIn("EMPTY_TURNS_OK", proc.stdout)

    def test_text_context_multi_turn_assembly_and_provider_requests_omit_system_prompts(
        self,
    ) -> None:
        probe_source = (
            _SWIFT_COMMON_HELPERS
            + r'''
let selectedText = """
func binarySearch(_ arr: [Int], target: Int) -> Int? {
    return arr.firstIndex(of: target)
}
"""
let turns = [
    ConversationTurn(role: "user", content: "  列出潜在边界条件  "),
    ConversationTurn(role: "assistant", content: "1. 空数组"),
    ConversationTurn(role: "user", content: "补充 Swift 代码")
]

let messages = PromptContextBuilder.buildMessages(
    context: .text(selectedText),
    turns: turns
)
guard messages.count == 3 else {
    fail("expected 3 assembled messages, got \(messages.count)")
}
assertNoSystemMessages(in: messages, context: "buildMessages(.text)")

guard (messages[0]["role"] as? String) == "user",
      let firstContent = messages[0]["content"] as? String else {
    fail("first message must have role=user and string content")
}
guard firstContent.contains(selectedText),
      firstContent.contains("列出潜在边界条件"),
      !firstContent.contains("  列出潜在边界条件  "),
      !firstContent.contains("请解释") else {
    fail("first message content invalid: \(firstContent)")
}

guard (messages[1]["role"] as? String) == "assistant",
      (messages[1]["content"] as? String) == "1. 空数组",
      (messages[2]["role"] as? String) == "user",
      (messages[2]["content"] as? String) == "补充 Swift 代码" else {
    fail("subsequent turns were not preserved in order")
}

let providers = loadTestProviders()

let openaiJSON = buildRequestJSON(provider: providers.openai, messages: messages)
guard let openaiMessages = openaiJSON["messages"] as? [[String: Any]],
      openaiMessages.count == 3 else {
    fail("OpenAI request missing 3 messages")
}
assertNoSystemMessages(in: openaiMessages, context: "OpenAI text request")
let openaiFirst = extractText(from: openaiMessages[0]["content"])
guard (openaiMessages[0]["role"] as? String) == "user",
      openaiFirst.contains(selectedText),
      openaiFirst.contains("列出潜在边界条件"),
      !openaiFirst.contains("请解释"),
      (openaiMessages[1]["role"] as? String) == "assistant",
      extractText(from: openaiMessages[1]["content"]) == "1. 空数组",
      (openaiMessages[2]["role"] as? String) == "user",
      extractText(from: openaiMessages[2]["content"]) == "补充 Swift 代码" else {
    fail("OpenAI request messages did not preserve text context and turns")
}

let anthropicJSON = buildRequestJSON(provider: providers.anthropic, messages: messages)
guard anthropicJSON["system"] == nil else {
    fail("Anthropic JSON must not contain a system key")
}
guard let anthropicMessages = anthropicJSON["messages"] as? [[String: Any]],
      anthropicMessages.count == 3 else {
    fail("Anthropic request missing 3 messages")
}
assertNoSystemMessages(in: anthropicMessages, context: "Anthropic text request")
let anthropicFirst = extractText(from: anthropicMessages[0]["content"])
guard (anthropicMessages[0]["role"] as? String) == "user",
      anthropicFirst.contains(selectedText),
      anthropicFirst.contains("列出潜在边界条件"),
      !anthropicFirst.contains("请解释"),
      (anthropicMessages[1]["role"] as? String) == "assistant",
      extractText(from: anthropicMessages[1]["content"]) == "1. 空数组",
      (anthropicMessages[2]["role"] as? String) == "user",
      extractText(from: anthropicMessages[2]["content"]) == "补充 Swift 代码" else {
    fail("Anthropic request messages did not preserve text context and turns")
}

let geminiJSON = buildRequestJSON(provider: providers.gemini, messages: messages)
guard geminiJSON["systemInstruction"] == nil else {
    fail("Gemini JSON must not contain a systemInstruction key")
}
guard let geminiContents = geminiJSON["contents"] as? [[String: Any]],
      geminiContents.count == 3 else {
    fail("Gemini request missing 3 contents entries")
}
assertNoSystemMessages(in: geminiContents, context: "Gemini text request")
let geminiFirst = extractText(from: geminiContents[0]["parts"])
let geminiSecond = extractText(from: geminiContents[1]["parts"])
let geminiThird = extractText(from: geminiContents[2]["parts"])
guard (geminiContents[0]["role"] as? String) == "user",
      geminiFirst.contains(selectedText),
      geminiFirst.contains("列出潜在边界条件"),
      !geminiFirst.contains("请解释"),
      (geminiContents[1]["role"] as? String) == "model",
      geminiSecond == "1. 空数组",
      (geminiContents[2]["role"] as? String) == "user",
      geminiThird == "补充 Swift 代码" else {
    fail("Gemini request contents did not preserve text context and turns")
}

print("TEXT_CONTEXT_ASSEMBLY_OK")
'''
        )
        proc = _compile_and_run_swift_probe(probe_source)
        self.assertEqual(
            proc.returncode,
            0,
            f"Text context assembly and provider buildRequest probe failed:\n{proc.stderr}",
        )
        self.assertIn("TEXT_CONTEXT_ASSEMBLY_OK", proc.stdout)

    def test_image_context_assembly_and_provider_requests_build_multimodal_without_system_prompts(
        self,
    ) -> None:
        probe_source = (
            _SWIFT_COMMON_HELPERS
            + r"""
let dataURL = "data:image/png;base64,iVBORw0KGgo="
let userPrompt = "提取图中的报错信息并给出修复命令"
let messages = PromptContextBuilder.buildMessages(
    context: .imageDataURL(dataURL),
    turns: [ConversationTurn(role: "user", content: userPrompt)]
)

guard messages.count == 1 else {
    fail("expected 1 message for single-turn image context, got \(messages.count)")
}
assertNoSystemMessages(in: messages, context: "buildMessages(.imageDataURL)")

guard (messages[0]["role"] as? String) == "user",
      let contentParts = messages[0]["content"] as? [[String: Any]] else {
    fail("first image message must have role=user and array content")
}

let hasImageURLPart = contentParts.contains { part in
    (part["type"] as? String) == "image_url"
        && ((part["image_url"] as? [String: Any])?["url"] as? String) == dataURL
}
let hasUserTextPart = contentParts.contains { part in
    (part["type"] as? String) == "text"
        && (part["text"] as? String) == userPrompt
}
let combinedBuiltText = extractText(from: contentParts)
guard hasImageURLPart, hasUserTextPart, !combinedBuiltText.contains("请解释这张图片的内容。") else {
    fail("image message content parts missing image_url/text or containing hardcoded prompt")
}

let providers = loadTestProviders()

let openaiJSON = buildRequestJSON(provider: providers.openai, messages: messages)
guard let openaiMessages = openaiJSON["messages"] as? [[String: Any]],
      openaiMessages.count == 1,
      (openaiMessages[0]["role"] as? String) == "user",
      let openaiParts = openaiMessages[0]["content"] as? [[String: Any]] else {
    fail("OpenAI multimodal request structure invalid")
}
assertNoSystemMessages(in: openaiMessages, context: "OpenAI image request")
let openaiHasImage = openaiParts.contains { part in
    (part["type"] as? String) == "image_url"
        && ((part["image_url"] as? [String: Any])?["url"] as? String) == dataURL
}
let openaiText = extractText(from: openaiParts)
guard openaiHasImage, openaiText.contains(userPrompt), !openaiText.contains("请解释这张图片的内容。") else {
    fail("OpenAI multimodal request missing image_url or user prompt")
}

let anthropicJSON = buildRequestJSON(provider: providers.anthropic, messages: messages)
guard anthropicJSON["system"] == nil else {
    fail("Anthropic image JSON must not contain a system key")
}
guard let anthropicMessages = anthropicJSON["messages"] as? [[String: Any]],
      anthropicMessages.count == 1,
      (anthropicMessages[0]["role"] as? String) == "user",
      let anthropicParts = anthropicMessages[0]["content"] as? [[String: Any]] else {
    fail("Anthropic multimodal request structure invalid")
}
assertNoSystemMessages(in: anthropicMessages, context: "Anthropic image request")
let anthropicHasImage = anthropicParts.contains { part in
    guard (part["type"] as? String) == "image",
          let source = part["source"] as? [String: Any] else {
        return false
    }
    return (source["type"] as? String) == "base64"
        && (source["media_type"] as? String) == "image/png"
        && (source["data"] as? String) == "iVBORw0KGgo="
}
let anthropicText = extractText(from: anthropicParts)
guard anthropicHasImage, anthropicText.contains(userPrompt), !anthropicText.contains("请解释这张图片的内容。") else {
    fail("Anthropic multimodal request missing image block or user prompt")
}

let geminiJSON = buildRequestJSON(provider: providers.gemini, messages: messages)
guard geminiJSON["systemInstruction"] == nil else {
    fail("Gemini image JSON must not contain a systemInstruction key")
}
guard let geminiContents = geminiJSON["contents"] as? [[String: Any]],
      geminiContents.count == 1,
      (geminiContents[0]["role"] as? String) == "user",
      let geminiParts = geminiContents[0]["parts"] as? [[String: Any]] else {
    fail("Gemini multimodal request structure invalid")
}
assertNoSystemMessages(in: geminiContents, context: "Gemini image request")
let geminiHasImage = geminiParts.contains { part in
    guard let inline = (part["inlineData"] as? [String: Any]) ?? (part["inline_data"] as? [String: Any]) else {
        return false
    }
    let mime = (inline["mimeType"] as? String) ?? (inline["mime_type"] as? String)
    let data = inline["data"] as? String
    return mime == "image/png" && data == "iVBORw0KGgo="
}
let geminiText = extractText(from: geminiParts)
guard geminiHasImage, geminiText.contains(userPrompt), !geminiText.contains("请解释这张图片的内容。") else {
    fail("Gemini multimodal request missing inline image block or user prompt")
}

print("IMAGE_CONTEXT_ASSEMBLY_OK")
"""
        )
        proc = _compile_and_run_swift_probe(probe_source)
        self.assertEqual(
            proc.returncode,
            0,
            f"Image context assembly and provider buildRequest probe failed:\n{proc.stderr}",
        )
        self.assertIn("IMAGE_CONTEXT_ASSEMBLY_OK", proc.stdout)


class TestPromptComposerAppFlow(unittest.TestCase):
    def test_prompt_context_uitest_renders_pill_and_text_image_composers(
        self,
    ) -> None:
        self.assertTrue(
            GLINT_APP_BIN.is_file(),
            f"Missing built Glint app binary: {GLINT_APP_BIN}",
        )

        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            uitest_dir = tmp_path / "uitest"
            home_dir = tmp_path / "home"
            uitest_dir.mkdir(parents=True, exist_ok=True)
            home_dir.mkdir(parents=True, exist_ok=True)

            env = {
                **os.environ,
                "HOME": str(home_dir),
                "CFFIXED_USER_HOME": str(home_dir),
                "GLINT_UITEST": "prompt_context",
                "GLINT_UITEST_DIR": str(uitest_dir),
            }
            proc = subprocess.run(
                [str(GLINT_APP_BIN)],
                capture_output=True,
                text=True,
                env=env,
                check=False,
                timeout=30,
            )
            self.assertEqual(
                proc.returncode,
                0,
                f"Glint UITEST prompt_context exited {proc.returncode}:\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}",
            )
            self.assertIn("UITEST prompt_context PASS", proc.stdout)

            for artifact in (
                "pill_ask.png",
                "prompt_card_text.png",
                "prompt_card_image.png",
            ):
                png_path = uitest_dir / artifact
                self.assertTrue(
                    png_path.is_file(),
                    f"Missing prompt_context UI test PNG artifact: {png_path}",
                )
                png_bytes = png_path.read_bytes()
                self.assertGreater(
                    len(png_bytes),
                    1024,
                    f"{artifact} must be larger than 1024 bytes, got {len(png_bytes)}",
                )
                self.assertTrue(
                    png_bytes.startswith(b"\x89PNG\r\n\x1a\n"),
                    f"{artifact} must start with valid PNG magic header",
                )

    def test_main_swift_removes_hardcoded_explain_prompt_and_system_prompt(
        self,
    ) -> None:
        main_content = MAIN_SWIFT.read_text(encoding="utf-8")
        self.assertNotIn(
            "请解释这张图片的内容。",
            main_content,
            "glint-app/main.swift must not contain hardcoded image explain prompt",
        )
        self.assertNotIn(
            "resolvedExplainPrompt",
            main_content,
            "glint-app/main.swift must not reference legacy resolvedExplainPrompt",
        )


if __name__ == "__main__":
    unittest.main()
