"""Fixed-wall single-channel references; NOT an IHX/thesis reproduction.

Read-only SLX XML/parameter checks. No MATLAB, SLX load/sim/save, parameter
fit, or formal property changes. This uses the inherited hot-region h and
the calibrated formal Li cp frozen at 1200 K, without endorsing either.
The advection/exchange PDE omits axial conduction and wall dynamics.
"""
import csv
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

import numpy as np


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def protected_check(records):
    for record in records:
        assert digest(Path(record['paths'])) == record['hashes'], record['paths']


def integrate(B, C, H, H_am, kind, dt, end=1.5):
    """Independent RK4 of energy balances, not transfer-function formulas."""
    count = round(end / dt)
    times = np.arange(count + 1) * dt
    states = np.zeros((count + 1, 6))

    def inlet(t):
        return 4. if kind == 'step' else -4. * math.expm1(-t / .2)

    def rhs(t, s):
        x, y, xl, yl, mean, mean_matched = s
        u = inlet(t)
        q_old = H * x  # prescribed wall deviation = zero
        q1, q2 = H / 2 * xl, H / 2 * yl
        return np.array([
            (C * (u - x) - q_old / 2) / (B / 2),
            (C * (x - y) - q_old / 2) / (B / 2),
            (C * (u - xl) - q1) / (B / 2),
            (C * (xl - yl) - q2) / (B / 2),
            (C * (u - (2 * mean - u)) - H * mean) / B,
            (C * (u - (2 * mean_matched - u)) - H_am * mean_matched) / B,
        ])

    # Local energy closure for arbitrary non-equilibrium states. This does
    # NOT certify that an endpoint arithmetic mean is true spatial storage.
    s = np.array([.4, .7, .5, .2, .3, .8])
    f, u = rhs(.13, s), inlet(.13)
    residuals = [
        B / 2 * (f[0] + f[1]) - (C * (u - s[1]) - H * s[0]),
        B / 2 * (f[2] + f[3]) - (C * (u - s[3]) - H / 2 * (s[2] + s[3])),
        B * f[4] - (C * (u - (2 * s[4] - u)) - H * s[4]),
        B * f[5] - (C * (u - (2 * s[5] - u)) - H_am * s[5]),
    ]
    assert max(abs(v) for v in residuals) < 1e-8
    for i, t in enumerate(times[:-1]):
        s = states[i]
        k1 = rhs(t, s)
        k2 = rhs(t + dt / 2, s + dt / 2 * k1)
        k3 = rhs(t + dt / 2, s + dt / 2 * k2)
        k4 = rhs(t + dt, s + dt * k3)
        states[i + 1] = s + dt / 6 * (k1 + 2 * k2 + 2 * k3 + k4)
    inputs = np.array([inlet(t) for t in times])
    outputs = np.column_stack((states[:, 1], states[:, 3],
                               2 * states[:, 4] - inputs,
                               2 * states[:, 5] - inputs))
    delay, gain = B / C, math.exp(-H / C)
    exact = np.array([0. if t < delay else gain * inlet(t - delay) for t in times])
    return times, inputs, outputs, exact, residuals


def main():
    repo = Path(__file__).resolve().parents[1]
    active = repo.parent / (repo.name + '_副本')
    slx = active / 'final_steady_24a.slx'
    li = active / 'Lithium_property_simulink.m'
    manifest = repo / 'tmp/tp80484fa0_602f_4386_89ed_ae9ca96b3359/protected_after.csv'
    scalar = repo / 'tmp/tpf0a72ead_e5f7_48b0_bc8f_e26c293b272a/audit.json'
    with manifest.open() as f:
        protected = list(csv.DictReader(f))
    assert len(protected) == 34
    protected_check(protected)
    assert digest(slx) == '0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391'
    assert digest(li) == '666a3a9d7bcb45e0e80afca4bd30e02bd19098ce72cc56bfe9a5f528c67b4c4f'
    assert digest(scalar) == '97dc2fb957e1260d31695dafb38bb9021eb049a5d2b14e24a6328f59736df7c3'
    values = []
    with zipfile.ZipFile(slx) as z:
        for part in ('278', '388'):
            root = ET.fromstring(z.read(f'simulink/systems/system_{part}.xml'))
            inventory = {b.get('Name'): {p.get('Name'): p.text for p in b.findall('P')}
                         for b in root.findall('Block')}
            values.append([float(inventory[n]['Value']) for n in
                           ('h_Li', 'A_region', 'm_Li_region')])
    assert values[0] == values[1] == [10544., 7.031, .6588]
    h, area, mass = values[0]
    mdot, T0 = 4.572, 1200.  # fixed thesis boundary; diagnostic IC, not saved SLX IC
    cp = .9615 * 1000 * (104400 / T0**2 - 135.1 / T0 + 4.180)
    old_cp = json.loads(scalar.read_text())['uniform_input_coupling'][1]['cp_uniform_J_kgK']
    assert math.isclose(cp, old_cp, rel_tol=1e-14)
    B, C, H = mass * cp, mdot * cp, h * area
    n, delay = H / C, B / C
    a, b = (2 * C + H) / B, 2 * C / B
    H_am = 2 * C * math.tanh(n / 2)  # steady identity ONLY, not a chosen patch
    am = (2 * C + H_am) / B
    gains = dict(current_two_state=(2 * C - H) / (2 * C + H),
                 local_two_cell=(2 * C / (2 * C + H))**2,
                 literal_endpoint=(2 * C - H) / (2 * C + H),
                 static_matched_endpoint=(2 * C - H_am) / (2 * C + H_am),
                 advection_exchange_exact=math.exp(-n))
    assert gains['current_two_state'] < 0 < gains['advection_exchange_exact']
    assert math.isclose(gains['static_matched_endpoint'], math.exp(-n), rel_tol=1e-13)
    assert H_am < 2 * C < H

    # Independent linear-system frequency check, including the -1 feedthrough
    # from y=2*M-u. An outlet-state ODE that drops B*u' is a DIFFERENT model.
    matrix = np.array([[-a, 0.], [(2 * C - H) / B, -b]])
    errors = []
    for omega in (0., .1, 1., 10., 100., 1000.):
        s = 1j * omega
        original = np.linalg.solve(s * np.eye(2) - matrix, [b, 0.])[1]
        reduced = (2 * C - H) / (B * s + 2 * C + H)
        literal = (2 * C - H - B * s) / (B * s + 2 * C + H)
        errors += [abs(original - reduced * b / (s + b)),
                   abs(literal - (2 * b / (s + a) - 1))]
    assert max(errors) < 1e-12

    # Independent composite Simpson integral of steady spatial temperature.
    xi = np.linspace(0., 1., 2001)
    profile = np.exp(-n * xi)
    integral = (profile[0] + profile[-1] + 4 * sum(profile[1:-1:2])
                + 2 * sum(profile[2:-1:2])) / (3 * 2000)
    true_mean = -math.expm1(-n) / n
    endpoint_mean = (1 + math.exp(-n)) / 2
    assert abs(integral - true_mean) < 1e-12

    labels = list(gains)[:4]
    cases, arrays = {}, {}
    for kind in ('step', 'smooth_rise'):
        t, inputs, out, exact, residuals = integrate(B, C, H, H_am, kind, .0001)
        tf, uf, fine, ef, _ = integrate(B, C, H, H_am, kind, .00005)
        np.testing.assert_allclose(tf[::2], t, rtol=0, atol=1e-14)
        error = float(np.max(np.abs(out - fine[::2])))
        assert error < 1e-9
        assert np.all(exact >= 0) and np.all(out[:, 1] >= 0)
        assert min(out[:, 0]) < -.1 and min(out[:, 2]) < -.1 and min(out[:, 3]) < -.1
        analytic_error = {}
        if kind == 'step':
            analytic = np.column_stack([
                4 * gains['current_two_state'] * (1 - (a * np.exp(-b*t) - b*np.exp(-a*t)) / (a-b)),
                4 * gains['local_two_cell'] * (1 - np.exp(-a*t) * (1+a*t)),
                4 * (2*b/a * (1-np.exp(-a*t)) - 1),
                4 * (2*b/am * (1-np.exp(-am*t)) - 1),
            ])
            analytic_error['max_step_formula_error_K'] = float(np.max(np.abs(out-analytic)))
            assert analytic_error['max_step_formula_error_K'] < 1e-9
            assert out[0, 2] == out[0, 3] == -4.
        else:
            # A second analytic check: literal means with finite-slope input.
            r = 1/.2
            for j, rate in ((2, a), (3, am)):
                mean = 4*b*((1-np.exp(-rate*t))/rate
                            - (np.exp(-r*t)-np.exp(-rate*t))/(rate-r))
                err = float(np.max(np.abs(out[:, j]-(2*mean-inputs))))
                analytic_error[labels[j]+'_smooth_formula_error_K'] = err
                assert err < 1e-9
            assert out[0, 2] == 0 and out[1, 2] < 0
            assert out[0, 3] == 0 and out[1, 3] < 0
        metrics = {}
        for label, series in zip(labels+['advection_exchange_exact'], [*out.T, exact]):
            i = int(np.argmin(series))
            metrics[label] = dict(min_delta_out_K=float(series[i]), time_of_min_s=float(t[i]),
                                  final_sample_delta_out_K=float(series[-1]),
                                  infinite_time_delta_out_K=4*gains[label])
        cases[kind] = dict(metrics=metrics, dt_halving_error_K=error,
                           analytic_checks=analytic_error, energy_residuals_W=residuals)
        arrays[kind] = (t, inputs, out, exact)

    head = subprocess.check_output(['git','-C',str(active),'rev-parse','HEAD'], text=True).strip()
    archive = subprocess.check_output(['git','rev-parse','archive/pre-restart-20260824^{}'], cwd=repo, text=True).strip()
    assert head == 'f8bcd833e816eb681982b7dd04364e4b856948e3'
    assert archive == '8f625c268c35a95c18a626305c1aa6a79ae2ace7'
    run = Path(tempfile.mkdtemp(prefix='ihx_endpoint_reference_', dir=repo/'tmp'))
    for kind, (t, inputs, out, exact) in arrays.items():
        np.savetxt(run/(kind+'.csv'), np.column_stack((t, inputs, out, exact)), delimiter=',',
                   header=','.join(['time_s','delta_in_K']+labels+['advection_exchange_exact']), comments='')

    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    colors = ['#c23b32','#2171b5','#a63f8e','#d18a12','#19866c']
    titles = ['Current two-state equations', 'Prior local two-cell candidate',
              'Literal endpoint-mean storage', 'Steady-matched mean (NOT a patch)',
              'Advection/exchange reference']
    styles = ['-','-','--',':','-']
    fig, axes = plt.subplots(1, 2, figsize=(12.8, 5.8), sharey=True)
    for ax, kind in zip(axes, ('step', 'smooth_rise')):
        t, inputs, out, exact = arrays[kind]
        for series, color, title, style in zip([*out.T, exact], colors, titles, styles):
            ax.plot(t, series, color=color, label=title, linestyle=style, linewidth=2)
        ax.axhline(0, color='#777777', linewidth=.7)
        ax.set(xlabel='Time (s)', xlim=(0, 1.5), ylim=(-4.15,.65),
               title='+4 K inlet step' if kind=='step' else '+4 K smooth rise, 0.2 s time constant')
        ax.grid(alpha=.2)
    axes[0].set_ylabel('Outlet temperature change (K)')
    fig.suptitle('Fixed-wall single-channel diagnostic | steady matching does not ensure correct dynamics', fontsize=13, y=.98)
    handles, legend_labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, legend_labels, loc='lower center', ncol=3, bbox_to_anchor=(.5,.052), frameon=False, fontsize=9)
    fig.text(.5,.015,'Frozen cp at 1200 K; fixed wall. NOT the coupled IHX, Fig. 5.18, or a low-Pe validity proof.',ha='center',fontsize=9)
    fig.tight_layout(rect=(0,.19,1,.94))
    fig.savefig(run/'comparison.png', dpi=180)
    plt.close(fig)
    protected_check(protected)
    result = dict(
        scope='Offline fixed-wall single-channel ODE and analytic references. No SLX simulation or adoption.',
        frozen_parameters=dict(h_W_m2K=h, A_m2=area, m_kg=mass, mdot_kg_s=mdot,
            cp_J_kgK=cp, uniform_initial_and_wall_K=T0, B_J_K=B, C_W_K=C, H_W_K=H,
            NTU=n, residence_time_s=delay, H_am_steady_identity_only_W_K=H_am),
        gains=gains, cases=cases,
        steady_storage=dict(true_spatial_mean_per_unit_inlet=true_mean,
            endpoint_arithmetic_mean_per_unit_inlet=endpoint_mean,
            endpoint_over_true_spatial=endpoint_mean/true_mean,
            simpson_integral_error=abs(integral-true_mean)),
        frequency_identity_max_error=max(errors),
        correction_to_section20='The reduced outlet ODE omits B*dTin/dt. Its inlet transfer is NOT the literal variable-inlet Eq5.12 transfer; the latter has feedthrough -1.',
        limits=[
            'Inherited h is the prior 10/90 calibration, not an independently validated film coefficient.',
            'Formal cp includes the existing 0.9615 calibration; it is reused and frozen, not newly selected.',
            'The exact reference assumes uniform exchange, constant properties/flow, no axial conduction and a fixed wall.',
            'Uniform 1200 K initial conditions are diagnostic conditions, not the saved SLX initial states.',
            'Static matched conductance is an identity for this reference only, not a fit or authorized physics patch.',
            'Positive local-cell response does not establish accurate dynamics or thesis reproduction.',
        ],
        active_head=head, archive_commit=archive, protected_unchanged_count=len(protected),
        input_sha256={str(p):digest(p) for p in [Path(__file__),slx,li,manifest,scalar,
            repo/'空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf']},
        output_sha256={p.name:digest(p) for p in run.iterdir()})
    target = run/'evidence.json'
    target.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(dict(output=str(run), evidence_sha256=digest(target),
                         gains=gains, storage=result['steady_storage'], cases=cases), indent=2))
    print('FIXED_WALL_REFERENCE_CHECKS_PASS; PROTECTED_UNCHANGED=34; NO_SLX_SIMULATION')


if __name__ == '__main__':
    main()
