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
        self.assertNotIn('tmp/steady53_recheck_20260827', text)
        self.assertIn('data/provenance/baselines/f8bcd83', text)
        self.assertIn('data/provenance/steady53/fig5_18d', text)
        for module in ('radiator_curve_energy_check.py', 'radiator_parameter_family_check.py'):
            module_text = (root / 'tests' / module).read_text()
            for constant in ('REPO', 'EVIDENCE', 'SOURCE', 'RUNTIME', 'SCAN_POINTS', 'SCAN_PROVENANCE'):
                self.assertIn(constant, module_text)

    def test_normal_snapshot_verification_uses_existing_runtime_inputs(self):
        from tests import radiator_curve_energy_check as diagnostic
        self.assertTrue((diagnostic.RUNTIME / 'sys_param_rad_fixed.m').is_file())
        self.assertTrue(diagnostic.SCAN_POINTS.is_file())
        self.assertTrue(diagnostic.SCAN_PROVENANCE.is_file())
        hashes = diagnostic.verify_snapshot()
        self.assertIn('data/provenance/baselines/f8bcd83/runtime/sys_param_rad_fixed.m', hashes)

    def test_production_diagnostics_have_no_assert_statements(self):
        root = Path(__file__).resolve().parents[1]
        for name in ('radiator_curve_energy_check.py', 'radiator_parameter_family_check.py'):
            self.assertNotIn('assert ', (root / 'tests' / name).read_text())


if __name__ == '__main__':
    unittest.main()
