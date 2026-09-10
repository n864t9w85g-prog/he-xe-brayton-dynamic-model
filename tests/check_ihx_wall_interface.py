"""Read-only wall-interface algebra and source trace; no adopted physics patch.

No MATLAB, SLX load/sim/save, curve fitting, or property changes. XML is read
only. Same-U alternatives below are identifiability counterexamples, not
candidate parameters. All generated evidence goes to a fresh tmp directory.
"""
import csv
from decimal import Decimal, localcontext
from fractions import Fraction as F
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def trace_wall(root):
    blocks = {b.get('SID'): b for b in root.findall('Block')}
    params = {sid: {p.get('Name'): p.text for p in b.findall('P')}
              for sid, b in blocks.items()}
    named = {b.get('Name'): sid for sid, b in blocks.items()}
    incoming = {}
    for line in root.findall('Line'):
        src = next(p.text for p in line.findall('P') if p.get('Name') == 'Src')
        for p in line.iter('P'):
            if p.get('Name') == 'Dst':
                assert p.text not in incoming
                incoming[p.text] = src.split('#')[0]
    gotos = {params[s]['GotoTag']: s for s, b in blocks.items()
             if b.get('BlockType') == 'Goto'}
    visited = set()

    def source(sid, port=1):
        return incoming[f'{sid}#in:{port}']

    def expression(sid):
        visited.add(sid)
        b, p = blocks[sid], params[sid]
        kind, name = b.get('BlockType'), b.get('Name')
        if kind == 'Integrator':
            return name
        if kind == 'Constant':
            return f"{name}={p['Value']}"
        if kind == 'From':
            return expression(source(gotos[p['GotoTag']]))
        if kind == 'Lookup_n-D':
            return f'{name}({expression(source(sid))})'
        ports = int(b.find('PortCounts').get('in'))
        args = [expression(source(sid, n)) for n in range(1, ports+1)]
        if kind == 'Sum':
            signs = p['Inputs'].replace('|', '')
            assert len(signs) == ports
            return '(' + ''.join(s+a for s, a in zip(signs, args)) + ')'
        if kind == 'Product':
            signs = p.get('Inputs', '*'*ports)
            if signs.isdigit():
                signs = '*'*ports
            assert len(signs) == ports
            return '(1' + ''.join(s+'('+a+')' for s, a in zip(signs, args)) + ')'
        raise AssertionError(f'Unhandled block in wall path: {sid} {name} {kind}')

    result = {name: expression(named[name]) for name in ('Q_h', 'Q_c', 'C_wall')}
    result['dT_wall_dt'] = expression(source(named['T_wall_Integrator']))
    allowed = {'Constant', 'From', 'Sum', 'Product', 'Integrator', 'Lookup_n-D'}
    assert {blocks[s].get('BlockType') for s in visited} <= allowed
    assert {blocks[s].get('Name') for s in visited if blocks[s].get('BlockType') == 'Constant'} == {
        'A_region', 'A_region2', 'h_Li', 'h_HeXe', 'm_wall_region'}
    assert {blocks[s].get('Name') for s in visited if blocks[s].get('BlockType') == 'Lookup_n-D'} == {'cp_wall_lookup'}
    result['visited_SIDs'] = sorted(visited, key=int)
    return result, {name: params[sid] for name, sid in named.items()}


def main():
    repo = Path(__file__).resolve().parents[1]
    active = repo.parent/(repo.name+'_副本')
    slx = active/'final_steady_24a.slx'
    manifest = repo/'tmp/tp80484fa0_602f_4386_89ed_ae9ca96b3359/protected_after.csv'
    with manifest.open() as f:
        protected = list(csv.DictReader(f))
    assert len(protected) == 34
    for p in protected:
        assert digest(Path(p['paths'])) == p['hashes'], p['paths']
    assert digest(slx) == '0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391'
    traces, inventories = {}, []
    with zipfile.ZipFile(slx) as z:
        for part in ('278', '388'):
            traces[part], inv = trace_wall(ET.fromstring(z.read(f'simulink/systems/system_{part}.xml')))
            inventories.append(inv)
    inv = inventories[0]
    for name in ('h_Li', 'h_HeXe', 'A_region', 'A_region2', 'm_wall_region'):
        assert inv[name]['Value'] == inventories[1][name]['Value']
    hh, hc, ar, mr = [float(inv[n]['Value']) for n in ('h_Li', 'h_HeXe', 'A_region', 'm_wall_region')]
    assert ar == 7.031 and mr == 162.5 and hh == 10544 and hc == 1171.6
    lookup = inv['cp_wall_lookup']
    numeric = lambda text: [float(v) for v in re.findall(r'-?\d+(?:\.\d+)?', text)]
    bp, cp = numeric(lookup['BreakpointsForDimension1']), numeric(lookup['Table'])
    t0 = 1200.
    i = next(i for i in range(len(bp)-1) if bp[i] <= t0 <= bp[i+1])
    cp0 = cp[i]+(cp[i+1]-cp[i])*(t0-bp[i])/(bp[i+1]-bp[i])
    area, capacity = 2*ar, 2*mr*cp0
    u = 1/(1/hh+1/hc)
    original_alpha = (1/hh)/(1/u)
    bulk_hot, bulk_cold = (1600+1443.27)/2, (1100.91+1522.96)/2
    # Thesis Table5.2, not the old 2653 kW/1442/1099/1522 calibration point.
    # Both coefficients below are inversions for an equivalence check ONLY.
    delta1, delta2 = 1600-1522.96, 1443.27-1100.91
    lmtd = (delta2-delta1)/math.log(delta2/delta1)
    amtd = bulk_hot-bulk_cold
    q_paper = 2647180.
    u_lm = q_paper/(area*lmtd)
    u_am = q_paper/(area*amtd)
    with localcontext() as context:
        context.prec = 60
        a, b = Decimal('77.04'), Decimal('342.36')
        lm_decimal = (b-a)/(b/a).ln()
        assert math.isclose(lmtd, float(lm_decimal), rel_tol=1e-14)
        assert math.isclose(amtd, float((a+b)/2), rel_tol=1e-14)
    assert math.isclose(amtd, (delta1+delta2)/2, rel_tol=1e-14)
    assert amtd > lmtd and u_lm > u_am
    mean_temperature_check = dict(
        scope='Whole-component single-wall Eq5.12-14 steady limit; NOT the active two-region SLX result.',
        Q_table52_W=q_paper, delta1_K=delta1, delta2_K=delta2,
        log_mean_delta_K=lmtd, arithmetic_mean_delta_K=amtd,
        U_backcalculated_LMTD_W_m2K=u_lm, U_backcalculated_AMTD_W_m2K=u_am,
        Q_if_U_LMTD_used_with_AMTD_W=u_lm*area*amtd,
        Q_if_current_pair_used_with_AMTD_W=u*area*amtd,
        U_LMTD_with_AMTD_relative_excess=amtd/lmtd-1,
        LMTD_over_AMTD_not_a_patch=lmtd/amtd,
        interpretation='Equality of serial resistances alone does not equate LMTD with endpoint arithmetic-mean driving temperature. No inferred U or ratio is applied.')
    # Positive, normalized resistances, not real material data or a fit.
    exact_tests = []
    rh, rc, rw = F(1), F(2), F(3)
    for theta in (F(0), F(1, 2), F(1)):
        gh, gc = 1/(rh+theta*rw), 1/(rc+(1-theta)*rw)
        assert 1/gh+1/gc == rh+rw+rc
        assert 1/(1/gh+1/gc) == F(1, 6)
        exact_tests.append({'wall_resistance_fraction': str(theta), 'series_identity': True})
    assert 1/(rh+rc) != 1/(rh+rc+rw)   # omit finite wall resistance
    assert rh+rw+rc+rw != rh+rw+rc      # count the wall resistance twice
    rows = []
    for label, alpha in [('existing_pair', original_alpha),
                          ('same_U_50_50_non_candidate_counterexample', .5)]:
        gh, gc = u/alpha, u/(1-alpha)
        tw = (gh*bulk_hot+gc*bulk_cold)/(gh+gc)
        tau = capacity/(area*(gh+gc))
        q = area*u*(bulk_hot-bulk_cold)
        assert math.isclose(gh*area*(bulk_hot-tw), q, rel_tol=1e-12)
        assert math.isclose(gc*area*(tw-bulk_cold), q, rel_tol=1e-12)
        assert math.isclose(tau, capacity*alpha*(1-alpha)/(area*u), rel_tol=1e-13)
        # Analytic fixed-bulk, constant-cp wall response; no ODE solver used.
        samples = []
        for time in (0., 1., 2., 5., 10.):
            temperature = tw+(t0-tw)*math.exp(-time/tau)
            derivative = (tw-t0)*math.exp(-time/tau)/tau
            qh, qc = area*gh*(bulk_hot-temperature), area*gc*(temperature-bulk_cold)
            assert abs(capacity*derivative-(qh-qc)) < 1e-6
            samples.append(dict(t_s=time, T_wall_K=temperature))
        rows.append(dict(label=label, U_W_m2K=u, total_hot_resistance_fraction=alpha,
                         gh_W_m2K=gh, gc_W_m2K=gc, Q_fixed_bulk_W=q,
                         wall_equilibrium_K=tw, fixed_bulk_tau_s=tau, analytic_samples=samples))
    assert math.isclose(rows[0]['Q_fixed_bulk_W'], rows[1]['Q_fixed_bulk_W'])
    assert not math.isclose(rows[0]['wall_equilibrium_K'], rows[1]['wall_equilibrium_K'])
    assert not math.isclose(rows[0]['fixed_bulk_tau_s'], rows[1]['fixed_bulk_tau_s'])
    head = subprocess.check_output(['git','-C',str(active),'rev-parse','HEAD'],text=True).strip()
    assert head == 'f8bcd833e816eb681982b7dd04364e4b856948e3'
    archive = subprocess.check_output(['git','rev-parse','archive/pre-restart-20260824^{}'],cwd=repo,text=True).strip()
    assert archive == '8f625c268c35a95c18a626305c1aa6a79ae2ace7'
    files = [Path(__file__), slx, manifest,
             repo/'空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf']
    result = dict(
        scope='Read-only trace and algebra. Same-U 50/50 is NOT an authorized candidate or fit.',
        traces=traces, exact_normalized_interface_tests=exact_tests,
        mean_temperature_interface=mean_temperature_check,
        frozen_inputs=dict(hot_mean_K=bulk_hot,cold_mean_K=bulk_cold,initial_wall_K=t0,
                           cp_wall_frozen_at_1200_J_kgK=cp0,wall_capacity_J_K=capacity,area_m2=area),
        non_identifiability_counterexample=rows,
        tau_ratio_counterexample_over_existing=rows[1]['fixed_bulk_tau_s']/rows[0]['fixed_bulk_tau_s'],
        limits=[
            'Bulk means clamped at table5.2 arithmetic means: NOT a complete IHX trajectory.',
            'Frozen cp_wall at 1200 K is a diagnostic simplification, not a property change.',
            'No h, U, wall resistance, split, wall k or geometry is fitted to the thesis.',
            'Steady resistance equivalence does not establish exact transient equivalence.',
            'Single structural wall temperature is not proven to be a physical face/midplane/volume mean.',
            'No explicit wall k/delta in the traced path does not disprove an implicit coefficient interpretation.',
        ],
        source_hashes={str(p):digest(p) for p in files},active_head=head,archive=archive,
        protected_unchanged=len(protected))
    for p in protected:
        assert digest(Path(p['paths'])) == p['hashes'], p['paths']
    out = Path(tempfile.mkdtemp(prefix='ihx_wall_interface_',dir=repo/'tmp'))
    (out/'evidence.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(dict(traces=traces,rows=rows,mean_temperature=mean_temperature_check,
                         tau_ratio=result['tau_ratio_counterexample_over_existing']),ensure_ascii=False,indent=2))
    print('WALL_INTERFACE_AND_SAME_U_COUNTEREXAMPLE_PASS; PROTECTED_UNCHANGED=34; NO_SIMULATION')
    print('OUTPUT_DIRECTORY='+str(out))


if __name__ == '__main__':
    main()
