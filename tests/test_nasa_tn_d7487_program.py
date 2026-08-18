from __future__ import annotations

from dataclasses import replace
import hashlib
import importlib.util
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
PROGRAM_PATH = ROOT / "tools" / "nasa_tn_d7487" / "compressor_program.py"
ORIGINAL_DIR = (
    ROOT
    / "data"
    / "provenance"
    / "compressor_map"
    / "nasa_tn_d7487"
    / "original"
)

SPEC = importlib.util.spec_from_file_location("nasa_tn_d7487_program", PROGRAM_PATH)
assert SPEC is not None and SPEC.loader is not None
PROGRAM = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = PROGRAM
SPEC.loader.exec_module(PROGRAM)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class ProvenanceSnapshotTests(unittest.TestCase):
    def test_original_supplied_files_retain_their_recorded_hashes(self) -> None:
        expected = {
            "compressor_program.py": "84869e11152de778b98c736b76d5d4400710383b6ce930e70f215736d08a7ef8",
            "fortran_transcription.f": "4ad4b41a4710307e2242539effd7b8bfdb48c458bba5d2b399f46795bcb218b6",
            "README.md": "c2a6393f827e3882123c43fb742e7a116f11e78035d89812fb20ae178c847141",
            "sample_input.json": "511e7c4591820ab75c253587119e626198e00924a7638926a926c5f02bf16d66",
            "test_compressor_program.py": "02dd6ef56ac4a0529d0f964f0e835bce2de3f07afb52ad55a58cef6eab04089f",
        }
        for name, digest in expected.items():
            with self.subTest(name=name):
                self.assertEqual(sha256(ORIGINAL_DIR / name), digest)


class TwoPassControlFlowTests(unittest.TestCase):
    def test_second_pass_recomputes_surge_threshold_at_each_trial_point(self) -> None:
        config = PROGRAM.CompressorInput.from_json(ORIGINAL_DIR / "sample_input.json")
        vovcr = (0.4780, 0.4781, 0.4782, 0.58, 0.59, 0.60)
        config = replace(config, vovcr=vovcr, nvovcr=len(vovcr))

        result = PROGRAM.run_compressor(config)

        # NASA listing label 21-22 uses the current second-pass XMACH, not the
        # first-pass choking point XMACH. The narrow 0.4781/0.4782 pair makes
        # that otherwise rounded-away control-flow difference observable.
        self.assertEqual(result.points[0].vovcr, 0.4782)
        expected_surge = PROGRAM._interpolate_1d(
            result.points[0].throat_mach,
            PROGRAM.DIFLEM,
            PROGRAM.FLRNG,
        ) * result.choke_flow
        self.assertAlmostEqual(result.surge_flow, expected_surge, places=14)


if __name__ == "__main__":
    unittest.main()
