"""Numerical audit utilities only; no model or property modifications."""
import unittest
import numpy as np
from analyze_ihx_wall_storage import piecewise_energy, paper_wall_balance, settling_time


class WallAuditTests(unittest.TestCase):
    def test_linear_cp_exact_integral_and_reversed_path(self):
        # cp(T)=2*T+3; mass=4, reference=10.
        result = piecewise_energy(np.array([10., 12., 18., 9.]), 10., 4.,
                                  np.array([8., 11., 20.]), np.array([19., 25., 43.]))
        expected = 4 * (np.array([10., 12., 18., 9.])**2
                        + 3*np.array([10., 12., 18., 9.]) - 130)
        np.testing.assert_allclose(result, expected, atol=1e-11)

    def test_outside_lookup_domain_is_rejected(self):
        with self.assertRaises(ValueError):
            piecewise_energy(np.array([21.]), 10., 4.,
                             np.array([8., 20.]), np.array([19., 43.]))

    def test_wall_balance_known_equilibrium(self):
        # Hot/cold means 1500/1200, wall=1400: 2*100 == 1*200.
        qh, qc, net = paper_wall_balance(1600., 1400., 1100., 1300., 1400., 2., 1., 3.)
        self.assertEqual(qh, 600.)
        self.assertEqual(qc, 600.)
        self.assertEqual(net, 0.)

    def test_settling_requires_staying_inside_band(self):
        # The first crossing is not the settling time: later excursion to 8.
        self.assertEqual(settling_time(np.arange(6.), np.array([0., 9.8, 8., 9.7, 10., 10.])), 3.)
        self.assertEqual(settling_time(np.arange(3.), np.ones(3)), 0.)


if __name__ == '__main__':
    unittest.main()
