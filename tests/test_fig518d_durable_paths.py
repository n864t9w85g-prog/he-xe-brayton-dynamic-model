from pathlib import Path
import unittest


class DurablePathTests(unittest.TestCase):
    def test_diagnostics_and_harness_use_durable_evidence(self):
        root = Path(__file__).resolve().parents[1]
        names = [
            'radiator_a1_contract.py', 'radiator_curve_energy_check.py',
            'radiator_parameter_family_check.py',
            'prepare_radiator_a1_candidates.m', 'run_radiator_a1_candidate.m',
            'steady53/create_component_harness.m',
        ]
        text = '\n'.join((root / 'tests' / name).read_text() for name in names)
        self.assertNotIn('tmp/steady53_curves_20260828/source_f8bcd83', text)
        self.assertNotIn('tmp/steady53_curves_20260828/radiator_scan', text)
        self.assertIn('data/provenance/baselines/f8bcd83', text)
        self.assertIn('data/provenance/steady53/fig5_18d', text)


if __name__ == '__main__':
    unittest.main()
