from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parent.parent
MAIN_SWIFT_PATH = REPO_ROOT / "glint-app" / "main.swift"


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


class TestLogLineSerialization(unittest.TestCase):
    def test_logLine_fileAppendIsDelegatedOrProtectedBySerialization(self) -> None:
        source = MAIN_SWIFT_PATH.read_text(encoding="utf-8")
        body = _function_body(source, "func logLine(")

        performs_direct_seek_and_write = (
            "seekToEndOfFile" in body and ".write(" in body
        )
        synchronization_markers = (
            ".sync",
            ".async",
            ".lock()",
            "withLock",
            "appendLogLine",
            "logWriter",
        )
        is_serialized = any(marker in body for marker in synchronization_markers)

        self.assertTrue(
            not performs_direct_seek_and_write or is_serialized,
            "logLine must not race concurrent FileHandle seek/write operations; "
            "delegate appends to a serialized writer or protect the whole append operation",
        )


if __name__ == "__main__":
    unittest.main()
