"""Read-only-source arithmetic audit of thesis power definitions.

No property evaluation, SLX loading/simulation, parameter changes or fitting.
Only writes new evidence files in a specified tmp directory. --verify-only
rechecks the existing evidence without writes. Table values are manually
transcribed from visually inspected primary pages, not extracted OCR facts.
"""
import argparse
import csv
from decimal import Decimal as D, getcontext
from fractions import Fraction as F
import hashlib
import json
from pathlib import Path
import re
import subprocess

getcontext().prec = 40
ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('run', type=Path)
p.add_argument('--verify-only', action='store_true')
args = p.parse_args()
run = args.run.resolve()
assert run.is_relative_to(ROOT/'tmp') and run.is_dir()
sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
protected_file = ROOT/'tmp/tp7d213f64_7fad_4bfa_b722_0771b21d9640/protected_after.csv'
protected = list(csv.DictReader(protected_file.open()))
assert len(protected) == 34
for item in protected:
    assert sha(item['paths']) == item['hashes'], item['paths']
source = ROOT/'tmp/steady53_curves_20260828/source_f8bcd83'
active = ROOT.parent/'不接入转子稳态模型_副本'
runner = source/'tests/steady53/run_steady53_case.m'
assert sha(runner) == sha(active/'tests/steady53/run_steady53_case.m')
text = runner.read_text()
etas = re.findall(r'^\s*etaGenerator\s*=\s*([0-9.]+)\s*;',text,re.M)
assert etas == ['0.96527']
assert 'result.signals.tac_electric_power = etaGenerator .*' in text
assert '(result.signals.turbine_power -' in text
assert 'result.signals.compressor_power)' in text

# Paper-direct inputs. Decimal-place rounding below is a CONDITIONAL display
# model, not a measurement uncertainty or new model acceptance threshold.
table = {
    'Q_IHX_kW':'2647.18','Q_cooler_kW':'1622.00','Q_recuperator_kW':'3130.58',
    'P_turbine_kW':'2252.2','P_compressor_kW':'1231.6',
    'P_electric_kW':'1000.21','system_efficiency_percent':'37.54'}
qihx,qcool,pt,pc,pe,eff = [D(table[k]) for k in (
    'Q_IHX_kW','Q_cooler_kW','P_turbine_kW','P_compressor_kW',
    'P_electric_kW','system_efficiency_percent')]
eta = D('.98')  # Table 3.1, PDF61 / printed46, DIRECT source.
net = pt-pc
gap = qihx-qcool-net
assert gap == D('4.58')
fraction_gap = F(table['Q_IHX_kW'])-F(table['Q_cooler_kW'])-F(table['P_turbine_kW'])+F(table['P_compressor_kW'])
assert fraction_gap == F(229,50) == F(gap)
half_width = D('.005')+D('.005')+D('.05')+D('.05')
rounding_gap_interval = [gap-half_width,gap+half_width]
assert rounding_gap_interval == [D('4.470'),D('4.690')]
eta_electric_ihx = 100*pe/qihx
reported_eff_interval = [eff-D('.005'),eff+D('.005')]
electric_ihx_interval = [100*(pe-D('.005'))/(qihx+D('.005')),
                         100*(pe+D('.005'))/(qihx-D('.005'))]
assert electric_ihx_interval[0] > reported_eff_interval[1]
q_eff_inverse = 100*pe/eff
eta_electric_rx = 100*pe/D('2664')  # §5.3.1 body, PDF106 / printed91.
# The body says approximately 2.664 MW: it is NOT an exact 2664.000 kW.
# Central values alone give 37.54542%, not 37.54 under nearest rounding.
body_reactor_rounding_interval = [D('2663.5'),D('2664.5')]
assert body_reactor_rounding_interval[0] < q_eff_inverse < body_reactor_rounding_interval[1]

# A telescoping state-function identity, checked by exact coefficients.
# h1:turbine inlet, h2:outlet, h3:RHX hot outlet, h4:compressor inlet,
# h5:compressor outlet, h6:RHX cold outlet.
terms = {'Q_IHX':[1,0,0,0,0,-1], 'Q_cooler':[0,0,1,-1,0,0],
         'P_turbine':[1,-1,0,0,0,0], 'P_compressor':[0,0,0,-1,1,0],
         'Q_RHX_hot':[0,1,-1,0,0,0], 'Q_RHX_cold':[0,0,0,0,-1,1]}
lhs = [terms['Q_IHX'][i]-terms['Q_cooler'][i]-terms['P_turbine'][i]+terms['P_compressor'][i] for i in range(6)]
rhs = [terms['Q_RHX_hot'][i]-terms['Q_RHX_cold'][i] for i in range(6)]
assert lhs == rhs == [0,1,-1,0,1,-1]
prior_file = ROOT/'tmp/tp9071fb5b_0341_4b8c_85b4_5f791b3ff63a/summary.json'
assert sha(prior_file) == '421c4e626cbf84d1422a3d1ec3dc68ded98e426efdc1d478b081b31e2ca7b451'
prior = json.loads(prior_file.read_text())
hot,cold = prior['paths'][1:3]
signed_recup_gap = 11.97*(abs(hot['dH_total_J_kg'])-abs(cold['dH_total_J_kg']))/1000
assert float(gap)>0>signed_recup_gap
temperature_only_gap = abs(cold['dH_T_J_kg'])-abs(hot['dH_T_J_kg'])
total_gap = abs(cold['dH_total_J_kg'])-abs(hot['dH_total_J_kg'])
assert abs(temperature_only_gap-total_gap)<2 and total_gap>380

raw_dir = ROOT/'tmp/steady53_curves_20260828/results'
def series(filename):
    rows=[[float(x) for x in row] for row in csv.reader((raw_dir/filename).open())]
    assert len(rows)>2 and all(len(r)==2 for r in rows)
    assert rows[0][0]==0 and rows[-1][0]==14000
    assert all(b[0]>=a[0] for a,b in zip(rows,rows[1:]))
    return rows
turbine = series('baseline_WT_sw.csv')
compressor = series('baseline_Wc_sw.csv')
reactor = series('baseline_P_sw.csv')
assert [r[0] for r in turbine] == [r[0] for r in compressor] == [r[0] for r in reactor]
net_series = [a[1]-b[1] for a,b in zip(turbine,compressor)]
last_net = net_series[-1]/1000
eta_current = float(etas[0])
electrical = dict(source='Previously saved 14000 s baseline, NOT a new simulation.',
    final_time_s=turbine[-1][0],sample_count=len(turbine),
    turbine_final_kW=turbine[-1][1]/1000,compressor_final_kW=compressor[-1][1]/1000,
    reactor_final_kW=reactor[-1][1]/1000,shaft_net_final_kW=last_net,
    current_metric_eta=eta_current,paper_table31_eta=float(eta),
    current_synthesized_final_kWe=eta_current*last_net,
    paper_eta_postprocessed_final_kWe=float(eta)*last_net,
    current_metric_error_percent=100*(eta_current*last_net/float(pe)-1),
    paper_eta_metric_error_percent=100*(float(eta)*last_net/float(pe)-1),
    postprocess_difference_kW=(float(eta)-eta_current)*last_net,
    current_peak_to_peak_W=eta_current*(max(net_series)-min(net_series)),
    paper_eta_peak_to_peak_W=float(eta)*(max(net_series)-min(net_series)),
    source_runner_assignment_line=next(i for i,s in enumerate(text.splitlines(),1) if re.match(r'^\s*etaGenerator\s*=',s)))
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=active,text=True).strip()
archive=subprocess.check_output(['git','rev-parse','archive/pre-restart-20260824^{}'],cwd=ROOT,text=True).strip()
assert head=='f8bcd833e816eb681982b7dd04364e4b856948e3'
assert archive=='8f625c268c35a95c18a626305c1aa6a79ae2ace7'
files=[Path(__file__),runner,active/'tests/steady53/run_steady53_case.m',prior_file,
       raw_dir/'baseline.mat',raw_dir/'baseline_WT_sw.csv',raw_dir/'baseline_Wc_sw.csv',
       raw_dir/'baseline_P_sw.csv',protected_file,
       ROOT/'空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf']
files += sorted(run.glob('thesis-*.png'))
evidence=dict(date='2026-08-29',table52_simulation_column=table,
    source_pages={'table52':104,'table31_generator_efficiency':61,
                  'cp_average_definition':39,'cycle_equations':[39,40,41,42,44],
                  'rotor_equations':102,'steady_power_body':106},
    arithmetic=dict(shaft_net_kW=str(net),heat_difference_kW=str(qihx-qcool),
        heat_minus_shaft_kW=str(gap),nearest_rounding_gap_interval_kW=list(map(str,rounding_gap_interval)),
        paper_eta_times_net_kWe=str(eta*net),electric_table_minus_eta_times_net_kW=str(pe-eta*net),
        electric_over_IHX_percent=str(eta_electric_ihx),
        nearest_rounding_electric_over_IHX_interval_percent=list(map(str,electric_ihx_interval)),
        nearest_rounding_reported_efficiency_interval_percent=list(map(str,reported_eff_interval)),
        electric_over_body_reactor_percent=str(eta_electric_rx),
        body_reactor_nearest_rounding_interval_kW=list(map(str,body_reactor_rounding_interval)),
        heat_input_inferred_from_efficiency_kW=str(q_eff_inverse),
        body_reactor_minus_table_IHX_kW=str(D('2664')-qihx)),
    telescoping_identity=dict(statement='Q_IHX-Q_cooler-P_turbine+P_compressor = Q_RHX_hot-Q_RHX_cold',
        checked_state_coefficients=lhs,candidate_signed_recuperator_gap_kW=signed_recup_gap,
        table_and_candidate_residual_signs_opposite=True,
        candidate_temperature_only_specific_gap_J_kg=temperature_only_gap,
        candidate_full_specific_gap_J_kg=total_gap,
        pressure_correction_effect_J_kg=temperature_only_gap-total_gap),
    saved_baseline_postprocessing=electrical,active_head=head,archive=archive,
    source_hashes={str(f):sha(f) for f in files},protected_count=len(protected),
    no_property_evaluations=True,no_model_load_or_simulation=True,no_model_or_runner_edits=True,
    model_acceptance_passed=False,
    limitations=['Conditional simple-cycle identity; missing author implementation or power definitions can explain discrepancies.',
                 'Display rounding is not an uncertainty estimate or acceptance criterion.',
                 '0.98 is paper-direct in Chapter 3; Chapter 5 linkage is supported numerically, not author code.',
                 'The 2664.384656 kW denominator is inverse arithmetic, not a direct source value.',
                 'No new author-direct mass flow or final property repair is identified.',
                 'Postprocessing stored data does not improve or reproduce a cold-start trajectory.'])
output=run/'power_definition_audit.json'
if args.verify_only:
    assert json.loads(output.read_text())==evidence
else:
    with output.open('x') as f:
        json.dump(evidence,f,ensure_ascii=False,indent=2);f.write('\n')
print(json.dumps({k:v for k,v in evidence.items() if k!='source_hashes'},ensure_ascii=False,indent=2))
print('POWER_DEFINITION_AUDIT_PASS; PROTECTED=34; NO_FORMAL_CHANGE')
