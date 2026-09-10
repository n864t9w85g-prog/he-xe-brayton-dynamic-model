#!/usr/bin/env python3
"""Independent steady equations and raw-data checks; no SLX writes or fits."""
import argparse
import csv
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile
from verify_tac_power_sources import ROOT, sha, near, property_fd


def nak_cp(t):
    return 1000 * (1.061 - 3.694e-4*t + 4.615e-8*t*t + 1.509e-10*t**3)


def nak_h(t):
    return 1000 * (1.061*t - 3.694e-4*t*t/2 + 4.615e-8*t**3/3 + 1.509e-10*t**4/4)


def solve_steady(u, parameters, fd_step=.02):
    """Eliminate wall and midpoint states; iterate properties, not time ODEs."""
    ti, mc, hi, pressure, mh = u
    cp_h, cp_c = [520., 520.], [900., 900.]
    old = None
    for iteration in range(100):
        ch = [mh*x for x in cp_h]
        cc = [mc*x for x in cp_c]
        resistance = [1/(p['h_h']*p['A_region'])+1/(p['h_c']*p['A_region2'])
                      for p in parameters]
        d = [resistance[i]+.5/ch[i]+.5/cc[i] for i in range(2)]
        # D1*q1 + q2/Cc2 = deltaT; q1/Ch1 + D2*q2 = deltaT.
        det = d[0]*d[1]-1/(cc[1]*ch[0])
        q1 = (hi-ti)*(d[1]-1/cc[1])/det
        q2 = (hi-ti)*(d[0]-1/ch[0])/det
        hin = [hi, hi-q1/ch[0]]
        cin = [ti+q2/cc[1], ti]
        q = [q1, q2]
        states = []
        for i in range(2):
            hout, cout = hin[i]-q[i]/ch[i], cin[i]+q[i]/cc[i]
            hm, cm = (hin[i]+hout)/2, (cin[i]+cout)/2
            wall = hm-q[i]/(parameters[i]['h_h']*parameters[i]['A_region'])
            states.append([cm, cout, hm, hout, wall])
        flat = sum(states, [])
        if old and max(abs(a-b) for a,b in zip(flat,old)) < 2e-7:
            return states, iteration+1
        old = flat
        cp_h = [property_fd(states[i][2], pressure-i*9000, fd_step)[0] for i in range(2)]
        cp_c = [nak_cp(states[i][0]) for i in range(2)]
    raise AssertionError('Independent property iteration did not converge')


def read_csv(path, constant=False):
    with path.open() as f:
        rows = [(float(r['time_s']),float(r['value'])) for r in csv.DictReader(f)]
    assert rows[0][0] == 0
    if constant:
        assert len(rows)==1 and rows[-1][0]==0
    else:
        assert rows[-1][0] == 500
    assert all(math.isfinite(t) and math.isfinite(y) for t,y in rows)
    assert all(a[0]<=b[0] for a,b in zip(rows,rows[1:]))
    return rows


def semantic_inventory(path, component):
    # Compare executable block parameters and normalized wiring, not XML bytes.
    keys = {'Value','Gain','Inputs','Expr','InitialCondition','Table',
            'BreakpointsForDimension1','BreakpointsForDimension2','InterpMethod',
            'ExtrapMethod','SampleTime','Port','GotoTag','SFBlockType'}
    with zipfile.ZipFile(path) as z:
        root = ET.fromstring(z.read('simulink/systems/system_root.xml'))
        sub = next(b for b in root.findall('Block') if b.get('Name')==component)
        blocks, edges = {}, []

        def walk(ref, prefix):
            r = ET.fromstring(z.read('simulink/systems/'+ref+'.xml'))
            names = {b.get('SID'):prefix+b.get('Name') for b in r.findall('Block')}
            def port(s):
                sid, p = s.split('#')
                return names[sid]+'#'+p
            for b in r.findall('Block'):
                name = names[b.get('SID')]
                blocks[name] = [b.get('BlockType'),{p.get('Name'):p.text for p in b.findall('P') if p.get('Name') in keys}]
                child = b.find('System')
                if child is not None:
                    walk(child.get('Ref'),name+'/')
            for line in r.findall('Line'):
                src = line.findtext("P[@Name='Src']")
                for p in line.findall(".//P[@Name='Dst']"):
                    edges.append([port(src),port(p.text)])
        walk(sub.find('System').get('Ref'),'')
        scripts = {}
        for name in z.namelist():
            if name.startswith('simulink/stateflow/chart_') and name.endswith('.xml'):
                r = ET.fromstring(z.read(name)); cp = r.findtext("P[@Name='name']",'')
                if cp.startswith(component+'/'):
                    scripts[cp[len(component)+1:]] = r.findtext(".//P[@Name='script']")
        return {'blocks':blocks,'edges':sorted(edges),'scripts':scripts}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('directory',type=Path)
    parser.add_argument('--verify-only',action='store_true');a=parser.parse_args()
    dest=a.directory.resolve();assert dest.is_relative_to(ROOT/'tmp')
    s=json.loads((dest/'summary.json').read_text())
    for row in s['source_hashes']+s['boundary_evidence']:
        assert sha(row['path'])==row['sha256'],row['path']
    assert sha(s['model_file'])==s['model_sha256']
    source=s['source_hashes'][0]['path']
    source_tree=semantic_inventory(source,'precooler')
    assert source_tree==semantic_inventory(s['model_file'],'DUT')
    protected=list(csv.DictReader((dest/'protected_after.csv').open()))
    assert len(protected)==34
    for row in protected:
        assert sha(row['paths'])==row['hashes']
    base=s['cases'][0];checks=[]
    expected_changes=[[],[0],[2],[3],[4],[0,2,3,4]]
    for k,c in enumerate(s['cases']):
        assert c['final_time_s']==500 and not c['error']
        case_dir=dest/c['name'];assert sha(case_dir/'raw.mat')==c['raw_sha256']
        changed=[i for i in range(5) if c['inputs'][i]!=base['inputs'][i]]
        assert changed==expected_changes[k]
        for j in range(5):
            near(read_csv(case_dir/f'y_{j+1}.csv',j in (0,1,4))[-1][1],c['outputs'][j],1e-8,'raw output')
        for j,expected in ((0,c['inputs'][4]),(1,c['inputs'][3]-18000),(4,c['inputs'][1])):
            near(c['outputs'][j],expected,1e-8,'constant mass/pressure output')
        for i in range(2):
            for j in range(5):
                near(read_csv(case_dir/f'r{i+1}_s{j+1}.csv')[-1][1],c['states'][i][j],1e-8,'raw state')
        states,iterations=solve_steady(c['inputs'],s['parameters'])
        other,_=solve_steady(c['inputs'],s['parameters'],.01)
        err=max(abs(x-y) for x,y in zip(sum(states,[]),sum(c['states'],[])))
        half=max(abs(x-y) for x,y in zip(sum(states,[]),sum(other,[])))
        assert err<2e-4 and half<2e-5,(c['name'],err,half)
        ti,mc,hi,pressure,mh=c['inputs'];x=c['states'];q=[];balance=[]
        for i,p in enumerate(s['parameters']):
            ch=mh*property_fd(x[i][2],pressure-i*9000)[0]
            cc=mc*nak_cp(x[i][0])
            hot_in=hi if i==0 else x[0][3]
            cold_in=x[1][1] if i==0 else ti
            qh=p['h_h']*p['A_region']*(x[i][2]-x[i][4])
            qc=p['h_c']*p['A_region2']*(x[i][4]-x[i][0])
            balance.extend([ch*(hot_in-x[i][2])-qh/2,
                ch*(x[i][2]-x[i][3])-qh/2,
                cc*(cold_in-x[i][0])+qc/2,
                cc*(x[i][0]-x[i][1])+qc/2,qh-qc])
            q.append(qh)
            near(ch/mh,c['cp_hot_cold'][i][0],1e-4,'independent cp')
            near(cc/mc,c['cp_hot_cold'][i][1],1e-9,'NaK polynomial')
        assert max(abs(v) for v in balance)<.1,(c['name'],balance)
        checks.append({'name':c['name'],'T_HeXe_out_K':c['outputs'][2],
            'T_NaK_out_K':c['outputs'][3],
            'delta_HeXe_out_from_local_reference_K':c['outputs'][2]-base['outputs'][2],
            'delta_NaK_out_from_local_reference_K':c['outputs'][3]-base['outputs'][3],
            'independent_state_max_error_K':err,'FD_halving_state_max_change_K':half,
            'iterations':iterations,'max_steady_equation_residual_W':max(abs(v) for v in balance),
            'wall_heat_total_W':sum(q),
            'NaK_enthalpy_heat_W':mc*(nak_h(c['outputs'][3])-nak_h(ti))})
    delta=[base['outputs'][2]-s['coupled_outputs'][0],base['outputs'][3]-s['coupled_outputs'][1]]
    assert max(abs(v) for v in delta)<2e-4,delta
    gap=405.16-base['outputs'][2]
    shift=checks[-1]['delta_HeXe_out_from_local_reference_K']
    isolated_sum=sum(c['delta_HeXe_out_from_local_reference_K'] for c in checks[1:5])
    result={'status':'PASS','scope':s['scope'],'summary_sha256':sha(dest/'summary.json'),
        'verifier_sha256':sha(__file__),'property_verifier_sha256':sha(ROOT/'tests/verify_tac_power_sources.py'),
        'checks':checks,'same_boundary_minus_coupled_K':delta,
        'local_HeXe_gap_to_paper_K':gap,
        'NaK_Tin_local_effect_fraction_of_gap':checks[1]['delta_HeXe_out_from_local_reference_K']/gap,
        'all_inputs_local_effect_fraction_of_gap':shift/gap,
        'nonadditive_interaction_K':shift-isolated_sum,
        'all_inputs_HeXe_out_minus_paper_K':checks[-1]['T_HeXe_out_K']-405.16,
        'all_inputs_NaK_out_minus_paper_K':checks[-1]['T_NaK_out_K']-609.58,
        'paper_NaK_endpoints_with_active_cp_Q_W':6.95*(nak_h(609.58)-nak_h(360.10)),
        'same_executable_blocks':len(source_tree['blocks']),
        'same_executable_edges':len(source_tree['edges']),
        'same_chart_scripts':len(source_tree['scripts']),
        'protected_count':len(protected),'formal_mutations':False,'paper_acceptance':False}
    output=dest/'independent_verification.json'
    if a.verify_only:
        assert json.loads(output.read_text())==result
    else:
        with output.open('x') as f:json.dump(result,f,ensure_ascii=False,indent=2);f.write('\n')
    print(json.dumps(result,ensure_ascii=False,indent=2))


if __name__=='__main__':
    main()
