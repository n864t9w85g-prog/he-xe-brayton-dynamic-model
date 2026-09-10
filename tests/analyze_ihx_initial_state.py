"""Plot the declared 1200 K diagnostic against original scan samples, no fit."""
from pathlib import Path
import csv
import hashlib
import json
import argparse
import numpy as np
from PIL import Image
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

REPO = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('run_directory', type=Path)
args = parser.parse_args()
run = args.run_directory.resolve()
assert run.is_relative_to((REPO/'tmp').resolve()), 'Exploration results only.'
out = run/'analysis'
out.mkdir(exist_ok=False)
scan = REPO/'tmp/steady53_recheck_20260827/paper-105.png'
# Binding source hash; no scan resampling or image editing.
actual = hashlib.sha256(scan.read_bytes()).hexdigest()
provenance = json.loads((REPO/'tmp/steady53_curves_20260828/radiator_scan_provenance.json').read_text())
assert actual == provenance['sha256']
pixels = np.asarray(Image.open(scan).convert('L'))
points = []
for x in [182, 185, 190, 198, 210, 230, 260, 300, 360]:
    yy = np.flatnonzero(pixels[380:610, x] < 140)+380
    groups = [g for g in np.split(yy, np.flatnonzero(np.diff(yy)>1)+1) if len(g)]
    assert len(groups) == 3, (x, groups)
    yc, yw, yh = [float(g.mean()) for g in groups]
    T = lambda y: 1500.+(418.-y)*100./69.
    points.append(dict(x_px=x, cold_y_px=yc, wall_y_px=yw, hot_y_px=yh,
        time_s=(x-173.)*300./328., cold_K=T(yc), wall_K=T(yw), hot_K=T(yh)))
with (out/'paper_ihx_points.csv').open('w', newline='') as stream:
    writer = csv.DictWriter(stream, fieldnames=points[0].keys())
    writer.writeheader(); writer.writerows(points)

def read(name):
    a = np.loadtxt(run/(name+'.csv'), delimiter=',', ndmin=2)
    assert a.shape[1] == 2 and np.isfinite(a).all()
    assert a[0,0] == 0 and a[-1,0] == 500 and np.all(np.diff(a[:,0]) >= 0)
    a = a[np.r_[np.diff(a[:,0]) != 0, True]]
    return a[:,0], a[:,1]

def stats(t, y):
    bad = np.flatnonzero(abs(y-y[-1])>.01*abs(y[-1]))
    bracket = t[bad[-1]:bad[-1]+2].tolist() if len(bad) else [0., 0.]
    return dict(initial_K=float(y[0]), final_K=float(y[-1]),
        min_K=float(y.min()), min_time_s=float(t[y.argmin()]),
        max_K=float(y.max()), at50_K=float(np.interp(50., t, y)),
        settling_own_final_1pct_sample_bracket_s=bracket)

series = dict(hot=read('y_001'), cold=read('y_003'))
t1, y1 = read('state_05'); t2, y2 = read('state_10')
series['wall'] = (t1, .5*(y1+np.interp(t1, t2, y2)))
metrics = {name: stats(t, y) for name, (t, y) in series.items()}
metrics.update(source_image_sha256=actual, PDF_page=105, printed_page=90,
    figure='5.18(a)', axis_calibration=dict(x0_px=173, x300_px=501, y1500_px=418, y1400_px=487),
    reading_allowance='Approximate +/-3 K, +/-2 s; not a new acceptance tolerance.',
    initial_state_status='All ten thermal states =1200 K, diagnostic assumption, not a verified thesis initial state.',
    wall_status='Arithmetic average of two model wall states; NOT verified as identical to the thesis single structural temperature.',
    settling_status='Bracket to own final +/-1%, not formal thesis acceptance; trajectory mismatch retained.')
(out/'metrics.json').write_text(json.dumps(metrics, indent=2)+'\n')
fig, axes = plt.subplots(1, 2, figsize=(14, 5.5), layout='constrained')
colors = dict(cold='tab:blue', hot='tab:red', wall='tab:gray')
labels = dict(cold='Cold outlet', hot='Hot outlet', wall='Two-wall mean (mapping unverified)')
for ax, end in zip(axes, [300, 50]):
    for name, (t, y) in series.items():
        ax.plot(t, y, color=colors[name], lw=1.4, label='Model: '+labels[name])
        ax.errorbar([p['time_s'] for p in points], [p[name+'_K'] for p in points],
            yerr=3, xerr=2, fmt='o', ms=3, capsize=2, color=colors[name],
            mfc='white', label='Original scan: '+('Structure' if name=='wall' else labels[name]))
    ax.set(xlim=(0, end), ylim=(1130, 1570), xlabel='Time (s)', ylabel='Temperature (K)',
           title='Full window' if end==300 else 'Early transient: undershoot is retained')
    ax.grid(alpha=.2)
axes[0].legend(loc='lower right', fontsize=7)
fig.suptitle('IHX: same coefficients and fixed boundaries; only ten initial temperatures set to 1200 K\n'
             'Diagnostic hypothesis, NOT the known paper initial state; no fitting, time shift or filtering', fontsize=12)
fig.savefig(out/'ihx_original_vs_initial1200.png', dpi=160)
plt.close(fig)
print(json.dumps(dict(output=str(out), metrics=metrics), indent=2))
