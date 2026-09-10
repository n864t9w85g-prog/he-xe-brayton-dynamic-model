"""Read-only IHX wall-energy and thesis Eq.5.14 compatibility audit.

Reuses completed 500 s CSV logs. Never loads/simulates/writes an SLX, changes a
property, or estimates parameters by fitting a curve. Outputs are diagnostics.
"""
import argparse
import csv
import hashlib
import itertools
import json
from pathlib import Path
import re
import tempfile
import xml.etree.ElementTree as ET
import zipfile
import numpy as np

REPO = Path(__file__).resolve().parents[1]


def piecewise_energy(temperature, reference, mass, bp, cp):
    """Exact integral of the piecewise-linear lookup, with no extrapolation."""
    t = np.asarray(temperature, dtype=float)
    bp, cp = np.asarray(bp, dtype=float), np.asarray(cp, dtype=float)
    if (len(bp) != len(cp) or len(bp) < 2 or not np.all(np.diff(bp) > 0)
            or not np.isfinite(t).all() or np.min(t) < bp[0] or np.max(t) > bp[-1]
            or not bp[0] <= reference <= bp[-1]):
        raise ValueError('Invalid lookup or temperature outside lookup domain')
    slopes = np.diff(cp) / np.diff(bp)
    accumulated = np.r_[0., np.cumsum(np.diff(bp) * (cp[:-1] + cp[1:]) / 2)]

    def primitive(v):
        i = np.clip(np.searchsorted(bp, v, side='right') - 1, 0, len(bp) - 2)
        dt = v - bp[i]
        return accumulated[i] + cp[i]*dt + slopes[i]*dt**2/2

    return mass * (primitive(t) - primitive(reference))


def paper_wall_balance(thi, tho, tci, tco, wall, hh, hc, area):
    qh = hh*area*((thi+tho)/2-wall)
    qc = hc*area*(wall-(tci+tco)/2)
    return qh, qc, qh-qc


def settling_time(t, y, fraction=.05):
    """First saved sample after the last excursion from own-final-value band."""
    bad = np.flatnonzero(np.abs(y-y[-1]) > fraction*abs(y[-1]-y[0]))
    return float(t[bad[-1]+1]) if len(bad) else float(t[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run_directory', type=Path)
    args = parser.parse_args()
    run = args.run_directory.resolve()
    assert run.is_relative_to(REPO/'tmp')
    assert 'ALL_FOUR_CASES_COMPLETE_SOURCE_PROTECTED_NOT_THESIS_ACCEPTANCE' in (run/'diary.txt').read_text()
    protected = list(csv.DictReader((run/'protected_after.csv').open()))
    digest = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
    for row in protected:
        assert digest(row['paths']) == row['hashes'], row['paths']
    prior = json.loads((run/'analysis/metrics.json').read_text())
    source = REPO/'tmp/steady53_curves_20260828/source_f8bcd83/final_steady_24a.slx'
    assert digest(source) == '0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391'
    # ZIP/XML is a read-only evidence source, never a model write route.
    inventories = []
    with zipfile.ZipFile(source) as archive:
        for part in ('278', '388'):
            root = ET.fromstring(archive.read(f'simulink/systems/system_{part}.xml'))
            inventories.append({b.get('Name'): {p.get('Name'): p.text for p in b.findall('P')}
                                for b in root.findall('Block')})
    value = lambda name: float(inventories[0][name]['Value'])
    hh, hc, area, mass = [value(n) for n in ('h_Li', 'h_HeXe', 'A_region', 'm_wall_region')]
    numeric = lambda s: np.array([float(x) for x in re.findall(r'-?\d+(?:\.\d+)?', s)])
    lookup = inventories[0]['cp_wall_lookup']
    bp = numeric(lookup['BreakpointsForDimension1'])
    cp = numeric(lookup['Table'])
    for inv in inventories[1:]:
        for name in ('h_Li', 'h_HeXe', 'A_region', 'm_wall_region', 'cp_wall_lookup'):
            # GUI layout may differ; compare behavior-defining fields only.
            fields = ('BreakpointsForDimension1', 'Table') if name == 'cp_wall_lookup' else ('Value',)
            for field in fields:
                assert inv[name][field] == inventories[0][name][field]
    assert 2*mass == 325 and 2*area == 14.062  # Thesis Table 5.1, visually checked.
    points_path = REPO/'tmp/tpf255e6c2_bcc0_4262_883f_5caf6d3f6a0d/analysis/paper_ihx_points.csv'
    points = np.genfromtxt(points_path, delimiter=',', names=True)
    scan = REPO/'tmp/steady53_recheck_20260827/paper-105.png'
    assert digest(scan) == prior['scan_sha256']
    assert digest(points_path) == prior['paper_samples_sha256']
    inputs = {str(source): digest(source), str(scan): digest(scan), str(points_path): digest(points_path)}
    output = Path(tempfile.mkdtemp(prefix='ihx_wall_audit_', dir=REPO/'tmp'))
    metrics, series, newly_hashed_inputs = {}, {}, []
    for case in ('original_500', 'candidate_500'):
        cache = {}

        def read(name):
            if name not in cache:
                path = run/case/(name+'.csv')
                key = f'{case}/{name}.csv'
                inputs[str(path)] = digest(path)
                if key in prior['input_hashes']:
                    assert inputs[str(path)] == prior['input_hashes'][key], key
                else:
                    # Earlier analysis did not read all ten temperature CSVs.
                    # Record fresh hashes without inventing a prior checksum.
                    assert re.fullmatch(r'state_\d{2}', name), key
                    newly_hashed_inputs.append(str(path))
                a = np.loadtxt(path, delimiter=',')
                assert np.isfinite(a).all() and a[0, 0] == 0 and a[-1, 0] == 500
                if cache:
                    assert np.array_equal(a[:, 0], next(iter(cache.values()))[:, 0])
                cache[name] = a
            return cache[name][:, 1]

        hot, cold = read('y_001'), read('y_003')
        t = cache['y_001'][:, 0]
        assert np.all(np.diff(t) > 0)
        wall_energy, wall_power, hot_heat, cold_heat, fluid_power = [np.zeros_like(t) for _ in range(5)]
        region_metrics = {}
        for r in (1, 2):
            f = lambda s: read(f'r{r}_{s}')
            s = lambda i: read(f'state_{i+5*(r-1):02}')
            w = s(5)
            e = piecewise_energy(w, w[0], mass, bp, cp)
            wall_energy += e
            wall_power += f('wall_capacity')*f('wall_d')
            hot_heat += f('wall_hot')
            cold_heat += f('cold_q')
            fluid_power += (f('hot_half_capacity')*(f('hot_d1')+f('hot_d2'))
                            +f('cold_half_capacity')*(f('cold_d1')+f('cold_d2')))
            cap_error = float(np.max(abs(f('wall_capacity')-mass*np.interp(w, bp, cp))))
            assert cap_error < 1e-5
            hi = np.full_like(t, 1600.) if r == 1 else read('state_04')
            ci = read('state_07') if r == 1 else np.full_like(t, 1100.91)
            eh, ec = s(3)-(hi+s(4))/2, s(1)-(ci+s(2))/2
            region_metrics[f'region{r}'] = dict(
                wall_energy_final_MJ=float(e[-1]/1e6), wall_final_K=float(w[-1]),
                wall_capacity_lookup_max_error_J_K=cap_error,
                hot_first_state_minus_endpoint_mean_max_K=float(max(abs(eh))),
                hot_first_state_minus_endpoint_mean_max_after8s_K=float(max(abs(eh[t>=8]))),
                hot_first_state_minus_endpoint_mean_final_K=float(eh[-1]),
                cold_first_state_minus_endpoint_mean_max_K=float(max(abs(ec))))
        closure = float(max(abs(wall_power-hot_heat+cold_heat)))
        assert closure < 1e-5
        integrated = np.r_[0., np.cumsum(np.diff(t)*(wall_power[:-1]+wall_power[1:])/2)]
        # Coarsening estimates sensitivity of the time integral, not a solver
        # convergence test. Exact lookup/state energy is the reference.
        errors = {}
        for stride in (1, 2, 4):
            indices = np.unique(np.r_[np.arange(0, len(t), stride), len(t)-1])
            errors[str(stride)] = float(np.trapezoid(wall_power[indices], t[indices])-wall_energy[-1])
        wall_mean = (read('state_05')+read('state_10'))/2
        qh_lump, qc_lump, net_lump = paper_wall_balance(1600., hot[-1], 1100.91, cold[-1],
                                                       wall_mean[-1], hh, hc, 2*area)
        m = dict(regions=region_metrics, wall_energy_final_MJ=float(wall_energy[-1]/1e6),
                 time_integrated_wall_energy_MJ=float(integrated[-1]/1e6),
                 wall_time_integral_error_J_by_stride=errors,
                 wall_time_integral_max_trajectory_difference_J=float(max(abs(integrated-wall_energy))),
                 integrated_implemented_fluid_storage_MJ=float(np.trapezoid(fluid_power, t)/1e6),
                 wall_balance_max_residual_W=closure,
                 actual_hot_to_wall_final_W=float(hot_heat[-1]),
                 actual_wall_to_cold_final_W=float(cold_heat[-1]),
                 own_final_5percent_settling_saved_sample_s={
                     'hot': settling_time(t, hot), 'cold': settling_time(t, cold),
                     'wall_mean': settling_time(t, wall_mean)},
                 # A deliberately tested mapping, not the active model heat.
                 two_wall_mean_inserted_in_paper_single_wall_equation_W={
                     'hot': float(qh_lump), 'cold': float(qc_lump), 'net': float(net_lump)})
        metrics[case] = m
        series[case] = dict(t=t, hot=hot, cold=cold, wall=wall_mean,
                            energy=wall_energy, hot_heat=hot_heat, cold_heat=cold_heat)
        np.savetxt(output/(case+'_wall_budget.csv'),
                   np.c_[t, hot_heat, cold_heat, wall_power, fluid_power, wall_energy, integrated],
                   delimiter=',', header='time_s,hot_to_wall_W,wall_to_cold_W,wall_storage_W,implemented_fluid_storage_W,wall_energy_J,integrated_wall_power_J', comments='')

    # Eq.5.14 at the digitized plateau: no mass flow or fluid cp appears.
    plateau = []
    for p in points[points['time_s'] >= 50]:
        tho, tco, w = p['hot_K'], p['cold_K'], p['wall_K']
        qh, qc, net = paper_wall_balance(1600., tho, 1100.91, tco, w, hh, hc, 2*area)
        corners, ratios = [], []
        for dh, dc, dw in itertools.product((-3., 3.), repeat=3):
            wh = w+dw
            corners.append(paper_wall_balance(1600., tho+dh, 1100.91, tco+dc, wh, hh, hc, 2*area)[2])
            ratios.append((wh-(1100.91+tco+dc)/2)/((1600+tho+dh)/2-wh))
        plateau.append(dict(time_s=float(p['time_s']), hot_K=float(tho), cold_K=float(tco), wall_K=float(w),
                            net_W=float(net), hot_W=float(qh), cold_W=float(qc),
                            net_bounds_for_three_temperatures_plusminus3K_W=[float(min(corners)),float(max(corners))],
                            required_hh_over_hc_bounds_not_applied=[float(min(ratios)),float(max(ratios))],
                            predicted_dwall_K_s=float(net/(2*mass*np.interp(w,bp,cp)))))
    # Do not assert compatibility or incompatibility as a self-test: retain the
    # computed result even if a future approved baseline changes the outcome.
    report = dict(cases=metrics, source_model_sha256=digest(source),
                  static_parameters=dict(area_per_region_m2=area, mass_per_region_kg=mass, hh_W_m2K=hh, hc_W_m2K=hc, hh_over_hc=hh/hc),
                  paper_plateau_single_wall_checks=plateau,
                  source_pdf_sha256=digest(REPO/'空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf'),
                  input_hashes=inputs,
                  first_hashed_in_this_audit=newly_hashed_inputs,
                  limits=['Reanalysis of previously completed simulations, no new simulation.',
                          'Table mass/area match, but alloy cp provenance not established by replay.',
                          'Fluid storage integral uses implemented local-cp balances, not independent enthalpy.',
                          'Two-wall arithmetic mean is a tested mapping, not established thesis T_IHX.',
                          'Eq.5.14 checks assume the published single-wall definition and fixed paper inlet temperatures.',
                          '+/-3 K is scan read-off sensitivity, not a formal acceptance tolerance.',
                          'Own-final-value settling metric is not paper reproduction acceptance.',
                          'No fitted value or inverse ratio is applied to any model.'])
    for row in protected:
        assert digest(row['paths']) == row['hashes']
    report['protected_files_rechecked'] = len(protected)
    (output/'metrics.json').write_text(json.dumps(report, indent=2)+'\n')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig, axs = plt.subplots(2, 2, figsize=(12, 8), layout='constrained')
    for case, style, label in [('original_500','--','Original'),('candidate_500','-','Local-hot candidate')]:
        d = series[case]
        for key, color in [('hot','tab:blue'),('cold','tab:red')]:
            axs[0,0].plot(d['t'],d[key],style,color=color,label=f'{label}: {key}')
        axs[0,1].plot(d['t'],d['energy']/1e6,style,label=label)
        axs[1,0].plot(d['t'],(d['hot_heat']-d['cold_heat'])/1e6,style,label=label)
    for key, color in [('hot','tab:blue'),('cold','tab:red')]:
        axs[0,0].errorbar(points['time_s'],points[key+'_K'],yerr=3,xerr=2,fmt='o',ms=3,color=color,mfc='white',label=f'Paper scan: {key}')
    axs[0,0].set(xlim=(0,55),ylim=(1150,1550),ylabel='Temperature (K)',title='Unshifted outlet curves')
    axs[0,1].set(xlim=(0,55),ylabel='Stored wall energy above initial (MJ)',title='Exact integral of active wall cp lookup')
    axs[1,0].set(xlim=(0,55),ylabel='Actual two-wall net heat (MW)',title='Logged hot-to-wall minus wall-to-cold')
    p = plateau[-1]
    values = [metrics[c]['two_wall_mean_inserted_in_paper_single_wall_equation_W']['net']/1e6 for c in metrics]+[p['net_W']/1e6]
    axs[1,1].bar(['Original\nwall-mean mapping','Candidate\nwall-mean mapping','Paper scan\nlast plateau'],values,color=['gray','tab:blue','tab:orange'])
    lo,hi = np.array(p['net_bounds_for_three_temperatures_plusminus3K_W'])/1e6
    axs[1,1].errorbar(2,values[2],yerr=[[values[2]-lo],[hi-values[2]]],fmt='none',ecolor='black',capsize=5)
    axs[1,1].axhline(0,color='black',lw=.8)
    axs[1,1].set(ylabel='Eq.5.14 net heat with current h, A (MW)',title='Tested single-wall mapping at plateaus\nNot the actual two-region wall heat')
    for ax in axs.flat:
        ax.grid(alpha=.2)
    for ax in [axs[0,0],axs[0,1],axs[1,0]]:
        ax.set_xlabel('Time (s)'); ax.legend(fontsize=7)
    fig.suptitle('IHX original-curve audit: wall storage closes, but the single-wall mapping does not\nNo new simulation, parameter fitting, curve shifts or formal-file changes',fontsize=11)
    fig.savefig(output/'ihx_wall_storage_and_paper.png',dpi=170)
    plt.close(fig)
    print(json.dumps({'output':str(output),'cases':metrics,'paper_plateau':plateau},indent=2))


if __name__ == '__main__':
    main()
