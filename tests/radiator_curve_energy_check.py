"""Read-only radiator Eq. 5.15/5.16 diagnostic, NOT a model or calibration.

Uses the preserved f8bcd83 snapshot and digitized Fig. 5.18(d). Does not load
MATLAB, execute model callbacks, modify SLX/XML, or identify replacement values.
Run --self-test for algebra/units checks; otherwise writes a new tmp evidence dir.
Only Python's standard library is needed.
"""
from pathlib import Path
import argparse
import csv
import hashlib
import itertools
import json
import math
import re
import tempfile
import unittest
import xml.etree.ElementTree as ET
from zipfile import ZipFile

REPO = Path(__file__).resolve().parents[1]
EVIDENCE = REPO / "data/provenance/steady53/fig5_18d"
SOURCE = REPO / "data/provenance/baselines/f8bcd83"
RUNTIME = SOURCE / "runtime"
SCAN_POINTS = EVIDENCE / "paper_curve/points.csv"
SCAN_PROVENANCE = EVIDENCE / "paper_curve/provenance.json"
MODEL_HASH = "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def cp_nak(T):
    """Existing inlet-evaluated polynomial, J/(kg K); no property correction."""
    return 1000 * (1.061 - 3.694e-4*T + 4.615e-8*T*T + 1.509e-10*T**3)


def fluid_power(Ti, To, Tw, C, H):
    """Eq. 5.15 RHS [W], C=mdot*cp [W/K], H=h*A_exchange [W/K]."""
    return C*(Ti-To) - H*(.8*Ti + .2*To - Tw)


def fluid_bounds(Ti, To, Tw, C, H, delta_K):
    center = fluid_power(Ti, To, Tw, C, H)
    allowance = delta_K * (C + 1.2*H)
    return center-allowance, center+allowance


def linear_fourth_mean(a, b):
    """Exact average T^4 on a time-linear segment, stable also for a=b."""
    return sum(a**k * b**(4-k) for k in range(5)) / 5


def integrate_balances(rows, Ti, C, H, radiation_factor, Tenv):
    """Exact for piecewise-linear temperature interpolation, NOT raw paper data."""
    fluid_J = wall_J = 0.
    for a, b in zip(rows, rows[1:]):
        dt = b['time_s'] - a['time_s']
        if dt <= 0:
            raise ValueError('Time samples must be strictly increasing.')
        fa = fluid_power(Ti, a['outlet_K'], a['wall_K'], C, H)
        fb = fluid_power(Ti, b['outlet_K'], b['wall_K'], C, H)
        mean_out = (a['outlet_K']+b['outlet_K'])/2
        mean_wall = (a['wall_K']+b['wall_K'])/2
        fluid_J += dt*(fa+fb)/2
        wall_J += dt*(H*(.8*Ti+.2*mean_out-mean_wall) - radiation_factor*(
            linear_fourth_mean(a['wall_K'], b['wall_K'])-Tenv**4))
    return fluid_J, wall_J


def verify_snapshot():
    model = SOURCE / 'final_steady_24a.slx'
    if sha256(model) != MODEL_HASH:
        raise ValueError('Snapshot changed; do not silently reuse this diagnostic.')
    with ZipFile(model) as z:
        def block_props(member):
            root = ET.fromstring(z.read(member))
            return {b.attrib['Name']: {p.attrib['Name']: p.text
                    for p in b.findall('P')} for b in root.findall('Block')}
        constants = block_props('simulink/systems/system_3154.xml')
        core = block_props('simulink/systems/system_3143.xml')
        assert constants['Constant2']['Value'] == '1113'
        assert constants['Constant3']['Value'] == '5744'
        assert constants['Constant5']['Value'] == '9.755'
        assert constants['Constant4']['Value'] == 'Cp_rad'
        assert core['T_env']['Value'] == '225'
        assert core['Tho']['Expr'] == '((u(2)-0.8)*u(3)+u(1))/(u(2)+0.2)'
        assert core['Fcn1']['Expr'] == 'u(2)*(0.8*u(3)+0.2*u(6)-u(5))-u(1)*(u(5)^4-u(4)^4)'
    param_file = SOURCE/'sys_param_rad_fixed.m'
    params = param_file.read_text()
    for name, value in [('Cp_rad', '900'), ('epsilon', '0.9'), ('theta', '5.67e-8')]:
        assert re.search(r'^'+name+r'\s*=\s*'+re.escape(value)+r'\s*;', params, re.M)
    provenance_file = SCAN_PROVENANCE
    provenance = json.loads(provenance_file.read_text())
    assert provenance['source'].endswith('/paper-105.png')
    files = [model, param_file, provenance_file, SCAN_POINTS,
             SOURCE/'tests/steady53/steady53_component_boundaries.m']
    return {str(p.relative_to(REPO)): sha256(p) for p in files}


def diagnose():
    hashes = verify_snapshot()
    with SCAN_POINTS.open() as stream:
        rows = [{k: float(v) for k, v in row.items()} for row in csv.DictReader(stream)]
    assert len(rows) == 12 and all(math.isfinite(v) for r in rows for v in r.values())
    Ti, mdot, h, A_exchange, A_rad = 609.58, 6.95, 9.755, 1113., 1113.
    cp, H = cp_nak(Ti), h*A_exchange
    C, Crad = mdot*cp, 5744.*900
    R, Tenv = A_rad*.9*5.67e-8, 225.
    derived = []
    for row in rows:
        To, Tw = row['outlet_K'], row['wall_K']
        low, high = fluid_bounds(Ti, To, Tw, C, H, 3.)
        algebraic_out = ((C/H-.8)*Ti+Tw)/(C/H+.2)
        # Necessary pointwise upper bound for nonnegative fluid storage power.
        H_limit = C*(Ti-To)/(.8*Ti+.2*To-Tw)
        derived.append(dict(time_s=row['time_s'], wall_K=Tw, outlet_K=To,
            fluid_W=fluid_power(Ti, To, Tw, C, H),
            fluid_low_W=low, fluid_high_W=high,
            algebraic_outlet_K=algebraic_out,
            H_upper_for_nonnegative_storage_W_K=H_limit,
            current_wall_rate_K_s=(H*(.8*Ti+.2*To-Tw)-R*(Tw**4-Tenv**4))/Crad))
    intervals = []
    for first, last in [(1, 4), (0, 5), (1, 5)]:
        part = rows[first:last+1]
        Ef, Ew = integrate_balances(part, Ti, C, H, R, Tenv)
        dTo = part[-1]['outlet_K'] - part[0]['outlet_K']
        dTw = part[-1]['wall_K'] - part[0]['wall_K']
        intervals.append(dict(first_sample=first, last_sample=last,
            start_s=part[0]['time_s'], end_s=part[-1]['time_s'],
            fluid_energy_J=Ef, wall_energy_J=Ew,
            outlet_rise_K=dTo, outlet_rise_lower_with_3K_reading_K=dTo-6,
            wall_rise_K=dTw,
            implied_fluid_mass_kg=Ef/(cp*.2*dTo),
            implied_wall_capacity_J_K=Ew/dTw,
            warning='Inverse inconsistency diagnostic only; NEVER use as model parameters.'))
    # Regression checks on this bound dataset, not a claim of paper/model acceptance.
    assert all(r['fluid_high_W'] < 0 for r in derived[:6])
    assert all(r['implied_fluid_mass_kg'] < 0 for r in intervals)
    assert all(r['outlet_rise_lower_with_3K_reading_K'] > 0 for r in intervals)
    result = dict(baseline_commit='f8bcd833e816eb681982b7dd04364e4b856948e3',
        source_hashes=hashes,
        parameters=dict(Ti_K=Ti, mdot_kg_s=mdot, cp_J_kg_K=cp, C_W_K=C,
            h_W_m2_K=h, A_exchange_m2=A_exchange, A_rad_m2=A_rad,
            H_W_K=H, Crad_J_K=Crad, Tenv_K=Tenv),
        scope=[
            'No MATLAB/SLX simulation or model writes in this diagnostic.',
            'mdot=6.95 is a project boundary, not independently verified thesis data.',
            'Temperature readings +/-3 K, horizontal readings +/-2 s are approximate scan allowances, not acceptance thresholds.',
            'Pointwise power bounds are independent of time coordinate; they do not bound unknown paths between samples.',
            'Integral magnitudes assume piecewise-linear temperatures at the nominal scan times; no claim of exact author data.',
            'Positive storage alone is incompatible with the sampled rising trend under fixed current coefficients; this does not prove the thesis itself inconsistent.',
            'The thesis distinguishes A_exchange in hA from A_rad in radiation; equality here is only the current model implementation.',
            'No calibration, parameter promotion, full coupled stability or reproduction claim.'],
        samples=derived, intervals=intervals)
    out = Path(tempfile.mkdtemp(prefix='radiator_energy_20260828_', dir=REPO/'tmp'))
    (out/'energy_check.json').write_text(json.dumps(result, indent=2)+'\n')
    with (out/'sample_power_bounds.csv').open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=derived[0].keys())
        writer.writeheader(); writer.writerows(derived)
    assert verify_snapshot() == hashes, 'Inputs changed during diagnostic.'
    print(json.dumps(dict(output=str(out), parameters=result['parameters'],
        robust_negative_samples=sum(r['fluid_high_W'] < 0 for r in derived),
        intervals=intervals), indent=2))


class AlgebraChecks(unittest.TestCase):
    def test_existing_algebraic_relation_has_zero_storage(self):
        for Tw in [250., 360., 418.]:
            C, H, Ti = 6000., 10000., 610.
            To = ((C/H-.8)*Ti+Tw)/(C/H+.2)
            self.assertAlmostEqual(fluid_power(Ti, To, Tw, C, H), 0., places=7)

    def test_uncertainty_bounds_include_all_corners(self):
        args = (609.58, 280., 315., 6165., 10857.)
        lo, hi = fluid_bounds(*args, 3.)
        corners = [fluid_power(args[0], args[1]+a, args[2]+b, args[3], args[4])
                   for a, b in itertools.product([-3., 3.], repeat=2)]
        self.assertAlmostEqual(lo, min(corners), places=7)
        self.assertAlmostEqual(hi, max(corners), places=7)

    def test_known_positive_mass_is_not_rejected(self):
        # Manufacture a fluid-only exact solution; this is a test fixture, not physics calibration.
        Ti, C, H, cp, mass, dTo = 600., 5000., 10000., 900., 12., 2.
        rows = []
        for t in [0., 2., 5.]:
            To = 300.+dTo*t
            F = mass*cp*.2*dTo
            Tw = (F-C*(Ti-To))/H + .8*Ti+.2*To
            rows.append(dict(time_s=t, outlet_K=To, wall_K=Tw))
        E, _ = integrate_balances(rows, Ti, C, H, 0., 0.)
        recovered = E/(cp*.2*(rows[-1]['outlet_K']-rows[0]['outlet_K']))
        self.assertAlmostEqual(recovered, mass, places=9)

    def test_radiation_integral(self):
        self.assertAlmostEqual(linear_fourth_mean(2., 2.), 16.)
        self.assertAlmostEqual(linear_fourth_mean(1., 2.), (2.**5-1)/5)

    def test_reject_nonincreasing_time(self):
        rows = [dict(time_s=0., outlet_K=300., wall_K=300.)]*2
        with self.assertRaises(ValueError):
            integrate_balances(rows, 600., 5000., 10000., 1., 225.)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        unittest.main(argv=['radiator_curve_energy_check'], verbosity=2)
    else:
        diagnose()
