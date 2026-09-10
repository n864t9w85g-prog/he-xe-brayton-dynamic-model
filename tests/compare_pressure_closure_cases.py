#!/usr/bin/env python3
"""Independent four-case/structural check. No model execution or edits."""
import argparse
import csv
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
import zipfile
from check_pressure_closure_run import check, series, at
from verify_tac_power_sources import ROOT, sha, near


def xml_inventory(path):
    blocks={};edges=set();charts={}
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            if name.startswith('simulink/systems/') and name.endswith('.xml'):
                root=ET.fromstring(archive.read(name))
                for b in root.findall('Block'):
                    blocks[b.get('SID')]={'type':b.get('BlockType'),'name':b.get('Name'),
                                         'p':{p.get('Name'):p.text for p in b.findall('P')}}
                for line in root.findall('Line'):
                    src=line.find("P[@Name='Src']")
                    if src is not None:
                        edges.update((src.text,p.text) for p in line.findall(".//P[@Name='Dst']"))
            if name.startswith('simulink/stateflow/chart_') and name.endswith('.xml'):
                scripts=[p.text for p in ET.fromstring(archive.read(name)).findall(".//P[@Name='script']")]
                if scripts:charts[name]=scripts
        config=archive.read('simulink/configSet0.xml')
    return blocks,edges,charts,config


def main():
    parser=argparse.ArgumentParser();parser.add_argument('directory',type=Path)
    parser.add_argument('--verify-only',action='store_true');args=parser.parse_args()
    dest=args.directory.resolve();assert dest.is_relative_to(ROOT/'tmp')
    cases={};files={}
    for mode in ('reference','candidate'):
        for stop in (500,14000):
            key=f'{mode}_{stop}';directory=dest/key
            cases[key]=check(directory)
            assert cases[key]==json.loads((directory/'independent_verification.json').read_text())
            assert cases[key]['closure_gate_passed']==(mode=='candidate')
            assert cases[key]['delay_update_count']==51
            states=list(directory.glob('state_*.csv'));assert len(states)==40
            for p in states:series(p)  # validates finite scalar states
            for duration in cases[key]['sampling']:
                expected=[duration['stop_time_s']/50,0]
                for i in (1,2,3,4):
                    assert duration['blocks'][f'block_{i}']['compiled_sample_time']==expected
            files[key]={name:sha(directory/name) for name in
                        ('output.mat','status.json','sampling.json','independent_verification.json','diary.txt')}
    a,ae,ac,config_a=xml_inventory(dest/'pressure_reference.slx')
    b,be,bc,config_b=xml_inventory(dest/'pressure_candidate.slx')
    assert len(a)==1233 and len(b)==1235
    assert a.keys()<=b.keys() and b.keys()-a.keys()=={'4008','4009'}
    assert b['4008']['type']=='Outport' and b['4008']['p']['Port']=='7'
    assert b['4009']['type']=='Fcn'
    # Official API resized the TAC outline for the seventh output; no equation changes.
    layout_changes={}
    for sid in a:
        old,new=dict(a[sid]['p']),dict(b[sid]['p'])
        if old.get('Position')!=new.get('Position'):
            layout_changes[sid]={'before':old.get('Position'),'after':new.get('Position')}
            old.pop('Position',None);new.pop('Position',None)
        assert old==new and a[sid]['name']==b[sid]['name'] and a[sid]['type']==b[sid]['type'],sid
    assert set(layout_changes)=={'3804'}
    assert ac==bc and config_a==config_b
    assert ae-be=={('3391#out:1','514#in:4')}
    assert be-ae=={('4009#out:1','514#in:4'),('3804#out:7','4009#in:1'),('3811#out:1','4008#in:1')}
    patch=json.loads((dest/'patch_audit.json').read_text())
    assert sha(patch['candidate_file'])==patch['candidate_sha256']
    assert sha(ROOT/'tests/patch_pressure_algebraic_candidate.m')==patch['patch_sha256']
    assert patch['expression']==b['4009']['p']['Expr']
    comparison=[]
    keys=('compressor_outlet_P','compressor_inlet_P','turbine_inlet_P','turbine_outlet_P',
          'compressor_inlet_T','compressor_outlet_T','turbine_inlet_T','turbine_outlet_T',
          'reactor_outlet_T','reactor_inlet_T','recuperator_cold_outlet_T','recuperator_hot_outlet_T',
          'cooler_cold_inlet_T','cooler_cold_outlet_T','compressor_power','turbine_power','P_sw',
          'hexe_mdot_compressor','hexe_mdot_turbine')
    for stop in (500,14000):
        ref=cases[f'reference_{stop}']['end_values'];cand=cases[f'candidate_{stop}']['end_values']
        for name in keys:
            comparison.append({'stop_time_s':stop,'signal':name,'reference':ref[name],
                               'candidate':cand[name],'delta':cand[name]-ref[name]})
        # Shared sampled map values remain unchanged across entire original delay grids.
        directory=dest/f'reference_{stop}'
        times=series(directory/'flow_delay_witness.csv')[0]
        for name in ('flow_delay_witness','turbine_expansion_ratio','turbine_lookup_expansion_ratio'):
            refdata=series(directory/(name+'.csv'))
            canddata=series(dest/f'candidate_{stop}'/(name+'.csv'))
            for time in times:near(at(refdata,time),at(canddata,time),1e-11,'unchanged flow/map recursion')
    # Fresh reference runs reproduce the saved reference pressure hits, including long run.
    with (ROOT/'tmp/pressure_chain_4chhD5/saved_500_exact_hits.csv').open() as stream:
        old=list(csv.DictReader(stream))
    for stop in (500,14000):
        fresh=series(dest/f'reference_{stop}/compressor_outlet_P.csv')
        for row in old:
            time=float(row['time_s'])*stop/500
            near(at(fresh,time),float(row['compressor_outlet_P']),1e-5,'saved pressure sequence')
    active=ROOT.parent/'不接入转子稳态模型_副本'
    for repo in (ROOT,active):
        assert not subprocess.check_output(['git','-C',str(repo),'diff','HEAD','--name-only'],text=True).strip()
    head=subprocess.check_output(['git','-C',str(active),'rev-parse','HEAD'],text=True).strip()
    archive=subprocess.check_output(['git','-C',str(ROOT),'rev-parse','archive/pre-restart-20260824^{}'],text=True).strip()
    assert head=='f8bcd833e816eb681982b7dd04364e4b856948e3'
    assert archive=='8f625c268c35a95c18a626305c1aa6a79ae2ace7'
    result={'status':'PASS','scope':'Four warm steady runs and pressure numerical closure only; not paper curve acceptance.',
            'runs':{key:{k:v for k,v in value.items() if k in ('stop_time_s','sample_count',
                    'delay_update_count','max_abs_closure_residual_Pa','max_algebraic_formula_error_Pa',
                    'reference_replay_max_error_Pa','closure_gate_passed')} for key,value in cases.items()},
            'comparison':comparison,'raw_result_hashes':files,'existing_block_count':len(a),'new_block_count':2,
            'layout_only_changes':layout_changes,'removed_edges':[list(e) for e in sorted(ae-be)],
            'added_edges':[list(e) for e in sorted(be-ae)],
            'all_existing_chart_scripts_identical':True,'saved_solver_config_identical':True,
            'all_40_integrator_initial_values_unchanged':True,'both_delay_initial_values_unchanged':True,
            'verifier_sha256':sha(__file__),'case_verifier_sha256':sha(ROOT/'tests/check_pressure_closure_run.py'),
            'patch_audit_sha256':sha(dest/'patch_audit.json'),'protected_count':34,'active_head':head,
            'archive':archive,'formal_mutations':False,'paper_acceptance_passed':False}
    output=dest/'comparison_v2.json'
    if args.verify_only:
        assert json.loads(output.read_text())==result
    else:
        with output.open('x') as stream:
            json.dump(result,stream,ensure_ascii=False,indent=2);stream.write('\n')
        with (dest/'comparison_v2.csv').open('x') as stream:
            writer=csv.DictWriter(stream,fieldnames=list(comparison[0]));writer.writeheader();writer.writerows(comparison)
    print(json.dumps({k:v for k,v in result.items() if k not in ('comparison','raw_result_hashes')},indent=2))


if __name__=='__main__':main()
