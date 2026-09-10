"""Independent algebra/history checks for the scalar IHX audit; no simulation."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
import zipfile
import numpy as np

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('run_directory', type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
run = args.run_directory.resolve()
assert run.is_relative_to(repo/'tmp')
assert 'IHX_SCALAR_AUDIT_COMPLETE_NO_SLX_OR_ODE_RUN' in (run/'diary.txt').read_text()
r = json.loads((run/'audit.json').read_text())
digest = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
li_cp = lambda t: .9615*1000*(104400/t**2-135.1/t+4.180)
li_k = lambda t: 21.42+.05230*t-1.371e-5*t*t
checks = {}
for s in r['source_checks']:
    np.testing.assert_allclose(s['cp_h_J_kgK'],li_cp(s['T_h_mean_K']),rtol=1e-13)
    d = 4*.00651/14.062
    re = 11.97/(.00651/2/.0585)*d/s['mu_c_Pa_s']
    h = .022*re**.8*s['Pr_c']**.43*s['k_c_W_mK']/d
    np.testing.assert_allclose(h,s['h_c_Mikheev_W_m2K'],rtol=1e-13)
    np.testing.assert_allclose(6*li_k(s['T_h_mean_K'])/d,s['h_h_legacy_Nu6_estimate_W_m2K'],rtol=1e-13)

initial = r['consistent_outlet1200_initial_derivatives']
bh = 1.3176*li_cp(1400)
bc = .01838*initial['cp_c_J_kgK']
bw = 325*(636+26*(1200-1173.15)/100)
storage = bh*initial['hot_out_derivative_K_s']/2+bc*initial['cold_out_derivative_K_s']/2+bw*initial['wall_derivative_K_s']
adv = initial['hot_advection_W']+initial['cold_advection_W']
assert abs(storage-adv)<1e-7
checks['initial_combined_energy_residual_W'] = storage-adv

# Independent linear solve instead of the scalar thermal-resistance formula.
ch=4.572*r['source_checks'][1]['cp_h_J_kgK']
cc=11.97*r['source_checks'][1]['cp_c_J_kgK']
hh,hc=10544*14.062,1171.6*14.062
mat=np.array([[ch+hh/2,0,-hh],[0,cc+hc/2,-hc],[hh/2,hc/2,-hh-hc]])
rhs=np.array([(ch-hh/2)*1600,(cc-hc/2)*1100.91,-hh*1600/2-hc*1100.91/2])
solution=np.linalg.solve(mat,rhs)
frozen=r['frozen_property_whole_component_equilibrium']
expected=np.array([frozen['T_ho_K'],frozen['T_co_K'],frozen['T_wall_K']])
np.testing.assert_allclose(solution,expected,rtol=0,atol=1e-9)
checks['independent_frozen_equilibrium_K']=solution.tolist()

# The transfer comparison is ONLY for one region, frozen cp and prescribed
# fixed wall temperature. It is not an equivalence of the coupled IHX.
# Original: B/2*x'=C*(Ti-x)-H/2*(x-w),
#           B/2*y'=C*(x-y)-H/2*(x-w).
# Paper mean: B*y'=(2C-H)*Ti-(2C+H)*y+2H*w, at fixed inlet.
# Hence G_old/G_paper = 1/(1+s*B/(2C)) for the Ti-to-y channel.
transfer=[]
for side,m,mdot,cp,h in [('hot',.6588,4.572,li_cp(1200),10544),
                         ('cold',.00919,11.97,initial['cp_c_J_kgK'],1171.6)]:
    B,C,H=m*cp,mdot*cp,h*7.031
    system=np.array([[-(2*C+H)/B,0],[(2*C-H)/B,-2*C/B]])
    forcing=np.array([2*C/B,0.])
    errors=[]
    for omega in [0,.01,.1,1,10,100,1000]:
        s=1j*omega
        old=np.linalg.solve(s*np.eye(2)-system,forcing)[1]
        paper=(2*C-H)/(B*s+2*C+H)
        predicted=paper/(1+s*B/(2*C))
        errors.append(abs(old-predicted))
    assert max(errors)<1e-12
    transfer.append(dict(side=side,extra_inlet_channel_lag_s=m/(2*mdot),
                         H_over_2C=H/(2*C),fixed_wall_DC_gain=(2*C-H)/(2*C+H),
                         max_transfer_identity_residual=float(max(errors))))
checks['fixed_wall_frozen_cp_transfer']=transfer

active=repo.parent/(repo.name+'_副本')
history=[]
for rev in ['fa90cfc','1960aa1','e613993','f8bcd83']:
    commit=subprocess.check_output(['git','-C',str(active),'rev-parse',rev],text=True).strip()
    data=subprocess.check_output(['git','-C',str(active),'show',rev+':final_steady_24a.slx'])
    found=[]
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for name in archive.namelist():
            if name.startswith('simulink/systems/') and name.endswith('.xml'):
                for b in ET.fromstring(archive.read(name)).findall('Block'):
                    if b.get('Name') in ['h_Li','h_HeXe']:
                        value=next(p.text for p in b.findall('P') if p.get('Name')=='Value')
                        assert value == {'h_Li':'10544','h_HeXe':'1171.6'}[b.get('Name')]
                        found.append(dict(xml=name,SID=b.get('SID'),name=b.get('Name'),value=value))
    assert len(found)==4
    history.append(dict(commit=commit,slx_sha256=hashlib.sha256(data).hexdigest(),constants=found))

paths=[run/'audit.json',repo/'tests/audit_ihx_equation_origin.m',Path(__file__),
       active/'tmp/steady53/h890/table51_consistency.m',active/'pmtf685.pdf',
       repo/'空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf']
result=dict(checks=checks,constant_history=history,input_sha256={str(p):digest(p) for p in paths},
            scope='Independent scalar/matrix/history checks only; not an ODE/SLX run or thesis acceptance.',
            transfer_limit='Frozen-cp prescribed-wall inlet-to-outlet channel only; not a full coupled-system time constant.')
target=run/'independent_verification.json'
assert not target.exists(), 'Refuse to overwrite existing evidence'
target.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(checks,indent=2))
print('INDEPENDENT_IHX_EQUATION_AND_HISTORY_CHECKS_PASS')
