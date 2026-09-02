"""Contract tests for the immutable recovered rotating-map evidence bundle."""
from __future__ import annotations

import hashlib
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROVENANCE = (
    ROOT / "data/provenance/rotating_machinery/recovered_20260902"
)
EXPECTED = {
    "source/透平机程序.7z":
        "d0460bcbdb004dcdb447c37c5cf59e230511d1591af7d51e939f944545c35a98",
    "source/透平建模思路(1).docx":
        "0589e0f16107bdcd10f263b986aaea9607118ea31786b2daa580c0329c749f3b",
    "source/HeXe40_Xu2022_v2_stage9.zip":
        "eaf3c5d88a5b5ca15d1877dfcffee57c81d11c19159e6645dcf1e03ac44b0468",
    "source/Xu2022_PaperStyle_Equivalent_Lookup.mat":
        "f482a6a7388986727e09dd8b01b7614e1274952777c0b105f29827b96550eda6",
    "source/FULL_PROVENANCE.md":
        "83d3823f0b2db307a11e5a55b0d1459d43e9cdd439578594ebe88fab1a6eed76",
}


class RecoveredSourceManifestTests(unittest.TestCase):
    def test_recovered_sources_match_manifest(self) -> None:
        manifest = json.loads(
            (PROVENANCE / "manifest.json").read_text(encoding="utf-8")
        )
        self.assertEqual(manifest["schema"], "rotating_map_recovery_v1")
        self.assertEqual(len(manifest["files"]), 5)
        indexed = {item["repository_path"]: item for item in manifest["files"]}
        self.assertEqual(set(indexed), set(EXPECTED))
        for relative, digest in EXPECTED.items():
            with self.subTest(relative=relative):
                item = indexed[relative]
                path = PROVENANCE / relative
                self.assertTrue(path.is_file())
                self.assertFalse(path.is_symlink())
                self.assertEqual(path.stat().st_size, item["size_bytes"])
                self.assertEqual(
                    hashlib.sha256(path.read_bytes()).hexdigest(), digest
                )
                self.assertEqual(item["sha256"], digest)
                self.assertIn(item["evidence_level"], {"warning", "negative"})
                self.assertIs(item["author_original"], False)
                for field in (
                    "original_path",
                    "mtime_local",
                    "role",
                    "limitations",
                ):
                    self.assertTrue(item[field])

    def test_readme_keeps_candidate_limitations_explicit(self) -> None:
        text = (PROVENANCE / "README.md").read_text(encoding="utf-8")
        self.assertIn("✅", text)
        self.assertIn("⚠️", text)
        self.assertIn("❌", text)
        self.assertIn("PD/XK", text)
        self.assertIn("4.572 kg/s", text)
        self.assertIn("Gallo", text)
        self.assertIn("100%–110%", text)
        self.assertIn("不是徐驰作者原始查表矩阵", text)


if __name__ == "__main__":
    unittest.main()
