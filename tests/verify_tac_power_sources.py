#!/usr/bin/env python3
"""Independent read-only TAC audit; never loads/simulates/writes an SLX.

Raw virial B/C -> complex-step first derivatives -> EOS bisection -> h/u
five-point finite differences. This deliberately does not copy the MATLAB
analytic cp/cv derivatives or Newton density solve. No Scheme A or H1b.
"""
import argparse
import bisect
import cmath
import csv
import hashlib
import json
import math
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
R = 8.314
X = .7172
Y = 1 - X
M = X * .0040026 + Y * .131293


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def near(a, b, tol, label):
    assert math.isfinite(a) and abs(a - b) <= tol, (label, a, b, tol)
    return abs(a - b)


def real_cuberoot_extension(z):
    sign = 1 if z.real > 0 else -1
    assert abs(z.real) > 1e-50
    return sign * (sign * z) ** (1 / 3)


def virial(t):
    vh, vx = .0040026 / 69.64, .131293 / 1099.7
    v12 = (vh ** (1 / 3) + vx ** (1 / 3)) ** 3 / 8
    th, tx, t12 = t / 5.19, t / 289.6, t / math.sqrt(5.19 * 289.6)
    b11 = (8.4 - .0018 * t + 115 / cmath.sqrt(t) - 835 / t) * 1e-6

    def bpart(theta, v, slope):
        return v * (-102.6 + (102.732 - slope * theta - .44 / theta ** 1.22)
                    * cmath.tanh(4.5 * cmath.sqrt(theta)))

    b = X * X * b11 + 2 * X * Y * bpart(t12, v12, .001) + Y * Y * bpart(tx, vx, .01)

    def cpart(theta, v):
        return v * v * (.0757 + (-.0862 - 3.6e-5 * theta + .0237 / theta ** .059)
                        * cmath.tanh(.84 * theta))

    ch, cx = cpart(th, vh), cpart(tx, vx)
    c = (X ** 3 * ch + 3 * X * X * Y * real_cuberoot_extension(ch * ch * cx)
         + 3 * X * Y * Y * real_cuberoot_extension(ch * cx * cx) + Y ** 3 * cx)
    return b, c


def coefficients(t):
    b, c = virial(complex(t, 1e-20))
    return b.real, c.real, b.imag / 1e-20, c.imag / 1e-20


def molar_density(t, p):
    b, c, _, _ = coefficients(t)
    target = p / (R * t)
    lo, hi = .5 * target, 1.5 * target

    def f(n):
        return n + b * n * n + c * n ** 3 - target

    assert f(lo) < 0 < f(hi)
    # Establish monotonicity within this gas-root bracket.
    assert min(1 + 2 * b * n + 3 * c * n * n for n in (lo, hi)) > 0
    for _ in range(70):
        mid = (lo + hi) / 2
        if f(mid) > 0:
            hi = mid
        else:
            lo = mid
    n = (lo + hi) / 2
    assert n > .9 * target  # Official density floor is inactive here.
    near(f(n), 0, 1e-10, 'EOS residual')
    return n


def enthalpy(t, p):
    b, c, db, dc = coefficients(t)
    n = molar_density(t, p)
    return R * t * (2.5 + (b - t * db) * n + (c - .5 * t * dc) * n * n) / M


def internal_energy(t, n):
    _, _, db, dc = coefficients(t)
    return (1.5 * R * t - R * t * t * (db * n + .5 * dc * n * n)) / M


def deriv5(f, t, h):
    return (f(t - 2 * h) - 8 * f(t - h) + 8 * f(t + h) - f(t + 2 * h)) / (12 * h)


def property_fd(t, p, step=.02):
    assert 100 < t - 2 * step < t + 2 * step < 2000
    assert abs(t - 992.3824092088217) > 2 * step
    n = molar_density(t, p)
    cp = deriv5(lambda v: enthalpy(v, p), t, step)
    cv = deriv5(lambda v: internal_energy(v, n), t, step)
    assert cp > cv > 0
    return cp, cp / cv, n * M


def machine(a, step=.02):
    t, p, ratio, eta, flow = [a[k] for k in ('Tin_K', 'Pin_Pa', 'ratio', 'eta', 'mdot_kg_s')]
    compressor = a.get('kind', a.get('name', '')).startswith('compressor')
    cp1, gamma, _ = property_fd(t, p, step)
    tis = t * ratio ** ((1 if compressor else -1) * (1 - 1 / gamma))
    pout = p * ratio if compressor else p / ratio
    cp2 = property_fd(tis, pout, step)[0]
    tout = t + cp2 * (tis - t) / (cp1 * eta) if compressor else t - eta * cp2 * (t - tis) / cp1
    return {'Tout_K': tout, 'W_W': flow * cp1 * abs(tout - t), 'Tis_K': tis}


def bilinear(xs, ys, table, x, y):
    assert xs[0] <= x <= xs[-1] and ys[0] <= y <= ys[-1]
    i = min(max(0, bisect.bisect_right(xs, x) - 1), len(xs) - 2)
    j = min(max(0, bisect.bisect_right(ys, y) - 1), len(ys) - 2)
    a, b = (x - xs[i]) / (xs[i+1] - xs[i]), (y - ys[j]) / (ys[j+1] - ys[j])
    return sum(table[i+di][j+dj] * ([1-a, a][di]) * ([1-b, b][dj])
               for di in range(2) for dj in range(2))


def slx_evidence(path):
    systems = {}
    with zipfile.ZipFile(path) as z:
        for sid in ('3804', '3811', '3882', '3942'):
            entry = f'simulink/systems/system_{sid}.xml'
            root = ET.fromstring(z.read(entry))
            blocks = {b.get('SID'): {'name': b.get('Name'), 'type': b.get('BlockType'),
                      'parameters': {p.get('Name'): p.text for p in b.findall('P')}}
                      for b in root.findall('Block')}
            edges = []
            for line in root.findall('Line'):
                src = line.find("P[@Name='Src']").text
                edges.extend([src, p.text] for p in line.findall(".//P[@Name='Dst']"))
            systems[sid] = {'entry': entry, 'blocks': blocks, 'edges': edges,
                            'xml_sha256': hashlib.sha256(z.read(entry)).hexdigest()}
        chart_scripts = {}
        for entry in z.namelist():
            if entry.startswith('simulink/stateflow/chart_') and entry.endswith('.xml'):
                root = ET.fromstring(z.read(entry))
                for script in root.findall(".//P[@Name='script']"):
                    txt = script.text or ''
                    if any(token in txt for token in ('T5s = T_in', 'T2s = T1', 'cp2*', 'cp2 *')):
                        chart_scripts[entry] = txt
    c, t = systems['3811'], systems['3882']
    for system, product, sum_sid, cp_sid, mdot_sid, out_sid in (
        (c, '3868', '3869', '3838', '3840', '3871'),
        (t, '3957', '3961', '3914', '3916', '3965')):
        assert system['blocks'][product]['parameters']['Inputs'] == '3'
        assert system['blocks'][sum_sid]['parameters']['Inputs'] == '|+-'
        assert system['blocks'][cp_sid]['parameters']['GotoTag'] == 'cp1'
        for src, dst in ((sum_sid+'#out:1', product+'#in:1'),
                         (cp_sid+'#out:1', product+'#in:2'),
                         (mdot_sid+'#out:1', product+'#in:3'),
                         (product+'#out:1', out_sid+'#in:1')):
            assert [src, dst] in system['edges']
    for sid, value in (('3847','1/55090'), ('3848','1/55090'), ('3849','1/12.04'), ('3850','1/12.04')):
        assert c['blocks'][sid]['parameters']['Gain'] == value
    for sid, table in (('3816','ETAT_table'), ('3817','PR_table')):
        params = c['blocks'][sid]['parameters']
        assert params['Table'] == table
        assert params['BreakpointsForDimension1'] == 'speed_bp'
        assert params['BreakpointsForDimension2'] == 'm_ratio_bp'
    return {'systems': systems, 'selected_chart_scripts': chart_scripts,
            'scope': 'Read-only XML inventory and power-input assertions; no SLX rewrite.'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    dest = args.directory.resolve()
    assert dest.is_relative_to(ROOT / 'tmp')
    summary_path = dest / 'summary.json'
    s = json.loads(summary_path.read_text())
    for row in s['source_hashes']:
        assert sha(row['path']) == row['sha256'], row['path']
    with (dest / 'protected_after.csv').open() as f:
        protected = list(csv.DictReader(f))
    assert len(protected) == 34
    for row in protected:
        assert sha(row['paths']) == row['hashes'], row['paths']
    slx = next(r['path'] for r in s['source_hashes'] if r['path'].endswith('.slx'))
    xml = slx_evidence(slx)
    maps, look = s['tables'], s['lookup']
    c, f, e = maps['compressor'], maps['turbine_flow'], maps['turbine_efficiency']
    near(bilinear(c['speed_bp'],c['m_ratio_bp'],c['PR_table'],look['speed_ratio'],look['flow_ratio']),look['compressor_r'],1e-12,'compressor ratio map')
    near(bilinear(c['speed_bp'],c['m_ratio_bp'],c['ETAT_table'],look['speed_ratio'],look['flow_ratio']),look['compressor_eta'],1e-12,'compressor eta map')
    near(bilinear(f['bp_er'],f['bp_speed'],f['table_mf'],look['turbine_expansion_ratio'],55090),look['turbine_mass_flow_from_map'],1e-12,'turbine flow map')
    near(bilinear(e['bp_mf'],e['bp_speed'],e['table_eff'],look['turbine_mass_flow_from_map'],55090),look['turbine_eta'],1e-12,'turbine eta map')
    r = look['compressor_r']
    near(r*(1-.005158-.002579)/(1+r*.011605),look['turbine_expansion_ratio'],1e-12,'pressure drop er')
    errors = []
    for a in [s['compressor'],s['turbine']] + s['single_factor_cases']:
        x, y = machine(a), machine(a, .01)
        errors.append({'case': a.get('name',a.get('kind')), 'power_error_W':
                       near(x['W_W'],a.get('power_W',a.get('W_W')),.02,'machine power'),
                       'Tout_error_K': near(x['Tout_K'],a['Tout_K'],1e-5,'Tout'),
                       'step_halving_power_change_W': near(x['W_W'],y['W_W'],.02,'step halving')})
    with (dest / 'cp_path_samples.csv').open() as f:
        samples = [{k:float(v) for k,v in row.items()} for row in csv.DictReader(f)]
    assert len(samples) == 4004
    sample_errors = {'cp_J_kgK':0.,'gamma':0.,'rho_kg_m3':0.}
    for row in samples:
        cp, gamma, rho = property_fd(row['T_K'],row['P_Pa'])
        for key,val,tol in (('cp_J_kgK',cp,1e-4),('gamma',gamma,1e-6),('rho_kg_m3',rho,1e-9)):
            sample_errors[key] = max(sample_errors[key],near(val,row[key],tol,key))
    for idx,a in enumerate(s['accounting'],1):
        near(a['actual_to_paper_power_difference_W'],a['ordered_deltaT_contribution_W']+
             a['ordered_cp_contribution_W']+a['remaining_power_gap_at_paper_endpoints_W'],1e-6,'accounting identity')
        for branch,field in ((1,'actual_path_cpbar'),(2,'paper_path_cpbar')):
            rows=[x for x in samples if x['machine_index']==idx and x['branch_actual_or_paper']==branch]
            ys=[row['cp_J_kgK'] for row in rows]
            avg=(ys[0]+ys[-1]+4*sum(ys[1:-1:2])+2*sum(ys[2:-1:2]))/3000
            near(avg,a[field]['cpbar'],1e-8,'independent Simpson 1000 vs quadgk')
    prior_path=ROOT/'tmp/steady53_power_source_NMBBXi/power_definition_audit.json'
    assert sha(prior_path)=='fa836c95f5e2c8d78aaa61b26b7ef2bebed81e137bb4dd38a4f0cd27bcdb3643'
    prior=json.loads(prior_path.read_text())['saved_baseline_postprocessing']
    time_diff={kind:s[kind]['W_W']-1000*prior[kind+'_final_kW'] for kind in ('compressor','turbine')}
    active=ROOT.parent/'不接入转子稳态模型_副本'
    head=subprocess.check_output(['git','-C',str(active),'rev-parse','HEAD'],text=True).strip()
    assert head=='f8bcd833e816eb681982b7dd04364e4b856948e3'
    archive=subprocess.check_output(['git','-C',str(ROOT),'rev-parse','archive/pre-restart-20260824^{}'],text=True).strip()
    assert archive=='8f625c268c35a95c18a626305c1aa6a79ae2ace7'
    for repo in (ROOT,active):
        assert not subprocess.check_output(['git','-C',str(repo),'diff','HEAD','--name-only'],text=True).strip()
    result={'status':'PASS','summary_sha256':sha(summary_path),'verifier_sha256':sha(__file__),
            'method':'Raw B/C, complex-step first derivatives, bisection EOS, five-point h/u finite differences; two FD steps; independent bilinear maps and Simpson quadrature.',
            'machine_errors':errors,'property_sample_count':len(samples),'property_max_errors':sample_errors,
            'power_500_minus_14000_W':time_diff,'same_trajectory_claimed':False,
            'protected_count':len(protected),'active_head':head,'archive':archive,
            'model_acceptance_passed':False,'formal_mutations':False,'slx_readonly_evidence':xml}
    output=dest/'independent_verification.json'
    if args.verify_only:
        assert json.loads(output.read_text())==result
    else:
        with output.open('x') as f:
            json.dump(result,f,ensure_ascii=False,indent=2)
            f.write('\n')
    print(json.dumps({k:v for k,v in result.items() if k!='slx_readonly_evidence'},ensure_ascii=False,indent=2))


if __name__=='__main__':
    main()
