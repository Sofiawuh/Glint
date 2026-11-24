from pathlib import Path
import re
import unittest


REPO_ROOT = Path(__file__).resolve().parent.parent
SETTINGS_PATH = REPO_ROOT / "glint-app" / "Settings.swift"
CONFIG_PATH = REPO_ROOT / "glint-app" / "Config.swift"


def _function_body(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise AssertionError(f"Missing Swift function: {signature}")
    opening = source.find("{", start)
    if opening < 0:
        raise AssertionError(f"Missing function body: {signature}")
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[opening + 1 : index]
    raise AssertionError(f"Unterminated Swift function: {signature}")


class TestSettingsProbeLifecycle(unittest.TestCase):
    def setUp(self) -> None:
        self.settings = SETTINGS_PATH.read_text(encoding="utf-8")
        self.config = CONFIG_PATH.read_text(encoding="utf-8")

    def test_eachProbe_replacesAndCancelsItsPreviousCancellableTask(self) -> None:
        cases = (
            ("translatorProbeTask", "testTranslatorConnection"),
            ("gptProbeTask", "testGPTConnection"),
            ("speechProbeTask", "testSpeechConnection"),
        )

        for task_name, method_name in cases:
            with self.subTest(probe=method_name):
                has_retained_task = re.search(
                    rf"\b(?:private\s+)?var\s+{task_name}\s*:\s*URLSessionDataTask\?",
                    self.settings,
                )
                self.assertIsNotNone(
                    has_retained_task,
                    f"{method_name} must retain its URLSessionDataTask so it can be cancelled",
                )
                body = _function_body(self.settings, f"func {method_name}()")
                cancel_at = body.find(f"{task_name}?.cancel()")
                assign_match = re.search(rf"\b{task_name}\s*=", body)
                self.assertGreaterEqual(
                    cancel_at,
                    0,
                    f"{method_name} must cancel the previous probe before starting a new one",
                )
                self.assertIsNotNone(
                    assign_match,
                    f"{method_name} must retain the newly-created cancellable task",
                )
                assert assign_match is not None
                self.assertLess(
                    cancel_at,
                    assign_match.start(),
                    f"{method_name} must cancel the old task before replacing it",
                )

    def test_windowClose_cancelsAllOutstandingProbeTasks(self) -> None:
        body = _function_body(self.settings, "func windowWillClose(")
        for task_name in (
            "translatorProbeTask",
            "gptProbeTask",
            "speechProbeTask",
        ):
            with self.subTest(task=task_name):
                self.assertIn(
                    f"{task_name}?.cancel()",
                    body,
                    "Closing Settings must cancel every in-flight Azure connection probe",
                )

    def test_probeRequests_haveFiniteReasonableTimeouts(self) -> None:
        timeout_assignments = re.findall(
            r"request\.timeoutInterval\s*=\s*([^\n]+)", self.config
        )
        timeout_literals = [
            int(value)
            for assignment in timeout_assignments
            for value in re.findall(r"\b\d+\b", assignment)
        ]
        self.assertGreaterEqual(
            len(timeout_assignments),
            3,
            "Translator, GPT, and Speech request builders must all set explicit timeouts",
        )
        self.assertTrue(
            timeout_literals
            and all(1 <= timeout <= 60 for timeout in timeout_literals),
            f"Azure request timeouts must be finite and reasonable, got {timeout_assignments}",
        )


if __name__ == "__main__":
    unittest.main()
