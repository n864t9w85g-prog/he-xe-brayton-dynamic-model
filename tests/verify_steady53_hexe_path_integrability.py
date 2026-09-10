"""Independent, read-only-source audit of the official-cp path diagnosis.

Writes only a new evidence file in the supplied tmp run directory. No solver
or model repair. Negative-cp observations are preserved, never clipped.
"""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('run', type=Path)
args = p.parse_args()
run = args.run.resolve()
assert run.is_relative_to(ROOT / 'tmp')
assert 'HEXE_PATH_INTEGRABILITY_AUDIT_COMPLETE' in (run / 'diary.txt').read_text()
sha = lambda f: hashlib.sha256(Path(f).read_bytes()).hexdigest()
result = json.loads((run / 'summary.json').read_text())
for item in result['source_hashes']:
    assert sha(item['path']) == item['sha256'], item['path']
protected = list(csv.DictReader((run / 'protected_after.csv').open()))
for item in protected:
    assert sha(item['paths']) == item['hashes'], item['paths']
assert len(protected) == 34

def component_c(T, tc, volume):
    theta = T / tc
    return volume**2 * (.0757 + (-.0862-3.6e-5*theta+.0237/theta**.059)*math.tanh(.84*theta))

vh, vx = .0040026/69.64, .131293/1099.7
lo, hi = 990., 995.
assert component_c(lo, 5.19, vh)>0>component_c(hi, 5.19, vh)
for _ in range(60):
    mid = (lo+hi)/2
    if component_c(mid, 5.19, vh)>0:
        lo=mid
    else:
        hi=mid
t0=(lo+hi)/2
assert abs(t0-result['root_T_K'])<1e-8
th=t0/5.19
u=-.0862-3.6e-5*th+.0237/th**.059
a=vh**2/5.19*((-3.6e-5-.0013983/th**1.059)*math.tanh(.84*th)+u*.84*(1-math.tanh(.84*th)**2))
b=component_c(t0,289.6,vx)
assert a<0 and b>0
# Independent 5-point finite-difference check at a regular C111 zero.
h=.05
c=lambda t: component_c(t,5.19,vh)
afd=(-c(t0+2*h)+8*c(t0+h)-8*c(t0-h)+c(t0-2*h))/(12*h)
assert abs((afd-a)/a)<1e-7
x,y,R=.7172,.2828,8.314
M=x*.0040026+y*.131293
v12=(vh**(1/3)+vx**(1/3))**3/8
B11=(8.4-.0018*t0+115/math.sqrt(t0)-835/t0)*1e-6
def B_other(theta, volume, slope):
    return volume*(-102.6+(102.732-slope*theta-.44/theta**1.22)*math.tanh(4.5*math.sqrt(theta)))
B=x*x*B11+2*x*y*B_other(t0/math.sqrt(5.19*289.6),v12,.001)+y*y*B_other(t0/289.6,vx,.01)
C=y**3*b
samples=[{k:float(v) for k,v in row.items()} for row in csv.DictReader((run/'pole_samples.csv').open())]
assert len(samples)==24
checks=[]
for pressure in (676000.,1551000.):
    n=pressure/(R*t0)
    for _ in range(30):
        n-=(C*n**3+B*n*n+n-pressure/(R*t0))/(3*C*n*n+2*B*n+1)
    assert n>0 and 1+2*B*n+3*C*n*n>0
    assert n>=.9*pressure/(R*t0)  # production density floor is inactive
    # Leading C122 = k*sign(delta)*abs(delta)^(1/3), k<0.
    k=-abs(a*b*b)**(1/3)
    # cp leading term: A*sign(delta)*abs(delta)^(-5/3).
    A=R*t0*t0*n*n/M*x*y*y*k/3
    selected=[r for r in samples if r['P_Pa']==pressure and r['offset_K']==1e-6]
    scaled=[r['cp_J_kgK']*r['side']*r['offset_K']**(5/3) for r in selected]
    assert A<0 and len(selected)==2
    assert max(abs(s/A-1) for s in scaled)<.005
    assert any(r['cp_J_kgK']<0 for r in selected)
    checks.append(dict(P_Pa=pressure,rho_molar_at_zero=n,leading_A=A,
                       scaled_sample_values=scaled,relative_errors=[abs(s/A-1) for s in scaled]))
trunc=[{k:float(v) for k,v in row.items()} for row in csv.DictReader((run/'one_sided_integrals.csv').open())]
assert len(trunc)==16
for r in trunc:
    assert r['crosscheck_abs_J_kg']<max(.01,abs(r['integral_cp_J_kg'])*2e-4)
for pressure in (676000.,1551000.):
    for side in (-1.,1.):
        rows=sorted((r for r in trunc if r['P_Pa']==pressure and r['side']==side),key=lambda r:r['cutoff_K'],reverse=True)
        assert len(rows)==4 and abs(rows[-1]['integral_cp_J_kg'])>3*abs(rows[-2]['integral_cp_J_kg'])
for row in result['paths']:
    crosses=min(row['Tin_K'],row['Tout_K'])<t0<max(row['Tin_K'],row['Tout_K'])
    assert crosses==row['crosses_C111_zero']
    if crosses:
        assert row['inferred_flow_kg_s'] is None and not row['cpbar_valid']
    else:
        assert row['cpbar_valid'] and 12.06<row['inferred_flow_kg_s']<12.08

model=ROOT.parent/'不接入转子稳态模型_副本/final_steady_24a.slx'
consumers=[]
with zipfile.ZipFile(model) as z:
    for filename in z.namelist():
        if not filename.startswith('simulink/stateflow/chart_'): continue
        chart=ET.fromstring(z.read(filename))
        name=chart.find("P[@Name='name']").text
        if not name.startswith('recuperator/'): continue
        script=next(n.text for n in chart.iter('P') if n.get('Name')=='script')
        assert 'HeXe_property_simulink(T_in, P_in)' in script
        consumers.append(dict(path='final_steady_24a/'+name,xml=filename,
                              script=script,script_sha256=hashlib.sha256(script.encode()).hexdigest()))
assert len(consumers)==4
archive=subprocess.check_output(['git','rev-parse','archive/pre-restart-20260824^{}'],cwd=ROOT,text=True).strip()
assert archive=='8f625c268c35a95c18a626305c1aa6a79ae2ace7'
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=model.parent,text=True).strip()
assert head=='f8bcd833e816eb681982b7dd04364e4b856948e3'
source_files=[Path(__file__),run/'summary.json',run/'pole_samples.csv',run/'one_sided_integrals.csv',
              run/'wolfram_symbolic_check.json',ROOT/'tmp/hexe_source_7Iqt3c/thesis-034.png',
              ROOT/'tmp/ihx_geometry_source_wotvtW/assumptions-092.png',
              ROOT/'tmp/steady53_recheck_20260827/paper-104.png']
evidence=dict(root_T_K=t0,C111_derivative=a,C111_derivative_finite_difference=afd,C222_at_zero=b,
    local_asymptotic_checks=checks,official_recuperator_consumers=consumers,
    source_hashes={str(f):sha(f) for f in source_files},protected_files_verified=len(protected),
    active_head=head,archive=archive,scheme_A_evaluated=False,model_acceptance_passed=False,
    conclusion='Under the active equations, cp has a nonzero sign(delta)*abs(delta)^(-5/3) leading term. Ordinary one-sided enthalpy integrals diverge across the root.',
    limitations=['No new SLX trajectory or cold-start crossing was measured.',
                 'No new source-backed mass flow is identified or applied.',
                 'Wolfram raw symbolic messages are preserved, not represented as a warning-free run.',
                 'This is not proof of what the thesis author actually executed.'])
with (run/'independent_verification.json').open('x') as f:
    json.dump(evidence,f,ensure_ascii=False,indent=2);f.write('\n')
print(json.dumps(dict(root=t0,a=a,b=b,asymptotic=checks),indent=2))
print('HEXE_PATH_SINGULARITY_INDEPENDENT_CHECKS_PASS; PROTECTED=34; NO_MODEL_PROMOTION')
