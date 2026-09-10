"""Verify the offline IHX energy audit and display its read-off intervals."""
import argparse
import hashlib
import json
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("run_directory", type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
run = args.run_directory.resolve()
assert run.is_relative_to(repo / "tmp")
assert "READ_ONLY_PROPERTY_AUDIT_COMPLETE_NO_SLX_LOADED" in (run / "diary.txt").read_text()
data = json.loads((run / "boundary_energy.json").read_text())
cases = {c["name"]: c for c in data["cases"]}
assert data["Li_integral_analytic_residual_J_kg"] < 1e-6
assert max(data["pressure_FD_corrections_W"]) - min(data["pressure_FD_corrections_W"]) < 1e-4
for name in ("original_500_end", "candidate_500_end"):
    assert abs(cases[name]["gap_W"]) < 25, "Check did not retain the near-closed model endpoint controls."
b = data["scan_outlet_only_Q_bounds_W"]
assert b["hot"][0] > b["cold"][1]
assert abs(b["minimum_gap"] - (b["hot"][0] - b["cold"][1])) < 1e-6
table = cases["table5_2"]
assert table["gap_W"] > 200e3
assert abs(table["cold_pressure_correction_W"]) < 20
# Independent Python antiderivative of the inspected active Li cp correlation.
from math import log
F = lambda t: .9615 * 1000 * (-1.044e5/t - 135.1*log(t) + 4.180*t)
q = data["inputs"]["mdot_h"] * (F(data["inputs"]["T_hi"]) - F(table["T_ho_K"]))
assert abs(q - table["hot_Q_W"]) < 1e-5
out = run / "energy_bounds.png"
assert not out.exists(), "Refuse to overwrite earlier evidence."
fig, ax = plt.subplots(figsize=(10, 4.6), layout="constrained")
for y, key, title, color in [(1, "hot", "Li heat released", "tab:red"),
                             (0, "cold", "He-Xe heat absorbed", "tab:blue")]:
    lo, hi = [v/1000 for v in b[key]]
    midpoint = cases["figure5_18_last_sample"]["hot_Q_W" if key == "hot" else "cold_Q_pressure_path_W"]/1000
    ax.hlines(y, lo, hi, color=color, lw=8, alpha=.6)
    ax.plot(midpoint, y, "o", color=color)
    ax.text((lo+hi)/2, y+.13, f"{lo:.2f} to {hi:.2f} kW", ha="center", fontsize=10)
ax.axvline(data["inputs"]["IHX_table_power_W"]/1000, color="black", ls="--",
           label="Table 5.2 IHX duty: 2647.18 kW")
ax.annotate("Minimum gap: 128.40 kW", xy=(b["cold"][1]/1000, .5),
            xytext=(b["hot"][0]/1000, .5), va="center", ha="left",
            arrowprops=dict(arrowstyle="<->"), fontsize=10)
ax.set(yticks=[0, 1], yticklabels=["He-Xe side", "Li side"], ylim=(-.35, 1.45),
       xlim=(2585, 2980), xlabel="Steady heat rate (kW)",
       title="IHX figure endpoints with +/-3 K read-off allowance do not close\n"
             "Conditional on current fixed inlets, mass flows and property functions")
ax.grid(axis="x", alpha=.2); ax.legend(loc="lower right", fontsize=9)
fig.savefig(out, dpi=160); plt.close(fig)
print("PASS: Li analytic integral, finite-difference sensitivity, endpoint controls, and interval separation.")
print("No model changes. Source JSON SHA256:", hashlib.sha256((run/"boundary_energy.json").read_bytes()).hexdigest())
print("OUTPUT:", out)
