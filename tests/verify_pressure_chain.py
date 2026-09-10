#!/usr/bin/env python3
"""Independently check saved-data pressure recurrence, maps and SLX wiring."""
import argparse
import csv
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile
from verify_tac_power_sources import ROOT, sha, near, bilinear, machine


def rows(path):
    with path.open() as f:
        return [{k:float(v) for k,v in row.items()} for row in csv.DictReader(f)]


def xml_trace(path):
    inventory={}
    with zipfile.ZipFile(path) as z:
        for sid in ('root','272','514','2898','3804','3811','3882','3942',
                    '278','388','521','755','2907','3016'):
            entry=f'simulink/systems/system_{sid}.xml'
            root=ET.fromstring(z.read(entry))
            blocks={b.get('SID'):{'type':b.get('BlockType'),'name':b.get('Name'),
                    'p':{p.get('Name'):p.text for p in b.findall('P')}} for b in root.findall('Block')}
            edges=[]
            for line in root.findall('Line'):
                src=line.find("P[@Name='Src']").text
                edges.extend([src,p.text] for p in line.findall(".//P[@Name='Dst']"))
            inventory[sid]={'entry':entry,'blocks':blocks,'edges':edges}
        cfg=ET.fromstring(z.read('simulink/configSet0.xml'))
        settings={p.get('Name'):p.text for p in cfg.iter('P')
                  if p.get('Name') in ('SolverName','MaxStep','FixedStep','StartTime','StopTime')}
    root=inventory['root']
    assert root['blocks']['3391']['type']=='UnitDelay'
    assert root['blocks']['3391']['p']['InitialCondition']=='1.551e6'
    assert root['blocks']['3391']['p']['SampleTime']=='-1'
    assert root['blocks']['3994']['p']['InitialCondition']=='11.982029'
    for edge in [('3804#out:6','3391#in:1'),('3391#out:1','514#in:4'),
                 ('514#out:4','272#in:5'),('272#out:2','3804#in:1'),
                 ('3804#out:1','514#in:3'),('514#out:2','2898#in:4'),
                 ('2898#out:2','3804#in:4'),('3804#out:2','3994#in:1'),
                 ('3994#out:1','514#in:1')]:
        assert list(edge) in root['edges'],edge
    traces=[]
    for sid,out_sid,drop in [('278','384',2000),('388','494',2000),
            ('521','637',4000),('755','871',4000),('521','633',0),('755','867',0),
            ('2907','3012',9000),('3016','3121',9000)]:
        sys=inventory[sid];bs=sys['blocks'];incoming={dst:src for src,dst in sys['edges']}

        def driver(block,port=1):
            return incoming[f'{block}#in:{port}'].split('#')[0]

        def trace(block,depth=0):
            assert depth<20
            b=bs[block];typ=b['type'];p=b['p']
            if typ=='Constant': return {'constant':float(p['Value']),'SID':block}
            if typ=='Inport': return {'input':b['name'],'SID':block}
            if typ=='From':
                matches=[k for k,v in bs.items() if v['type']=='Goto' and v['p']['GotoTag']==p['GotoTag']]
                assert len(matches)==1
                return trace(driver(matches[0]),depth+1)
            if typ=='Mux':
                assert p['Inputs']=='2'
                return [trace(driver(block,i),depth+1) for i in (1,2)]
            if typ=='Fcn':
                assert p['Expr']=='u(1) - u(2)'
                return {'subtract':trace(driver(block),depth+1),'SID':block}
            if typ=='Outport': return trace(driver(block),depth+1)
            raise AssertionError((sid,block,typ))

        tree=trace(out_sid)
        assert tree['subtract'][1]['constant']==drop
        assert 'input' in tree['subtract'][0]
        traces.append({'system':sid,'outport':out_sid,'expression':tree,'drop_Pa':drop})
    return {'systems':inventory,'pressure_subtractions':traces,'saved_solver_settings':settings}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('directory',type=Path)
    parser.add_argument('--verify-only',action='store_true');args=parser.parse_args()
    dest=args.directory.resolve();assert dest.is_relative_to(ROOT/'tmp')
    auditfile=dest/'audit.json';a=json.loads(auditfile.read_text())
    for src in a['source_hashes']: assert sha(src['path'])==src['sha256'],src['path']
    with (dest/'protected_after.csv').open() as f: protected=list(csv.DictReader(f))
    assert len(protected)==34
    for row in protected: assert sha(row['paths'])==row['hashes'],row['paths']
    oldfile=ROOT/'tmp/tac_power_trace_Hnbkhl/summary.json'
    old=json.loads(oldfile.read_text());C=old['tables']['compressor'];F=old['tables']['turbine_flow']
    slx=next(x['path'] for x in a['source_hashes'] if x['path'].endswith('.slx'))
    evidence=xml_trace(slx)
    def maps(m):
        r=bilinear(C['speed_bp'],C['m_ratio_bp'],C['PR_table'],1,m/12.04)
        e=r*(1-.005158-.002579)/(1+r*.011605)
        return r,e,bilinear(F['bp_er'],F['bp_speed'],F['table_mf'],e,55090)
    hits=rows(dest/'saved_500_exact_hits.csv');replay=rows(dest/'offline_recurrence.csv')
    assert len(hits)==len(replay)==51
    q,m=1551000.,11.982029;errors=[]
    for k,row in enumerate(hits):
        near(row['time_s'],k*10,1e-9,'hit time')
        r,e,mt=maps(m)
        qnew=r*((q-12000)/e-18000)
        errors.append(near(qnew,row['compressor_outlet_P'],1e-5,'direct recurrence saved pressure'))
        near(q,row['recuperator_cold_outlet_P']+8000,1e-5,'saved delayed pressure')
        near(qnew,replay[k]['compressor_outlet_Pa'],1e-5,'MATLAB replay')
        near(m,row['hexe_mdot_compressor'],1e-10,'saved delayed flow')
        near(mt,row['hexe_mdot_turbine'],1e-10,'saved turbine flow')
        q,m=qnew,mt
    # Bisection, independently of MATLAB fzero.
    lo,hi=11.95,12.04
    assert maps(lo)[2]-lo>0>maps(hi)[2]-hi
    for _ in range(70):
        mid=(lo+hi)/2
        if maps(mid)[2]>mid: lo=mid
        else: hi=mid
    mr=(lo+hi)/2;r,e,_=maps(mr);alpha=r/e
    near(mr,a['map_fixed_flow_kg_s'],1e-12,'map fixed flow')
    near(alpha,a['pressure_multiplier'],1e-12,'pressure multiplier')
    qstar=(alpha*12000+r*18000)/(alpha-1)
    near(qstar,a['pressure_fixed_point_Pa'],1e-6,'pressure fixed point')
    # Direct numerical identity and deliberate pressure perturbation.
    perturb=1.
    atstar=r*((qstar-12000)/e-18000)
    disturbed=r*((qstar+perturb-12000)/e-18000)
    near(atstar,qstar,1e-8,'fixed point identity')
    near(disturbed-atstar,alpha*perturb,1e-8,'perturbation amplification')
    assert alpha>1
    exacth,exactl=12000/1551000,18000/1551000
    exacte=r*(1-exacth)/(1+r*exactl)
    near(r*((1551000-12000)/exacte-18000),1551000,1e-8,'exact normalization fixed point')
    assert r/exacte>1  # More digits do NOT stabilize this delay recurrence.
    case_errors=[]
    for case in a['local_power_cases']:
        inp=dict(old['turbine']);inp['ratio']=case['er']
        result=machine(inp)
        case_errors.append(near(result['W_W'],case['power_W'],.02,'power crosscheck'))
    wlpath=ROOT/'tmp/pressure_chain_1l2mJo/wolfram_recurrence_verification.json'
    wl=json.loads(wlpath.read_text());assert not wl['raw_result']['isError']
    raw=wl['raw_result']['content'][0]['text'];payload=json.loads(json.loads(raw.split('= ',1)[1]))
    assert payload['checks']==[True]*5
    near(payload['pressureMultiplierAndFixedPoint'][0],alpha,1e-12,'Wolfram alpha')
    near(payload['pressureMultiplierAndFixedPoint'][1],qstar,1e-6,'Wolfram fixed point')
    result={'status':'PASS','audit_sha256':sha(auditfile),'verifier_sha256':sha(__file__),
            'source_verifier_sha256':sha(ROOT/'tests/verify_tac_power_sources.py'),
            'saved_hit_count':51,'max_saved_pressure_error_Pa':max(errors),
            'max_power_crosscheck_error_W':max(case_errors),'map_fixed_flow_kg_s':mr,
            'pressure_multiplier':alpha,'pressure_fixed_point_Pa':qstar,
            'Wolfram_check_count':5,'wolfram_evidence_sha256':sha(wlpath),
            'protected_count':34,'model_acceptance_passed':False,
            'scope':'Offline pressure/flow subgraph and local fixed-input power only; no SLX run, no claim of physical rotor instability.',
            'slx_evidence':evidence}
    output=dest/'independent_verification.json'
    if args.verify_only: assert json.loads(output.read_text())==result
    else:
        with output.open('x') as f: json.dump(result,f,ensure_ascii=False,indent=2);f.write('\n')
    print(json.dumps({k:v for k,v in result.items() if k!='slx_evidence'},ensure_ascii=False,indent=2))


if __name__=='__main__': main()
