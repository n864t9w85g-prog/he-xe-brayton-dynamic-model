"""Independent CSV checks and Fig5.18(a) overlay for the offline mean test."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('run_directory', type=Path)
run = parser.parse_args().run_directory.resolve()
repo = Path(__file__).resolve().parents[1]
assert run.is_relative_to(repo/'tmp')
digest = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert 'IHX_MEAN_STATE_DIAGNOSTIC_COMPLETE_500S; PROTECTED=34' in (run/'diary.txt').read_text()
summary = json.loads((run/'summary.json').read_text())
assert len(summary['metrics']) == 4
prior = repo/'tmp/tp80484fa0_602f_4386_89ed_ae9ca96b3359'
prior_manifest = json.loads((prior/'analysis/metrics.json').read_text())
for name, h in prior_manifest['input_hashes'].items():
    if name.startswith('original_500/'):
        assert digest(prior/name) == h, name
prior_verification = json.loads((prior/'original_500/verification.json').read_text())
assert prior_verification['final_time'] == 500
assert digest(prior_verification['model_file']) == prior_verification['model_sha256']
with (run/'prior_input_hashes.csv').open() as f:
    for row in csv.DictReader(f):
        assert digest(row['replayPaths']) == row['replayHashes']
with (run/'protected_after.csv').open() as f:
    protected = list(csv.DictReader(f))
assert len(protected) == 34
for row in protected:
    assert digest(row['paths']) == row['hashes'], row['paths']

points = repo/'tmp/tpf255e6c2_bcc0_4262_883f_5caf6d3f6a0d/analysis/paper_ihx_points.csv'
scan = repo/'tmp/steady53_recheck_20260827/paper-105.png'
provenance = json.loads(points.with_name('metrics.json').read_text())
assert digest(scan) == provenance['source_image_sha256']
assert digest(points) == prior_manifest['paper_samples_sha256']
paper = np.genfromtxt(points, delimiter=',', names=True)
p = summary['parameters']
names = ['original_replay', 'original_consistent_initial', 'literal_mean', 'literal_tighter']
data, metrics, checks = {}, {}, {}
for name in names:
    states = np.loadtxt(run/(name+'_states.csv'), delimiter=',')
    outputs = np.loadtxt(run/(name+'_outputs.csv'), delimiter=',')
    assert np.array_equal(states[:, 0], outputs[:, 0])
    t, s, v = outputs[:, 0], states[:, 1:], outputs[:, 1:]
    assert t[0] == 0 and t[-1] == 500 and np.all(np.diff(t) > 0)
    assert np.isfinite(outputs).all()
    data[name] = outputs
    means = s[:, [1,4]] if name.startswith('literal') else s[:, [2,7]]
    coldmeans = s[:, [0,3]] if name.startswith('literal') else s[:, [0,5]]
    wall = s[:, [2,5]] if name.startswith('literal') else s[:, [4,9]]
    qh = p['hh']*p['A']*(means-wall)
    qc = p['hc']*p['A']*(wall-coldmeans)
    np.testing.assert_allclose(qh, v[:, [6,8]], atol=2e-6, rtol=0)
    np.testing.assert_allclose(qc, v[:, [7,9]], atol=2e-6, rtol=0)
    metrics[name] = {}
    for label, col in [('hot',2),('cold',3)]:
        y = outputs[:, col]
        difference = np.interp(paper['time_s'], t, y) - paper[label+'_K']
        metrics[name][label] = dict(final_K=float(y[-1]), min_K=float(y.min()),
            time_of_min_s=float(t[np.argmin(y)]), at50_K=float(np.interp(50,t,y)),
            sample_rmse_K=float(np.sqrt(np.mean(difference**2))),
            sample_max_abs_difference_K=float(np.max(np.abs(difference))),
            final_minus_last_paper_sample_K=float(y[-1]-paper[label+'_K'][-1]))
    metrics[name]['wall1_final_K'] = float(v[-1,4])
    metrics[name]['wall2_final_K'] = float(v[-1,5])
    if name.startswith('literal'):
        hin = np.column_stack((np.full(len(t),p['Thi']),v[:,0]))
        cin = np.column_stack((v[:,3],np.full(len(t),p['Tci'])))
        mean_error = max(np.max(abs(2*means-hin-v[:,:2])),
                         np.max(abs(2*coldmeans-cin-v[:,2:4])))
        assert mean_error < 2e-10
        # Independent integral check for the variable-cp hot mean states.
        # cp is reproduced from the unchanged formal formula, not fitted.
        cp = .9615*1000*(104400/means**2-135.1/means+4.180)
        power = p['mhFlow']*cp*(hin-v[:,:2])-qh
        dt = np.diff(t)[:,None]
        accumulated = np.vstack((np.zeros((1,2)),np.cumsum(dt*(power[:-1]+power[1:])/2,axis=0)))
        primitive = lambda x: .9615*1000*(-104400/x-135.1*np.log(x)+4.180*x)
        storage = p['mh']*(primitive(means)-primitive(means[0]))
        integral_error = np.max(abs(accumulated-storage),axis=0)
        integral_relative = integral_error/np.max(abs(storage),axis=0)
        assert np.max(integral_relative) < 5e-4
        checks[name] = dict(endpoint_mean_identity_max_error_K=float(mean_error),
            hot_integral_storage_max_error_J=integral_error.tolist(),
            hot_integral_relative_error=integral_relative.tolist())

# Tighter integration must reproduce the exported physical outputs as well.
refinement = float(np.max(abs(data['literal_mean'][:,1:7]-data['literal_tighter'][:,1:7])))
assert refinement < .002
active = repo.parent/(repo.name+'_副本')
head = subprocess.check_output(['git','-C',str(active),'rev-parse','HEAD'],text=True).strip()
archive = subprocess.check_output(['git','rev-parse','archive/pre-restart-20260824^{}'],cwd=repo,text=True).strip()
assert head == 'f8bcd833e816eb681982b7dd04364e4b856948e3'
assert archive == '8f625c268c35a95c18a626305c1aa6a79ae2ace7'
out = Path(tempfile.mkdtemp(prefix='analysis_',dir=run))
fig, axes = plt.subplots(2,2,figsize=(12.4,8.8),layout='constrained')
style = [('original_replay','Original: all states 1200 K','#686868','--'),
         ('original_consistent_initial','Original: consistent mean IC','#d18a12',':'),
         ('literal_mean','Literal endpoint-mean equations','#226daf','-')]
for ax, label, col, title in [(axes[0,0],'hot',2,'Whole IHX hot outlet'),
                             (axes[0,1],'cold',3,'Whole IHX cold outlet')]:
    for name, legend, color, line in style:
        a = data[name]
        ax.plot(a[:,0],a[:,col],line,color=color,lw=1.8,label=legend)
    ax.errorbar(paper['time_s'],paper[label+'_K'],xerr=2,yerr=3,fmt='o',
                color='black',mfc='white',ms=4,capsize=2,label='Thesis scan samples')
    ax.set(xlim=(0,70),xlabel='Time (s)',ylabel='Temperature (K)',title=title)
    ax.grid(alpha=.2)
axes[0,0].legend(fontsize=8,loc='lower right')
ax = axes[1,0]
for name, line, label in [('original_replay','--','Original'),('literal_mean','-','Literal')]:
    a = data[name]
    for col,color,r in [(5,'#8057a0',1),(6,'#2a9672',2)]:
        ax.plot(a[:,0],a[:,col],line,color=color,lw=1.5,label=f'{label}: wall {r}')
ax.errorbar(paper['time_s'],paper['wall_K'],xerr=2,yerr=3,fmt='o',color='black',
            mfc='white',ms=4,capsize=2,label='Thesis wall (mapping unresolved)')
ax.set(xlim=(0,70),xlabel='Time (s)',ylabel='Temperature (K)',title='Both wall states shown; no averaging to fit')
ax.grid(alpha=.2); ax.legend(fontsize=7.5,loc='lower right')
ax = axes[1,1]
for name,label,color,line in style:
    a = data[name]
    ax.plot(a[:,0],a[:,2],line,color=color,lw=1.8,label=label)
ax.axhline(1200,color='#777777',lw=.8)
ax.set(xlim=(0,5),xlabel='Time (s)',ylabel='Hot outlet temperature (K)',title='Initial hot-outlet reversal remains')
ax.grid(alpha=.2); ax.legend(fontsize=8,loc='lower right')
fig.suptitle('IHX at the existing thesis boundary: 500 s offline equation integrations\n'
             'Unchanged h, mass, properties and pressure routing; no time shift or curve fit',fontsize=12)
fig.savefig(out/'mean_state_vs_paper.png',dpi=180); plt.close(fig)
sources = [Path(__file__),repo/'tests/run_ihx_mean_state_diagnostic.m',run/'summary.json',
           points,scan,prior/'analysis/metrics.json',prior/'original_500/verification.json']
sources += list(run.glob('*.csv'))
report = dict(comparison=metrics,checks=checks,output_refinement_max_error_K=refinement,
    source_hashes={str(f):digest(f) for f in sources},
    plot_sha256=digest(out/'mean_state_vs_paper.png'),active_head=head,archive=archive,
    scope='Offline ODE diagnostic, not a fresh SLX run, promoted model or acceptance pass.',
    paper_reading_uncertainty='Approximately +/-3 K, +/-2 s, not a formal threshold.',
    wall_mapping='No unique mapping from two walls to thesis T_IHX is claimed.',
    initialization='Consistent original control matches literal mean/outlet/wall initial values; storage definitions still differ.')
(out/'evidence.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(dict(output=str(out),metrics=metrics,checks=checks,
    output_refinement_max_error_K=refinement,evidence_sha256=digest(out/'evidence.json')),indent=2))
print('MEAN_STATE_CSV_AND_PAPER_OVERLAY_CHECKS_PASS; PROTECTED_UNCHANGED=34')
