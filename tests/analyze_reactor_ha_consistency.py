"""Audit and plot completed reactor hA-only experiments, never edit models."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import subprocess

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

REPO = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("run_directory", type=Path)
args = parser.parse_args()
run = args.run_directory.resolve()
assert run.is_relative_to(REPO / "tmp")
assert "TWO_REACTOR_CASES_COMPLETE_FORMAL_FILES_UNCHANGED_NOT_THESIS_ACCEPTANCE" in (run / "diary.txt").read_text()


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def params(inv):
    return {r["key"]: r["value"] for r in inv["parameters"]}


def parameter(p, name):
    return float(json.loads(p["/DUT/" + name + "|Value"]))


assert (run / "protected_before.csv").read_bytes() == (run / "protected_after.csv").read_bytes()
with (run / "protected_after.csv").open() as f:
    protected = list(csv.DictReader(f))
for row in protected:
    assert sha(row["paths"]) == row["hashes"], row["paths"]

inventories = {c: json.loads((run / c / "inventory.json").read_text()) for c in ("original", "candidate")}
old, new = [inventories[c]["after"] for c in ("original", "candidate")]
assert old["blocks"] == new["blocks"] and old["edges"] == new["edges"]
p0, p1 = params(old), params(new)
assert p0.keys() == p1.keys()
changes = [{"key": k, "before": p0[k], "after": p1[k]} for k in p0 if p0[k] != p1[k]]
assert [d["key"] for d in changes] == ["/DUT/hA1|Value", "/DUT/hA2|Value"]
assert params(inventories["original"]["before"]) == p0
assert params(inventories["candidate"]["before"]) == p0

metrics, series, hashes = {}, {}, {}
for case, p in (("original", p0), ("candidate", p1)):
    summary_path = run / case / "summary.json"
    summary = json.loads(summary_path.read_text())
    csv_path = run / case / "signals.csv"
    assert sha(csv_path) == summary["signals_sha256"]
    assert sha(summary["model_path"]) == summary["model_sha256"]
    a = np.genfromtxt(csv_path, delimiter=",", names=True)
    assert all(np.isfinite(a[k]).all() for k in a.dtype.names)
    assert a["time_s"][0] == 0 and a["time_s"][-1] == 500
    assert (np.diff(a["time_s"]) > 0).all()
    kappa, gamma, ha = (parameter(p, n) for n in ("1//C_fuel", "gamma_f", "hA1"))
    assert ha == parameter(p, "hA2")
    assert np.all(a["kappa"] == kappa) and np.all(a["gamma"] == gamma)
    assert np.all(a["cp_J_kgK"] == parameter(p, "cp_Li"))
    assert np.all(a["mdot_kg_s"] == parameter(p, "Constant1"))
    residual = a["P_Rx_W"] - a["dTf_dt_K_s"] / kappa - a["mdot_kg_s"] * a["cp_J_kgK"] * (a["Tout_K"] - a["Tin_K"])
    max_residual = float(np.max(np.abs(residual)))
    assert (max_residual > 10000) if case == "original" else (max_residual < .001)
    fuel_error = a["P_Rx_W"] - a["dTf_dt_K_s"] / kappa - (gamma/kappa)*(a["Tf_K"]-(a["Tin_K"]+a["Tout_K"])/2)
    assert np.max(np.abs(fuel_error)) < .001

    # Independent stationary root of the unchanged zero-reactivity and
    # fuel-transfer equations, using exported active block constants.
    af, ac, tf_ref, ta_ref = (parameter(p, n) for n in ("alphaf", "alphac", "To", "T_average"))
    ti = float(a["Tin_K"][0])
    assert np.all(a["Tin_K"] == ti)
    capacity_flow = float(a["mdot_kg_s"][0] * a["cp_J_kgK"][0])
    ratio = 2*ha/(2*capacity_flow+ha)
    gap = (af*(tf_ref-ti)+ac*(ta_ref-ti))/(af+ac*ratio/2)
    tf_root, to_root = ti+gap, ti+ratio*gap
    power_root = (gamma/kappa)*(tf_root-(ti+to_root)/2)
    assert abs(af*(tf_root-tf_ref)+ac*((ti+to_root)/2-ta_ref)) < 1e-12
    assert abs(float(a["Tout_K"][-1])-to_root) < .001
    assert abs(float(a["P_Rx_W"][-1])-power_root) < 10
    metrics[case] = dict(
        max_abs_energy_residual_W=max_residual,
        final_Tout_K=float(a["Tout_K"][-1]), final_power_W=float(a["P_Rx_W"][-1]),
        final_dTf_dt_K_s=float(a["dTf_dt_K_s"][-1]), final_dP_dt_W_s=float(a["dP_dt_W_s"][-1]),
        Tout_minus_paper_table52_K=float(a["Tout_K"][-1]-1600),
        stationary_root=dict(Tfuel_K=tf_root, Tout_K=to_root, power_W=power_root,
                             scope="Calculated unchanged-model stationary root, not a thesis value"),
    )
    series[case] = (a, residual)
    for path in (csv_path, summary_path, run / case / "inventory.json", Path(summary["model_path"])):
        hashes[str(path)] = sha(path)

assert series["original"][0]["Tf_K"][0] == series["candidate"][0]["Tf_K"][0]
assert series["original"][0]["P_Rx_W"][0] == series["candidate"][0]["P_Rx_W"][0]
archive = subprocess.check_output(["git", "rev-parse", "archive/pre-restart-20260824^{}"], cwd=REPO, text=True).strip()
assert archive == "8f625c268c35a95c18a626305c1aa6a79ae2ace7"

out = run / "analysis"
out.mkdir(exist_ok=False)
fig, axes = plt.subplots(2, 1, figsize=(9, 7), layout="constrained", sharex=True)
for case, label, color, style in (("original", "Original", "#636363", "--"),
                                 ("candidate", "hA-consistent candidate", "#1776b6", "-")):
    a, residual = series[case]
    axes[0].plot(a["time_s"], a["Tout_K"], style, color=color, label=label)
    axes[1].plot(a["time_s"], residual/1000, style, color=color, label=label)
axes[0].axhline(1600, color="#333333", lw=1, ls=":", label="Thesis Table 5.2: 1600 K (reference only)")
axes[0].set(ylabel="Reactor outlet temperature (K)", title="Same warm initial states; fixed inlet at 1443.27 K")
axes[0].legend(fontsize=9, loc="upper right")
axes[1].axhline(0, color="#333333", lw=.7)
axes[1].set(xlabel="Simulation time (s)", ylabel="Energy-balance residual (kW)",
            title="Reactor power minus fuel storage minus coolant heat gain")
for ax in axes:
    ax.set_xlim(0, 500)
    ax.grid(alpha=.2)
fig.suptitle("Reactor hA-only diagnostic: closure improves, outlet-temperature discrepancy grows\n"
             "Not the thesis startup-curve reproduction or a full-system acceptance run", fontsize=11)
plot_path = out / "reactor_ha_500s_comparison.png"
fig.savefig(plot_path, dpi=160)
plt.close(fig)
hashes[str(plot_path)] = sha(plot_path)
hashes[str(Path(__file__).resolve())] = sha(__file__)
for name in ("check_reactor_energy_balance.py", "run_reactor_ha_consistency.m", "run_reactor_ha_whole_system.m"):
    path = REPO / "tests" / name
    hashes[str(path)] = sha(path)
paper = REPO / "空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf"
assert sha(paper) == "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a"
hashes[str(paper)] = sha(paper)
report = dict(metrics=metrics, only_parameter_changes=changes, protected_files_verified=len(protected),
              archive_commit=archive, input_output_sha256=hashes, model_acceptance_passed=False,
              whole_system_14000s_candidate_validated=False,
              scope="Completed 500 s isolated warm-state reactor pair only; paper line is a table reference, not original transient data")
(out / "verification.json").write_text(json.dumps(report, indent=2, ensure_ascii=False)+"\n")
print(json.dumps(metrics, indent=2))
print("LOCAL_AUDIT_COMPLETE_NOT_THESIS_ACCEPTANCE; OUTPUT=" + str(out))
