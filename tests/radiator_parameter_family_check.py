"""No-fit compatibility test for constant-input/constant-ratio radiators.

This checks a family of equations against scan readings, not a replacement model.
Requires only the standard library unless --plot is passed. Does not execute SLX.
"""
import argparse
import csv
import itertools
import json
import tempfile
import unittest
from pathlib import Path

from radiator_curve_energy_check import EVIDENCE, REPO, fluid_power, verify_snapshot


def endpoint_k(Ti, outlet_final, wall_final):
    if not Ti > outlet_final:
        raise ValueError('Requires hot inlet above final outlet.')
    return 1-(wall_final-outlet_final)/(Ti-outlet_final)


def normalized_power(Ti, outlet, wall, outlet_final, wall_final):
    """F/H [K] after imposing the same curve's steady endpoint, no fitted scale."""
    k = endpoint_k(Ti, outlet_final, wall_final)
    return k*(outlet_final-outlet)-(wall_final-wall)


def universal_upper(outlet, wall, outlet_final, wall_final, uncertainty):
    """Strict upper bound on F/H for all hot Ti, given two ordering conditions.

    Conditions under uncertainty: final wall > final outlet; final outlet > outlet.
    All four individual readings have independent +/-uncertainty K allowance.
    This bound uses k<1, so does not require an exact Ti, alpha, cp, flow or hA.
    """
    if wall_final-outlet_final <= 2*uncertainty:
        raise ValueError('Final wall/outlet ordering not robust.')
    if outlet_final-outlet <= 2*uncertainty:
        raise ValueError('Outlet rise to final value not robust.')
    return (wall-outlet)-(wall_final-outlet_final)+4*uncertainty


def read_points():
    with (EVIDENCE/'points.csv').open() as stream:
        return [{k: float(v) for k, v in r.items()} for r in csv.DictReader(stream)]


def run(make_plot):
    before = verify_snapshot()
    rows = read_points()
    end = rows[-1]  # 187.96 s plateau proxy; original scan, not a simulated endpoint.
    Oe, We = end['outlet_K'], end['wall_K']
    uncertainty = 3.
    records = []
    for row in rows:
        O, W = row['outlet_K'], row['wall_K']
        upper = None
        if Oe-O > 2*uncertainty:
            upper = universal_upper(O, W, Oe, We, uncertainty)
        records.append(dict(time_s=row['time_s'], gap_K=W-O,
            universal_F_over_H_upper_K=upper,
            nominal_F_over_H_at_Ti60958_K=normalized_power(609.58, O, W, Oe, We),
            violates_algebraic_and_monotonic_positive_storage=(upper is not None and upper < 0)))
    assert sum(r['violates_algebraic_and_monotonic_positive_storage'] for r in records) == 5
    result = dict(
        source_hashes=before,
        plateau_proxy=dict(time_s=end['time_s'], outlet_K=Oe, wall_K=We, gap_K=We-Oe),
        temperature_reading_allowance_K=uncertainty,
        nominal_endpoint_k=endpoint_k(609.58, Oe, We),
        per_reading_allowance_to_erase_first_universal_gap_K=(We-Oe-records[0]['gap_K'])/4,
        assumptions=[
            'Constant inlet Ti > final outlet.',
            'Constant positive C=mdot*cp and H=h*A_exchange, or constant positive C/H.',
            'Fixed average temperature alpha*Ti+(1-alpha)*To, 0<alpha<1.',
            'Same measured wall/outlet quantities at transient and steady endpoint.',
            'Late scan plateau approximates steady state; +/-3 K is a reading allowance, not a formal tolerance.',
            'For stored-fluid case only: nonnegative thermal capacity and monotonically increasing outlet.',
        ],
        algebra=[
            'r=C/H; k=r+1-alpha.',
            'At steady state: k=1-(Tw_inf-To_inf)/(Ti-To_inf)<1.',
            'F/H=k*(To_inf-To)-(Tw_inf-Tw).',
            'If To<To_inf: F/H<(Tw-To)-(Tw_inf-To_inf).',
            'Algebraic case requires F=0; positive storage with rising To requires F>0.',
            'Radiator mass, wall cp, radiative area and emissivity are absent from this necessary condition.',
        ],
        limits=[
            'No conclusion about arbitrary time-varying boundaries, cp/h ratios, distributed wall fields or different plotted signals.',
            'Negative bound at a sample rules out algebraic matching there; a dynamic contradiction additionally assumes no hidden local cooling at that point.',
            'Does not prove that every interpretation of the thesis is impossible or that its original implementation used these exact equations.',
            'No coefficients inferred here are applied to any model; no new acceptance threshold.',
        ], samples=records)
    out = Path(tempfile.mkdtemp(prefix='radiator_family_20260828_', dir=REPO/'tmp'))
    (out/'compatibility.json').write_text(json.dumps(result, indent=2)+'\n')
    with (out/'gap_bounds.csv').open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=records[0].keys())
        writer.writeheader(); writer.writerows(records)
    if make_plot:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        fig, ax = plt.subplots(figsize=(10, 5.5), layout='constrained')
        gap = We-Oe
        ax.axhspan(gap-6, gap+6, color='tab:red', alpha=.14,
                   label='Late plateau gap +/-6 K from two +/-3 K readings')
        ax.axhline(gap, color='tab:red', linestyle='--', linewidth=1.2)
        ax.errorbar([r['time_s'] for r in records], [r['gap_K'] for r in records],
                    yerr=6, xerr=2, fmt='o', markersize=4, capsize=3,
                    color='tab:blue', label='Original scan: wall minus outlet; no curve fitting')
        ax.set(xlabel='Time (s)', ylabel='Wall minus outlet temperature (K)',
               xlim=(0, 200), ylim=(15, 80),
               title='Fig. 5.18(d): the temperature gap grows toward its final value\n'
                     'Constant-input, constant-ratio Eq. 5.15 requires the opposite gap ordering during outlet rise')
        ax.grid(alpha=.2); ax.legend(loc='lower right', fontsize=8)
        fig.savefig(out/'gap_compatibility.png', dpi=160)
        plt.close(fig)
    assert verify_snapshot() == before
    print(json.dumps(dict(output=str(out), plateau=result['plateau_proxy'],
        nominal_k=result['nominal_endpoint_k'], samples=records[:6],
        erasure_allowance_K=result['per_reading_allowance_to_erase_first_universal_gap_K']), indent=2))


class FamilyChecks(unittest.TestCase):
    def test_eliminated_formula_equals_full_balance(self):
        for Ti, alpha in itertools.product([610., 1000., 1e6], [.2, .5, .8]):
            Oe, We, O, W, H = 358., 418., 265., 300., 10000.
            k = endpoint_k(Ti, Oe, We)
            r = k-1+alpha
            if r <= 0:
                continue
            full = fluid_power(Ti, O, W, r*H, H)/H if alpha == .8 else (
                r*(Ti-O)-(alpha*Ti+(1-alpha)*O-W))
            self.assertAlmostEqual(full, normalized_power(Ti, O, W, Oe, We), places=8)

    def test_all_reading_corners_below_universal_upper(self):
        upper = universal_upper(251., 284., 358., 418., 3.)
        for a, b, c, d in itertools.product([-3., 3.], repeat=4):
            for Ti in [500., 610., 1000., 1e6]:
                value = normalized_power(Ti, 251+a, 284+b, 358+c, 418+d)
                self.assertLess(value, upper)

    def test_positive_storage_compatible_example_not_rejected(self):
        self.assertGreater(normalized_power(610., 350., 420., 358., 418.), 0.)

    def test_ordering_guards(self):
        with self.assertRaises(ValueError):
            endpoint_k(300., 358., 418.)
        with self.assertRaises(ValueError):
            universal_upper(356., 380., 358., 418., 3.)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--plot', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        unittest.main(argv=['radiator_parameter_family_check'], verbosity=2)
    else:
        run(args.plot)
