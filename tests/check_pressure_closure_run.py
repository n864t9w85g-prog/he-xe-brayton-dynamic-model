#!/usr/bin/env python3
"""Verify raw pressure logs; optional regression deliberately fails reference.

Pressure samples are never linearly interpolated. For independently logged
sampled signals, take the last value at/before a pressure timestamp (ZOH).
"""
import argparse
import bisect
import csv
import json
from pathlib import Path
from verify_tac_power_sources import ROOT, sha, near, bilinear


def series(path):
    with path.open() as stream:
        rows=list(csv.DictReader(stream))
    times=[float(x['time_s']) for x in rows];ys=[float(x['value']) for x in rows]
    assert times and all(a<=b for a,b in zip(times,times[1:])),path
    assert all(abs(y)<float('inf') for y in ys),path
    return times,ys


def at(data,time):
    ts,ys=data;i=bisect.bisect_right(ts,time+1e-9)-1
    assert i>=0
    return ys[i]


def check(directory):
    status=json.loads((directory/'status.json').read_text())
    assert status['success'] and status['final_time_s']==status['requested_stop_time_s']
    assert sha(status['model_file'])==status['model_sha256']
    for src in status['source_hashes']:
        assert sha(src['path'])==src['sha256'],src['path']
    with (directory/'protected_after.csv').open() as stream:
        protected=list(csv.DictReader(stream))
    assert len(protected)==34
    for row in protected:
        assert sha(row['paths'])==row['hashes'],row['paths']
    logs={p.stem:series(p) for p in directory.glob('*.csv') if p.name!='protected_after.csv'}
    ts,qs=logs['compressor_outlet_P']
    residuals=[];formula_errors=[];equation_errors=[];feed=[]
    for time,q in zip(ts,qs):
        rc=at(logs['turbine_expansion_ratio'],time)
        er=at(logs['turbine_lookup_expansion_ratio'],time)
        feed_q=at(logs['recuperator_cold_outlet_P'],time)+8000
        residuals.append(q-feed_q);feed.append(feed_q)
        equation_errors.append(near(q,rc*((feed_q-12000)/er-18000),1e-5,'active pressure chain'))
        if status['mode']=='candidate':
            alpha=rc/er;qstar=(alpha*12000+rc*18000)/(alpha-1)
            formula_errors.append(near(feed_q,qstar,1e-5,'independent algebraic q'))
            near(feed_q,at(logs['pressure_algebraic_feed'],time),1e-5,'candidate input feed')
        else:
            near(feed_q,at(logs['pressure_delay_witness'],time),1e-5,'reference delay feed')
    replay_error=None
    if status['mode']=='reference':
        # Independent flow/pressure iteration from ORIGINAL saved initial values.
        maps=json.loads((ROOT/'tmp/tac_power_trace_Hnbkhl/summary.json').read_text())['tables']
        c,f=maps['compressor'],maps['turbine_flow'];qold=1551000.;mdot=11.982029
        replay=[]
        for t in logs['pressure_delay_witness'][0]:
            q=at(logs['compressor_outlet_P'],t)
            rc=bilinear(c['speed_bp'],c['m_ratio_bp'],c['PR_table'],1,mdot/12.04)
            er=rc*(1-.005158-.002579)/(1+rc*.011605)
            mt=bilinear(f['bp_er'],f['bp_speed'],f['table_mf'],er,55090)
            qnew=rc*((qold-12000)/er-18000)
            replay.append(near(q,qnew,1e-4,'reference recurrence replay'))
            qold,mdot=qnew,mt
        replay_error=max(replay)
    end={name:values[1][-1] for name,values in logs.items() if not name.startswith('state_')}
    result={'status':'VERIFIED','mode':status['mode'],'stop_time_s':status['final_time_s'],
            'model_sha256':status['model_sha256'],'sample_count':len(ts),'pressure_timestamps_s':ts,
            'delay_update_count':len(logs['pressure_delay_witness'][0]),
            'pressure_min_Pa':min(qs),'pressure_max_Pa':max(qs),'pressure_end_Pa':qs[-1],
            'max_abs_closure_residual_Pa':max(map(abs,residuals)),'final_closure_residual_Pa':residuals[-1],
            'max_pressure_chain_error_Pa':max(equation_errors),
            'max_algebraic_formula_error_Pa':max(formula_errors) if formula_errors else None,
            'reference_replay_max_error_Pa':replay_error,'protected_count':34,
            'closure_gate_passed':max(map(abs,residuals))<1e-5,'end_values':end,
            'verifier_sha256':sha(__file__),'paper_acceptance_passed':False,
            'raw_csv_sha256':{p.name:sha(p) for p in sorted(directory.glob('*.csv'))},
            'sampling':json.loads((directory/'sampling.json').read_text())}
    return result


def main():
    parser=argparse.ArgumentParser();parser.add_argument('directory',type=Path)
    parser.add_argument('--require-closed',action='store_true')
    parser.add_argument('--write-report',action='store_true')
    args=parser.parse_args();dest=args.directory.resolve();assert dest.is_relative_to(ROOT/'tmp')
    result=check(dest)
    if args.write_report:
        with (dest/'independent_verification.json').open('x') as stream:
            json.dump(result,stream,ensure_ascii=False,indent=2);stream.write('\n')
    print(json.dumps({k:v for k,v in result.items() if k not in
                     ('end_values','raw_csv_sha256','pressure_timestamps_s','sampling')},indent=2))
    if args.require_closed:
        assert result['closure_gate_passed'],(
            'PRESSURE_CLOSURE_REGRESSION_FAILED',result['max_abs_closure_residual_Pa'],1e-5)


if __name__=='__main__':main()
