"""Audit recorded IHX heat allocation; no model edits or fitted coefficients."""
import argparse
import hashlib
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

REPO = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("run_directory", type=Path)
args = parser.parse_args()
run = args.run_directory.resolve()
assert run.is_relative_to((REPO / "tmp").resolve())
assert "COMPLETE_DIAGNOSTIC_ONLY" in (run / "diary.txt").read_text()
names = [f"state_{k:02}" for k in range(1, 11)] + [
    "advective_out_W", "allocated_out_loss_W", "dTh2_K_s", "cp_hot", "Q_h",
    "y_001", "y_003",
]
cases = {}
hashes = {}
for case in ("delta_0", "delta_4"):
    arrays = {}
    for name in names:
        path = run / case / (name + ".csv")
        a = np.loadtxt(path, delimiter=",", ndmin=2)
        assert a.shape[1] == 2 and np.isfinite(a).all()
        assert a[0, 0] == 0 and a[-1, 0] == 2 and np.all(np.diff(a[:, 0]) >= 0)
        arrays[name] = a
        hashes[f"{case}/{path.name}"] = hashlib.sha256(path.read_bytes()).hexdigest()
    t = arrays["state_04"][:, 0]
    assert all(np.array_equal(a[:, 0], t) for a in arrays.values())
    cases[case] = (t, {name: a[:, 1] for name, a in arrays.items()})

control_t, control = cases["delta_0"]
t, s = cases["delta_4"]
drift = max(float(np.max(np.abs(control[f"state_{k:02}"] - 1200))) for k in range(1, 11))
assert drift == 0, "The uniform-equilibrium control is not stationary."
# These coefficients are the inspected active region constants, not fit values.
m_hot = 0.6588
H = 10544 * 7.031
C = 4.572 * s["cp_hot"][0]
predicted_derivative = (s["advective_out_W"] - s["allocated_out_loss_W"]) / (.5 * m_hot * s["cp_hot"])
derivative_residual = float(np.max(np.abs(predicted_derivative - s["dTh2_K_s"])))
allocation_residual = float(np.max(np.abs(s["allocated_out_loss_W"] - .5 * s["Q_h"])))
assert derivative_residual < 1e-9 and allocation_residual < 1e-6
index = int(np.argmin(s["state_04"]))
assert s["state_04"][index] < 1199, "The diagnosed excursion is not reproduced in these data."
# Audit a recorded sample, not a derivative of an interpolated/digitized curve.
j = int(np.argmin(np.abs(t - .05)))
assert s["state_04"][j] < s["state_05"][j]
assert s["allocated_out_loss_W"][j] > s["advective_out_W"][j] > 0
assert s["dTh2_K_s"][j] < 0
metrics = dict(
    source_commit="f8bcd833e816eb681982b7dd04364e4b856948e3",
    source_model_sha256="0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391",
    control_max_absolute_drift_K=drift,
    region1_hot_out_min_K=float(s["state_04"][index]),
    region1_hot_out_min_sample_time_s=float(t[index]),
    H_W_K=H, C_W_K=float(C), H_over_2C=float(H / (2 * C)),
    cross_coefficient_per_s=float((2 * C - H) / (m_hot * s["cp_hot"][0])),
    max_derivative_balance_residual_K_s=derivative_residual,
    max_half_heat_allocation_residual_W=allocation_residual,
    recorded_sample=dict(time_s=float(t[j]), **{name: float(s[name][j]) for name in names}),
    numerical_settings=dict(RelTol=1e-7, AbsTol=1e-9, MaxStep_s=.002, StopTime_s=2),
    scope="Controlled diagnostic, not a thesis startup or acceptance test. Minima are recorded samples. No physical correction has been applied.",
    inputs_sha256=hashes,
)
out = run / "analysis"
out.mkdir(exist_ok=False)
(out / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
fig, axes = plt.subplots(1, 2, figsize=(12.8, 5), layout="constrained")
ax = axes[0]
ax.plot(control_t, control["state_04"] - 1200, "k--", label="Control: both inlets 1200 K")
for name, label, color in [
    ("state_03", "Hot first state", "tab:orange"),
    ("state_04", "Hot outlet state", "tab:red"),
    ("state_05", "Wall state", "tab:gray"),
]:
    ax.plot(t, s[name] - 1200, label="+4 K inlet: " + label, color=color)
ax.plot(t[index], s["state_04"][index] - 1200, "o", color="tab:red")
ax.annotate(f"{s['state_04'][index]:.3f} K at {t[index]:.3f} s",
            (t[index], s["state_04"][index] - 1200), xytext=(.39, -.85),
            arrowprops=dict(arrowstyle="->", color="tab:red"), fontsize=9)
ax.set(xlim=(0, .8), xlabel="Time (s)", ylabel="Temperature minus 1200 K (K)",
       title="Region 1: outlet cools despite a warmer inlet")
ax.legend(fontsize=8, loc="upper left")
ax = axes[1]
ax.plot(t, s["advective_out_W"] / 1000, label="Advection into outlet cell", color="tab:blue")
ax.plot(t, s["allocated_out_loss_W"] / 1000, label="Assigned outlet heat loss: Qh / 2", color="tab:orange")
ax.plot(t, (s["advective_out_W"] - s["allocated_out_loss_W"]) / 1000,
        label="Net outlet heating", color="tab:red")
ax.axhline(0, color="black", lw=.6)
ax.set(xlim=(0, .4), xlabel="Time (s)", ylabel="Thermal power (kW)",
       title="Same recorded run: heat-allocation explanation")
ax.legend(fontsize=8, loc="center right")
for ax in axes:
    ax.grid(alpha=.2)
fig.suptitle("IHX diagnostic: all 10 initial states 1200 K; hot inlet 1200 vs 1204 K\n"
             "Unchanged source equations and physical coefficients; not a thesis reproduction", fontsize=11)
fig.savefig(out / "ihx_uniform_step_audit.png", dpi=160)
plt.close(fig)
print(json.dumps({k: v for k, v in metrics.items() if k != "inputs_sha256"}, indent=2))
print("OUTPUT=" + str(out))
