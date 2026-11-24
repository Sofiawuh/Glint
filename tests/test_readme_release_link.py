from pathlib import Path
import re
import unittest


REPO_ROOT = Path(__file__).resolve().parent.parent
README_PATH = REPO_ROOT / "README.md"
EXPECTED_RELEASES_URL = "https://github.com/Sofiawuh/Glint/releases"


class TestReadmeReleaseLink(unittest.TestCase):
    def test_releasesLink_pointsToCanonicalSofiawuhRepository(self) -> None:
        content = README_PATH.read_text(encoding="utf-8")
        release_links = re.findall(
            r"\[[^\]]*releases?[^\]]*\]\((https://github\.com/[^)]+/releases)\)",
            content,
            flags=re.IGNORECASE,
        )

        self.assertTrue(
            release_links,
            "README must include a Markdown Releases download link",
        )
        self.assertEqual(
            release_links,
            [EXPECTED_RELEASES_URL],
            "README Releases must point only to the canonical Sofiawuh/Glint repository",
        )


if __name__ == "__main__":
    unittest.main()
