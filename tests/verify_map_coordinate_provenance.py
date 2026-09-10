#!/usr/bin/env python3
"""Read-only source reconstruction and independent local-coordinate audit.

Writes diagnostics only below tmp; historical MATLAB builders are read as
bytes, NEVER executed. Does not rebuild or overwrite any MAT or SLX.
"""
import argparse
import bisect
import csv
import hashlib
import json
import math
from pathlib import Path
import subprocess
from verify_tac_power_sources import ROOT, sha, near, bilinear, machine, property_fd, slx_evidence


def interp(xs, ys, x):
    assert xs[0] <= x <= xs[-1], (xs[0], x, xs[-1])
    i = min(bisect.bisect_right(xs, x)-1, len(xs)-2)
    t = (x-xs[i])/(xs[i+1]-xs[i])
    return (1-t)*ys[i]+t*ys[i+1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    dest = args.directory.resolve()
    assert dest.is_relative_to(ROOT/'tmp')
    audit_path = dest/'map_audit.json'
    a = json.loads(audit_path.read_text())
    c, f = a['compressor_mat'], a['turbine_flow_mat']
    for row in a['source_hashes']:
        assert sha(row['path']) == row['sha256'], row['path']
    with (dest/'protected_after.csv').open() as stream:
        protected = list(csv.DictReader(stream))
    assert len(protected) == 34
    for row in protected:
        assert sha(row['paths']) == row['hashes'], row['paths']
    prov = c['provenance']
    for name in ('source_pdf', 'calibration', 'raw_points'):
        assert sha(ROOT/prov[name+'_file']) == prov[name+'_sha256']
    active = ROOT.parent/'不接入转子稳态模型_副本'
    lineage = {}
    for name in ('build_traceable_compressor_lookup.m', 'tmx2269_similarity_transform.m',
                 'tmx2269_predict_speed_line.m', 'paper54_constants.m'):
        raw = subprocess.check_output(['git','-C',str(active),'show','fa90cfc:'+name])
        lineage[name] = {'commit':'fa90cfc','sha256':hashlib.sha256(raw).hexdigest(),
                         'source_text':raw.decode()}
    assert lineage[prov['implementation_file']]['sha256'] == prov['implementation_sha256']
    transform = lineage['tmx2269_similarity_transform.m']['source_text']
    assert "S.target.mdot_model_kg_s = 12.04;" in transform
    assert "S.target.mdot_category = 'existing model parameter';" in transform
    archived_mats = {}
    for name in ('hexe_compressor_lookup.mat','turbine_table1.mat','turbine_table2.mat'):
        raw = subprocess.check_output(['git','-C',str(active),'show','fa90cfc:'+name])
        archived_mats[name] = hashlib.sha256(raw).hexdigest()
    snapshot = ROOT/'tmp/steady53_curves_20260828/source_f8bcd83'
    for name in ('hexe_compressor_lookup.mat','turbine_table1.mat'):
        assert archived_mats[name] == sha(snapshot/name)
    assert archived_mats['turbine_table2.mat'] == sha(ROOT/'turbine_table2.mat')
    assert a['efficiency_scale_09711_max_abs_residual'] == 0
    old = json.loads((ROOT/'tmp/tac_power_trace_Hnbkhl/summary.json').read_text())
    for key, field in (('compressor',c),('turbine_flow',f)):
        for name, values in old['tables'][key].items():
            if name in field:
                assert values == field[name], name

    # Follow actual input edges, not only the existence/names of Gain blocks.
    slx = slx_evidence(snapshot/'final_steady_24a.slx')
    sys = slx['systems']['3811']; bs = sys['blocks']
    for lookup, gain, source, tag, port, goto, inp in (
        ('3817','3847','3830','N',1,'3852','3812'),
        ('3816','3848','3825','N',1,'3852','3812'),
        ('3817','3849','3824','m_in',2,'3860','3813'),
        ('3816','3850','3835','m_in',2,'3860','3813')):
        assert bs[source]['type'] == 'From' and bs[source]['parameters']['GotoTag'] == tag
        assert bs[goto]['type'] == 'Goto' and bs[goto]['parameters']['GotoTag'] == tag
        assert bs[inp]['type'] == 'Inport'
        for edge in ((source+'#out:1',gain+'#in:1'),(gain+'#out:1',lookup+f'#in:{port}'),
                     (inp+'#out:1',goto+'#in:1')):
            assert list(edge) in sys['edges'], edge
        assert bs[lookup]['parameters']['ExtrapMethod'] == 'Clip'
    assert c['coordinate_definition']['speed'] == '(N/N_design)/sqrt(T_in/T_design)'
    assert c['coordinate_definition']['flow'] == '(mdot/mdot_design)*sqrt(T_in/T_design)/(P_in/P_design)'

    # Reconstruct every active PR/eta table entry from the recorded raw CSV.
    # Target gamma/eta are separately checked below using independent property derivatives.
    with (ROOT/prov['raw_points_file']).open() as stream:
        points = list(csv.DictReader(stream))
    def measured(quantity, speed):
        rows = sorted((float(p['flow_eq_kg_s']),float(p['value'])) for p in points
                      if p['quantity']==quantity and float(p['speed_ratio'])==speed)
        assert rows
        return list(map(list,zip(*rows)))
    prx, pry = measured('pressure_ratio',1.)
    ex, ey = measured('efficiency',1.)
    source_design_flow = json.loads((ROOT/prov['calibration_file']).read_text())['published_design_conditions']['flow_eq_kg_s']
    exponent = (c['gamma_hexe']-1)/c['gamma_hexe']
    source_pr = interp(prx,pry,source_design_flow)
    source_eta = interp(ex,ey,source_design_flow)
    head_scale = (c['PR_design']**exponent-1)/(source_pr**exponent-1)
    loss_scale = (1-c['eta_design'])/(1-source_eta)
    max_pr, max_eta, cells = 0.,0.,0
    for i,speed in enumerate(c['speed_bp']):
        if speed <= 1:
            px, py = measured('pressure_ratio',speed)
            xx, yy = measured('efficiency',speed)
        else:
            px, py = [speed*x for x in prx], [(1+speed**2*(y**.4-1))**2.5 for y in pry]
            xx, yy = [speed*x for x in ex], ey
        px = [x/source_design_flow for x in px]; xx = [x/source_design_flow for x in xx]
        for j,flow in enumerate(c['m_ratio_bp']):
            pr = (1+head_scale*(interp(px,py,flow)**exponent-1))**(1/exponent)
            eta = 1-loss_scale*(1-interp(xx,yy,flow))
            max_pr = max(max_pr, near(pr,c['PR_table'][i][j],1e-11,'raw CSV PR reconstruction'))
            max_eta = max(max_eta, near(eta,c['ETAT_table'][i][j],1e-12,'raw CSV eta reconstruction'))
            cells += 1
    cp, gamma, _ = property_fd(c['T_in_design'],c['P_in_design'])
    tis = c['T_in_design']*c['PR_design']**(1-1/gamma)
    cp2 = property_fd(tis,c['P_out_design'])[0]
    eta_derived = cp2*(tis-c['T_in_design'])/(cp*(c['T_out_design']-c['T_in_design']))
    near(eta_derived,c['eta_design'],1e-8,'target eta inferred from Table 5.2 endpoints')
    errors = []
    for row in a['cases']:
        n,m = row['N_rpm']/c['N_design'],row['mdot_kg_s']/c['mdot_design']
        if row['use_metadata_coordinates']:
            n /= math.sqrt(row['Tin_K']/c['T_in_design'])
            m *= math.sqrt(row['Tin_K']/c['T_in_design'])/(row['Pin_Pa']/c['P_in_design'])
        near(n,row['speed_coordinate'],1e-14,'speed coordinate')
        near(m,row['flow_coordinate'],1e-14,'flow coordinate')
        r = bilinear(c['speed_bp'],c['m_ratio_bp'],c['PR_table'],n,m)
        eta = bilinear(c['speed_bp'],c['m_ratio_bp'],c['ETAT_table'],n,m)
        er = r*(1-.005158-.002579)/(1+r*.011605)
        mt = bilinear(f['bp_er'],f['bp_speed'],f['table_mf'],er,55090)
        for name,x in (('PR',r),('eta',eta),('turbine_ratio',er),('turbine_return_flow_kg_s',mt)):
            near(x,row[name],1e-12,name)
        inp = dict(row,kind='compressor',ratio=r,eta=eta)
        power = machine(inp); finer = machine(inp,.01)
        errors.append(near(power['W_W'],row['compressor_power_W'],.02,'independent power'))
        near(power['W_W'],finer['W_W'],.02,'finite difference step halving')
        near(power['Tout_K'],row['compressor_Tout_K'],1e-5,'independent Tout')
    # Algebraic solution of EXISTING fixed-drop equations; not a new pressure anchor.
    # This only proves a numerical closure option, not physical inventory dynamics.
    pressure_residuals=[];qvalues=[]
    for flow in c['m_ratio_bp']:
        r = bilinear(c['speed_bp'],c['m_ratio_bp'],c['PR_table'],1,flow)
        er = r*(1-.007737)/(1+r*.011605);alpha=r/er
        assert alpha>1
        q=(alpha*12000+r*18000)/(alpha-1)
        pin=(q-12000)/er-18000
        assert q>12000 and pin>0
        pressure_residuals.append(near(r*pin,q,1e-7,'algebraic pressure closure'))
        qvalues.append(q)
    for repo in (ROOT,active):
        assert not subprocess.check_output(['git','-C',str(repo),'diff','HEAD','--name-only'],text=True).strip()
    head=subprocess.check_output(['git','-C',str(active),'rev-parse','HEAD'],text=True).strip()
    assert head=='f8bcd833e816eb681982b7dd04364e4b856948e3'
    archive=subprocess.check_output(['git','-C',str(ROOT),'rev-parse','archive/pre-restart-20260824^{}'],text=True).strip()
    assert archive=='8f625c268c35a95c18a626305c1aa6a79ae2ace7'
    for row in protected:
        assert sha(row['paths']) == row['hashes']
    result={'status':'PASS','audit_sha256':sha(audit_path),'verifier_sha256':sha(__file__),
            'helper_sha256':sha(ROOT/'tests/verify_tac_power_sources.py'),
            'raw_reconstruction_cells_per_table':cells,'raw_reconstruction_PR_max_error':max_pr,
            'raw_reconstruction_eta_max_error':max_eta,'source_design_PR':source_pr,
            'source_design_eta':source_eta,'head_scale':head_scale,'loss_scale':loss_scale,
            'independent_eta_design':eta_derived,'local_power_max_error_W':max(errors),
            'pressure_algebraic_cases':len(qvalues),'pressure_algebraic_q_range_Pa':[min(qvalues),max(qvalues)],
            'pressure_algebraic_max_residual_Pa':max(pressure_residuals),
            'active_head':head,'archive':archive,'protected_count':len(protected),
            'archived_mat_hashes':archived_mats,'historical_sources_read_not_executed':lineage,
            'slx_coordinate_system_evidence':sys,'model_loaded_or_simulated':False,
            'formal_mutations':False,'model_acceptance_passed':False}
    output=dest/'independent_verification.json'
    if args.verify_only:
        assert json.loads(output.read_text())==result
    else:
        with output.open('x') as stream:
            json.dump(result,stream,ensure_ascii=False,indent=2);stream.write('\n')
    print(json.dumps({k:v for k,v in result.items() if k not in
                     ('historical_sources_read_not_executed','slx_coordinate_system_evidence')},ensure_ascii=False,indent=2))


if __name__=='__main__':
    main()
