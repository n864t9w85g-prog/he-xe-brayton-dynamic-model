#!/usr/bin/env python3
"""Audit the unchanged, warm steady NaK loop; do not modify model equations."""
import argparse
import csv
import json
from pathlib import Path
from verify_precooler_boundary_diagnostic import nak_cp, nak_h, semantic_inventory
from verify_tac_power_sources import ROOT, sha, near, property_fd


def main():
    parser=argparse.ArgumentParser();parser.add_argument('directory',type=Path)
    parser.add_argument('--verify-only',action='store_true');args=parser.parse_args()
    dest=args.directory.resolve();assert dest.is_relative_to(ROOT/'tmp')
    source=ROOT/'tmp/steady53_curves_20260828/source_f8bcd83/final_steady_24a.slx'
    assert sha(source)=='0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391'
    rad=semantic_inventory(source,'rediator');pre=semantic_inventory(source,'precooler')
    blocks=rad['blocks'];edges=rad['edges']
    assert ['T_hi#out:1','MATLAB Function#in:1'] in edges
    assert ['MATLAB Function#out:1','m*Cp,h#in:1'] in edges
    assert ['m_hi#out:1','m*Cp,h#in:2'] in edges
    assert '1.061 - 3.694e-4.*T + 4.615e-8.*T.^2 + 1.509e-10.*T.^3' in rad['scripts']['MATLAB Function']
    assert blocks['Tho'][1]['Expr']=='((u(2)-0.8)*u(3)+u(1))/(u(2)+0.2)'
    for name,value in [('Constant2','1113'),('Constant3','5744'),('Constant5','9.755')]:
        assert blocks['Subsystem/'+name][1]['Value']==value
    assert blocks['A1'][1].get('Gain','1')=='1'
    reference=ROOT/'tmp/pressure_closure_4FKFZS/reference_14000';raw=[]
    def last(name):
        path=reference/(name+'.csv')
        with path.open() as f:rows=list(csv.DictReader(f))
        assert float(rows[-1]['time_s'])==14000
        raw.append({'path':str(path),'sha256':sha(path)})
        return float(rows[-1]['value'])
    inlet=last('cooler_cold_outlet_T');outlet=last('cooler_cold_inlet_T');wall=last('state_040')
    hot_in=last('recuperator_hot_outlet_T');mh=last('hexe_mdot_recup_hot')
    pressure=last('recuperator_hot_outlet_P')
    x=[[last(f'state_{k:03d}') for k in range(start,start+5)] for start in (12,17)]
    mc=6.95 # source root SID3130, separately verified in local boundary audit
    qh=[];qc=[];cold_advection=[]
    for i in range(2):
        pfx=f'precooler_{i+1}/'
        value=lambda key:float(pre['blocks'][pfx+key][1]['Value'])
        qh.append(value('h_h')*value('A_region')*(x[i][2]-x[i][4]))
        qc.append(value('h_c')*value('A_region2')*(x[i][4]-x[i][0]))
        cold_in=x[1][1] if i==0 else outlet
        cold_advection.append(mc*nak_cp(x[i][0])*(x[i][1]-cold_in))
        hin=hot_in if i==0 else x[0][3]
        near(mh*property_fd(x[i][2],pressure-9000*i)[0]*(hin-x[i][3]),qh[i],.1,'hot steady')
        near(qh[i],qc[i],.1,'wall steady')
        near(qc[i],cold_advection[i],.1,'cold steady')
    rad_fluid=mc*nak_cp(inlet)*(inlet-outlet)
    rad_conv=1113*9.755*(.8*inlet+.2*outlet-wall)
    rad_emitted=1113*.9*5.67e-8*(wall**4-225**4)
    near(rad_fluid,rad_conv,1e-6,'radiator algebraic balance')
    near(rad_conv,rad_emitted,.1,'radiator late wall balance')
    common=mc*(nak_h(inlet)-nak_h(outlet))
    paper_dh=nak_h(609.58)-nak_h(360.10)
    result={'scope':'Warm original saved model; instantaneous 14000 s endpoint; no candidate run or fix',
        'source_sha256':sha(source),'verifier_sha256':sha(__file__),
        'helper_sha256':sha(ROOT/'tests/verify_precooler_boundary_diagnostic.py'),
        'raw_sources':raw,'NaK_inlet_to_radiator_K':inlet,'NaK_outlet_from_radiator_K':outlet,
        'radiator_wall_K':wall,'radiator_cp_inlet_J_kgK':nak_cp(inlet),
        'precooler_cold_region_cp_J_kgK':[nak_cp(s[0]) for s in x],
        'precooler_hot_heat_W':sum(qh),'precooler_cold_heat_W':sum(qc),
        'precooler_cold_advection_W':sum(cold_advection),'radiator_fluid_heat_W':rad_fluid,
        'radiator_convection_W':rad_conv,'radiator_emission_W':rad_emitted,
        'common_NaK_enthalpy_rate_W':common,
        'precooler_minus_radiator_heat_W':sum(qc)-rad_emitted,
        'precooler_minus_common_enthalpy_W':sum(qc)-common,
        'radiator_minus_common_enthalpy_W':rad_fluid-common,
        'paper_NaK_endpoints_active_cp_at_project_flow_Q_W':mc*paper_dh,
        'paper_Q_minus_that_rate_W':1622000-mc*paper_dh,
        'paper_Q_endpoints_required_cpbar_at_project_flow_J_kgK':1622000/(mc*(609.58-360.10)),
        'active_cpbar_between_paper_endpoints_J_kgK':paper_dh/(609.58-360.10),
        'paper_Q_required_flow_with_active_cp_kg_s':1622000/paper_dh,
        'flow_status':'6.95 kg/s project boundary, not verified thesis direct; derived 7.134 is NOT a proposed correction',
        'status':'PASS diagnostic identities; physical energy mismatch retained',
        'formal_mutations':False,'paper_acceptance':False}
    output=dest/'nak_loop_energy.json'
    if args.verify_only:assert json.loads(output.read_text())==result
    else:
        with output.open('x') as f:json.dump(result,f,ensure_ascii=False,indent=2);f.write('\n')
    print(json.dumps({k:v for k,v in result.items() if k!='raw_sources'},ensure_ascii=False,indent=2))


if __name__=='__main__':main()
