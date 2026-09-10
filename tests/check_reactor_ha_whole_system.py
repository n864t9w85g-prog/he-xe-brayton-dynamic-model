"""Independent checks and plots of the hA-only 14000 s comparison.

This is an exploratory audit, not thesis acceptance. In particular, boundary
enthalpy flow is not the IHX wall heat-transfer signal or a cold-start curve.
"""
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
assert "FULL_PAIR_14000_COMPLETE_FORMAL_FILES_UNCHANGED" in (run / "diary.txt").read_text()


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


inv = json.loads((run / "inventory.json").read_text())
before, after = inv["before"], inv["after"]
for key in ("blocks", "edges", "settings", "charts"):
    assert before[key] == after[key], key
old_p, new_p = [{p["key"]: p["value"] for p in inv[s]["parameters"]} for s in ("before", "after")]
assert old_p.keys() == new_p.keys()
changes = [{"key": k, "before": old_p[k], "after": new_p[k]} for k in old_p if old_p[k] != new_p[k]]
assert [d["key"] for d in changes] == ["/reactor/hA1|Value", "/reactor/hA2|Value"]
assert {"/IHX#1->/reactor#1", "/reactor#1->/IHX#1", "/reactor#2->/IHX#2"} <= set(before["edges"])
parameter = lambda name: float(json.loads(old_p["/reactor/" + name + "|Value"]))
kappa, gamma, cp, mdot = [parameter(n) for n in ("1//C_fuel", "gamma_f", "cp_Li", "Constant1")]
assert (kappa, gamma, cp, mdot) == (2.246e-5, .2906, 4111, 4.572)
for d in changes:
    assert float(json.loads(d["before"])) == 13296
    assert float(json.loads(d["after"])) == gamma/kappa

assert (run / "protected_before.csv").read_bytes() == (run / "protected_after.csv").read_bytes()
with (run / "protected_after.csv").open() as f:
    protected = list(csv.DictReader(f))
for row in protected:
    assert sha(row["paths"]) == row["hashes"], row["paths"]
source = REPO / "tmp/steady53_curves_20260828/source_f8bcd83"
assert sha(source / "Lithium_property_simulink.m") == "666a3a9d7bcb45e0e80afca4bd30e02bd19098ce72cc56bfe9a5f528c67b4c4f"

# Direct Table 5.2 simulation values, checked visually against PDF p.104.
# Reactor 2664 kW is NOT in that table and is deliberately not added here.
paper = {"reactor_inlet_T": 1443.27, "reactor_outlet_T": 1600,
         "turbine_inlet_T": 1522.96, "turbine_inlet_P": 1.539e6,
         "turbine_outlet_T": 1162, "turbine_outlet_P": .676e6,
         "compressor_inlet_T": 405.16, "compressor_inlet_P": .658e6,
         "compressor_outlet_T": 601.90, "compressor_outlet_P": 1.551e6,
         "recuperator_hot_outlet_T": 663.63, "recuperator_hot_outlet_P": .676e6,
         "recuperator_cold_outlet_T": 1100.91, "recuperator_cold_outlet_P": 1.543e6,
         "cooler_cold_inlet_T": 360.1, "cooler_cold_outlet_T": 609.58,
         "turbine_power": 2252.2e3, "compressor_power": 1231.6e3}
series, metrics, hashes = {}, {}, {}
for case in ("original", "candidate"):
    summary = json.loads((run / case / "summary.json").read_text())
    status = json.loads((run / case / "status.json").read_text())
    assert summary["success"] and status["success"] and not status["errorReport"]
    assert summary["final_time_s"] == status["final_time_s"] == 14000
    assert sha(summary["file"]) == summary["model_sha256"]
    csv_path = run / case / "signals.csv"
    assert sha(csv_path) == summary["signals_sha256"]
    a = np.genfromtxt(csv_path, delimiter=",", names=True)
    assert all(np.isfinite(a[k]).all() for k in a.dtype.names)
    t = a["time_s"]
    assert t[0] == 0 and t[-1] == 14000 and (np.diff(t) > 0).all()
    assert np.all(a["lithium_mdot_reactor"] == mdot) and np.all(a["lithium_mdot_ihx"] == mdot)
    assert np.all(a["rotor_speed"] == 55090)
    ti, to, tf = (a[n] for n in ("reactor_inlet_T", "reactor_outlet_T", "Tfuel_K"))
    assert np.all((ti >= 453.7) & (ti <= 1608) & (to >= 453.7) & (to <= 1608))
    qfuel = (gamma/kappa)*(tf-(ti+to)/2)
    qcool = mdot*cp*(to-ti)
    primitive = lambda x: .9615*1000*(-104400/x-135.1*np.log(x)+4.180*x)
    qboundary = mdot*(primitive(to)-primitive(ti))
    for calculated, key in ((qfuel, "Qfuel_W"), (qcool, "Qcoolant_W"), (qboundary, "IHX_Li_boundary_enthalpy_W")):
        assert np.max(np.abs(calculated-a[key])) < 1e-4, key
    local_gap = qcool-qfuel
    assert (np.max(np.abs(local_gap)) > 10000) if case == "original" else (np.max(np.abs(local_gap)) < .001)
    # Numerically integrate the active cp polynomial independently of its
    # analytic primitive at the final boundary temperatures.
    x, w = np.polynomial.legendre.leggauss(32)
    temp = (to[-1]+ti[-1])/2+(to[-1]-ti[-1])*x/2
    numerical = mdot*(to[-1]-ti[-1])/2*np.sum(w*.9615*1000*(104400/temp**2-135.1/temp+4.180))
    assert abs(numerical-qboundary[-1]) < 1e-5
    tail = t >= 13000
    assert tail.sum() >= 2
    references = {n: dict(paper=v, final=float(a[n][-1]), delta=float(a[n][-1]-v),
                          relative_error_pct=float(100*(a[n][-1]-v)/v)) for n, v in paper.items()}
    metrics[case] = dict(final_time_s=float(t[-1]), rows=len(t), tail_samples=int(tail.sum()),
        max_local_transfer_gap_W=float(np.max(np.abs(local_gap))),
        final_Qfuel_W=float(qfuel[-1]), final_Qcoolant_W=float(qcool[-1]),
        final_Li_boundary_enthalpy_W=float(qboundary[-1]),
        final_cross_cp_gap_W=float(qcool[-1]-qboundary[-1]),
        final_fuel_minus_boundary_W=float(qfuel[-1]-qboundary[-1]),
        final_reactor_power_W=float(a["reactor_power"][-1]),
        tail_peak_to_peak={n: float(np.ptp(a[n][tail])) for n in a.dtype.names if n != "time_s"},
        table52_references=references)
    series[case] = dict(data=a, qfuel=qfuel, qcool=qcool, qboundary=qboundary)
    for p in (csv_path, run / case / "summary.json", run / case / "status.json", run / case / "result.mat", Path(summary["file"])):
        hashes[str(p)] = sha(p)

for key in ("Tfuel_K", "reactor_power"):
    assert series["original"]["data"][key][0] == series["candidate"]["data"][key][0]
out = run / "analysis"
out.mkdir(exist_ok=False)
with (out / "table52_comparison.csv").open("w") as f:
    writer = csv.writer(f)
    writer.writerow(["signal", "paper_table52", "original_final", "candidate_final", "original_error_pct", "candidate_error_pct"])
    for n, v in paper.items():
        old, new = [metrics[c]["table52_references"][n] for c in ("original", "candidate")]
        writer.writerow([n, v, old["final"], new["final"], old["relative_error_pct"], new["relative_error_pct"]])

styles = (("original", "Original", "#636363", "--"), ("candidate", "hA-consistent candidate", "#1776b6", "-"))
fig, axes = plt.subplots(2, 2, figsize=(12, 7), layout="constrained")
panels = (("reactor_outlet_T", "Reactor outlet", "Temperature (K)", 1),
          ("reactor_inlet_T", "IHX hot outlet / reactor inlet", "Temperature (K)", 1),
          ("turbine_inlet_T", "IHX cold outlet / turbine inlet", "Temperature (K)", 1),
          ("reactor_power", "Reactor power", "Power (kW)", .001))
for ax, (name, title, unit, scale) in zip(axes.flat, panels):
    for c, label, color, style in styles:
        a = series[c]["data"]
        ax.plot(a["time_s"], a[name]*scale, style, color=color, label=label)
    if name in paper:
        ax.axhline(paper[name], color="#333333", ls=":", lw=1, label="Table 5.2 reference")
    ax.set(title=title, xlabel="Simulation time (s)", ylabel=unit, xlim=(0, 500))
    ax.grid(alpha=.2)
axes[0, 0].legend(fontsize=9)
fig.suptitle("Same warm-initialized whole system; first 500 s of two completed 14000 s runs\n"
             "Only reactor hA changed; this is not Fig.5.18 startup-curve reproduction", fontsize=11)
fig.savefig(out / "whole_system_first500s.png", dpi=160)
plt.close(fig)

fig, axes = plt.subplots(1, 2, figsize=(12, 4.5), layout="constrained")
for c, label, color, style in styles:
    d = series[c]
    for ax, gap in zip(axes, (d["qcool"]-d["qfuel"], d["qfuel"]-d["qboundary"])):
        ax.plot(d["data"]["time_s"], gap/1000, style, color=color, label=label)
for ax, title in zip(axes, ("Reactor: coolant gain minus fuel transfer", "Fuel transfer minus Li boundary enthalpy rate")):
    ax.axhline(0, color="#333333", lw=.7)
    ax.set(title=title, xlabel="Simulation time (s)", ylabel="Difference (kW)", xlim=(0, 14000))
    ax.grid(alpha=.2)
axes[0].legend(fontsize=9)
fig.suptitle("Local balance closes, but cross-component heat-capacity inconsistency remains\n"
             "Boundary enthalpy is a diagnostic calculation, not the IHX wall heat-flow signal", fontsize=11)
fig.savefig(out / "whole_system_energy_14000s.png", dpi=160)
plt.close(fig)

archive = subprocess.check_output(["git", "rev-parse", "archive/pre-restart-20260824^{}"], cwd=REPO, text=True).strip()
assert archive == "8f625c268c35a95c18a626305c1aa6a79ae2ace7"
paper_path = REPO / "空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf"
assert sha(paper_path) == "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a"
for p in [Path(__file__), REPO / "tests/run_reactor_ha_whole_system.m", run / "inventory.json", run / "parameter_diff.csv",
          run / "diary.txt", source / "Lithium_property_simulink.m", source / "HeXe_property_simulink.m",
          source / "tests/steady53/run_steady53_case.m", paper_path, *out.iterdir()]:
    hashes[str(p)] = sha(p)
report = dict(metrics=metrics, parameter_changes=changes, block_count=len(before["blocks"]),
    edge_count=len(before["edges"]), stateflow_chart_count=len(before["charts"]), solver=before["settings"],
    protected_files_verified=len(protected), archive_commit=archive, sha256=hashes,
    numerical_pair_completed=True, model_acceptance_passed=False,
    limitations=["Warm initial states, not original thesis component startup curves",
                 "Single run per variant, not the full formal acceptance suite",
                 "Boundary enthalpy rate is not actual IHX wall heat-transfer output",
                 "Runner electric power is synthesized with 0.96527; excluded from direct table validation",
                 "Constant 55090 rpm does not validate rotor dynamic stability",
                 "Historical exit143 source remains unidentified; this run made no execution-environment fix"])
(out / "verification.json").write_text(json.dumps(report, indent=2, ensure_ascii=False)+"\n")
for case, m in metrics.items():
    print(case, json.dumps({k: v for k, v in m.items() if k not in ("tail_peak_to_peak", "table52_references")}, indent=2))
print("WHOLE_SYSTEM_AUDIT_COMPLETE_NOT_THESIS_ACCEPTANCE; OUTPUT=" + str(out))
