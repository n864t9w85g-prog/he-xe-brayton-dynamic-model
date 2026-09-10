"""Independent offline check of the approved Scheme A four-path experiment.

Uses raw B/C coefficients, complex-step first derivatives, bracketed EOS
bisection, and state-function finite differences rather than the MATLAB
candidate's analytic cp/Newton solver. No source or model writes. Creates
only one new verification JSON inside the supplied tmp experiment directory.
"""
import argparse
import cmath
import csv
import hashlib
import json
import math
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('run', type=Path)
run = parser.parse_args().run.resolve()
assert run.is_relative_to(ROOT / 'tmp')
sha = lambda f: hashlib.sha256(Path(f).read_bytes()).hexdigest()
result = json.loads((run / 'summary.json').read_text())
assert 'SCHEME_A_FOUR_PATHS_OFFLINE_COMPLETE' in (run / 'diary.txt').read_text()
for item in result['source_hashes']:
    assert sha(item['path']) == item['sha256'], item['path']
before = list(csv.DictReader((run / 'protected_before.csv').open()))
after = list(csv.DictReader((run / 'protected_after.csv').open()))
assert before == after and len(after) == 34
for item in after:
    assert sha(item['paths']) == item['hashes'], item['paths']

R, x, y = 8.314, .7172, 1-.7172
M = x*.0040026 + y*.131293
vh, vx = .0040026/69.64, .131293/1099.7
v12 = (vh**(1/3)+vx**(1/3))**3/8


def raw_coefficients(t):
    """Existing candidate's raw second/third virials, without its derivatives."""
    b11 = (8.4-.0018*t+115/cmath.sqrt(t)-835/t)*1e-6
    def other_b(theta, v, slope):
        return v*(-102.6+(102.732-slope*theta-.44/theta**1.22)
                  * cmath.tanh(4.5*cmath.sqrt(theta)))
    b22 = other_b(t/289.6, vx, .01)
    b12 = other_b(t/math.sqrt(5.19*289.6), v12, .001)
    th = t/289.6
    c222 = vx**2*(.0757+(-.0862-3.6e-5*th+.0237/th**.059)*cmath.tanh(.84*th))
    return x*x*b11+2*x*y*b12+y*y*b22, y**3*c222


def coefficients(t):
    b, c = raw_coefficients(t)
    bc, cc = raw_coefficients(complex(t, 1e-16))
    return b.real, c.real, bc.imag/1e-16, cc.imag/1e-16


def state(t, p):
    b, c, db, dc = coefficients(t)
    lo, hi = 0., 2*p/(R*t)
    polynomial = lambda n: c*n**3+b*n*n+n-p/(R*t)
    assert polynomial(lo) < 0 < polynomial(hi)
    for _ in range(70):
        n = (lo+hi)/2
        if polynomial(n) > 0:
            hi = n
        else:
            lo = n
    n = (lo+hi)/2
    assert n > .9*p/(R*t) and 1+2*b*n+3*c*n*n > 0
    h = (2.5*R*t+R*t*((b-t*db)*n+(c-.5*t*dc)*n*n))/M
    nt = -((n+b*n*n+c*n**3)/t+db*n*n+dc*n**3)/(1+2*b*n+3*c*n*n)
    hp = 1/(M*n)+t*nt/(M*n*n)
    return h, n*M, hp, n


def derivative5(fun, value, step):
    return (-fun(value+2*step)+8*fun(value+step)-8*fun(value-step)
            + fun(value-2*step))/(12*step)


def cp_fd(t, p, step=.1):
    return derivative5(lambda temp: state(temp, p)[0], t, step)


def cv_fd(t, n, step=.1):
    def u(temp):
        _, _, db, dc = coefficients(temp)
        return (1.5*R*temp-R*temp**2*(db*n+.5*dc*n*n))/M
    return derivative5(u, t, step)


def simpson(fun, a, b, count):
    if a == b:
        return 0.
    spacing = (b-a)/count
    vals = [fun(a+k*spacing) for k in range(count+1)]
    return spacing/3*(vals[0]+vals[-1]+4*sum(vals[1:-1:2])+2*sum(vals[2:-1:2]))


samples = [{k: float(v) for k, v in row.items()}
           for row in csv.DictReader((run / 'domain_samples.csv').open())]
assert len(samples) == result['sample_count'] == 7616
for row in samples:
    assert all(math.isfinite(v) for v in row.values())
    assert min(row['cp_J_kgK'], row['cv_J_kgK'], row['rho_kg_m3'], row['dPdrho']) > 0
    assert row['gamma'] > 1 and row['stable_positive_root_count'] == 1
    assert row['density_floor_active'] == row['removed_terms_max_abs'] == 0
    assert row['relative_EOS_residual'] < 1e-12

# Independently recompute representative points on every path and both sides
# of the former singularity, rather than trusting a same-implementation audit.
selected = samples[::97] + [samples[-1]]
t0 = 992.3824092088217
selected += [r for r in samples if abs(r['T_K']-t0) <= .00101]
checks = []
for row in selected:
    t, p = row['T_K'], row['P_Pa']
    h, rho, hp, n = state(t, p)
    cp1, cp2 = cp_fd(t,p,.1), cp_fd(t,p,.2)
    cv1, cv2 = cv_fd(t,n,.1), cv_fd(t,n,.2)
    pressure_fd = derivative5(lambda pressure: state(t,pressure)[0],p,100.)
    assert abs(h-row['h_J_kg']) < 1e-6
    assert abs(rho-row['rho_kg_m3']) < 1e-10
    assert max(abs(cp1-cp2),abs(cp1-row['cp_J_kgK'])) < 5e-4
    assert max(abs(cv1-cv2),abs(cv1-row['cv_J_kgK'])) < 5e-4
    assert abs(cp1/cv1-row['gamma']) < 5e-6
    assert abs(hp-pressure_fd) < 1e-8
    checks.append(dict(T_K=t,P_Pa=p,cp_finite_difference=cp1,cv_finite_difference=cv1,
        cp_error=cp1-row['cp_J_kgK'],cv_error=cv1-row['cv_J_kgK'],
        gamma_error=cp1/cv1-row['gamma'],h_error=h-row['h_J_kg'],
        rho_error=rho-row['rho_kg_m3'],pressure_identity_error=hp-pressure_fd))

expected = [(1100.91,1522.96,1543000.,1539000.,2647180.),
            (1162.,663.63,676000.,676000.,3130580.),
            (601.90,1100.91,1551000.,1543000.,3130580.),
            (663.63,405.16,676000.,658000.,1622000.)]
path_checks = []
for path, inputs in zip(result['paths'],expected,strict=True):
    ti,to,pi,po,duty = inputs
    assert tuple(path[k] for k in ('Tin_K','Tout_K','Pin_Pa','Pout_Pa','table_duty_W')) == inputs
    dh = state(to,po)[0]-state(ti,pi)[0]
    dht = simpson(lambda t: cp_fd(t,pi),ti,to,400)
    dhp = simpson(lambda p: state(to,p)[2],pi,po,200)
    dht_coarse = simpson(lambda t: cp_fd(t,pi),ti,to,200)
    assert abs(dh-path['dH_total_J_kg']) < 1e-3
    assert abs(dht+dhp-dh) < 1e-3 and abs(dht-dht_coarse) < 1e-3
    flow = duty/abs(dh)
    assert abs(flow-path['inferred_flow_kg_s']) < 1e-7
    assert abs(path['duty_at_project_flow_W']-11.97*abs(dh)) < .02
    path_checks.append(dict(name=path['name'],endpoint_dH_J_kg=dh,
        cp_fd_simpson_T_200=dht_coarse,cp_fd_simpson_T_400=dht,
        independent_pressure_integral=dhp,integral_minus_endpoint_J_kg=dht+dhp-dh,
        independent_inferred_flow_kg_s=flow))

flows = [p['independent_inferred_flow_kg_s'] for p in path_checks]
spread = 100*(max(flows)-min(flows))/(sum(flows)/4)
assert abs(spread-result['flow_consistency']['range_over_mean_percent']) < 1e-7
hot, cold = (abs(path_checks[i]['endpoint_dH_J_kg']) for i in (1,2))
recup = dict(hot_delta_h_magnitude_J_kg=hot,cold_delta_h_magnitude_J_kg=cold,
             per_mass_gap_J_kg=cold-hot,
             heat_gap_at_unchanged_project_flow_W=11.97*(cold-hot),
             note='Conditional on this candidate and fixed table endpoints, not a fitted correction or proof the author used these properties.')
model = ROOT.parent/'不接入转子稳态模型_副本/final_steady_24a.slx'
head = subprocess.check_output(['git','rev-parse','HEAD'],cwd=model.parent,text=True).strip()
archive = subprocess.check_output(['git','rev-parse','archive/pre-restart-20260824^{}'],cwd=ROOT,text=True).strip()
assert head == 'f8bcd833e816eb681982b7dd04364e4b856948e3'
assert archive == '8f625c268c35a95c18a626305c1aa6a79ae2ace7'
assert result['no_SLX_loaded'] and result['no_SLX_simulated']
assert not result['model_acceptance_passed'] and not result['candidate_promoted']
assert not result['flow_consistency']['flow_applied']
evidence = dict(protected_files_verified=len(after),active_head=head,archive=archive,
    sample_rows_verified=len(samples),independent_state_check_count=len(checks),
    max_cp_fd_error=max(abs(c['cp_error']) for c in checks),
    max_cv_fd_error=max(abs(c['cv_error']) for c in checks),
    newton_delta_stop_false_count=sum(r['newton_delta_stop_met']==0 for r in samples),
    max_relative_EOS_residual=max(r['relative_EOS_residual'] for r in samples),
    state_checks=checks,path_checks=path_checks,flow_spread_percent=spread,
    recuperator_energy_mismatch=recup,
    source_hashes={str(p):sha(p) for p in [Path(__file__),run/'summary.json',
        run/'domain_samples.csv',run/'four_paths.csv',run/'diary.txt']},
    conclusion='All four candidate paths are finite and sampled-domain positive; they do NOT imply one exactly common mass flow. No model promotion.',
    limitations=['No SLX or cold-start simulation.','Domain sampling is not a global or experimental validity proof.',
                 'Recuperator hot/cold paths share the same reported duty, so these are not four independent experiments.',
                 'Candidate-inferred flow is not paper-direct and has not been applied.',
                 'Lithium-side enthalpy mismatch is untouched.'])
with (run/'independent_verification.json').open('x') as f:
    json.dump(evidence,f,ensure_ascii=False,indent=2);f.write('\n')
print(json.dumps({k:v for k,v in evidence.items() if k not in ('state_checks','source_hashes')},ensure_ascii=False,indent=2))
print('SCHEME_A_FOUR_PATHS_INDEPENDENT_CHECKS_PASS; PROTECTED=34; NO_MODEL_PROMOTION')
