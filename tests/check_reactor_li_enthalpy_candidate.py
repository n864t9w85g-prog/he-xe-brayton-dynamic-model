"""Independent artifact, topology and enthalpy check; not thesis acceptance."""
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

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("run_directory", type=Path)
run = p.parse_args().run_directory.resolve()
assert run.is_relative_to(root / "tmp")
baseline = root / "tmp/tpc62c4458_6d68_4bf1_9446_6dc3806024b2"
offline = root / "tmp/tp72ca94c4_b6e3_4599_aead_78bb905143b0"
source = root / "tmp/steady53_curves_20260828/source_f8bcd83"
sha = lambda path: hashlib.sha256(Path(path).read_bytes()).hexdigest()
assert "ENTHALPY_CANDIDATE_14000_COMPLETE_PROTECTED_FILES_UNCHANGED" in (run / "diary.txt").read_text()
assert "OFFLINE_ENTHALPY_TESTS_PASS_NO_SLX_LOADED" in (offline / "diary.txt").read_text()
assert (run / "protected_before.csv").read_bytes() == (run / "protected_after.csv").read_bytes()
with (run / "protected_after.csv").open() as f:
    protected = list(csv.DictReader(f))
for row in protected:
    assert sha(row["paths"]) == row["hashes"], row["paths"]

inv = json.loads((run / "inventory.json").read_text())
before, after = inv["before"], inv["after"]
assert before == json.loads((baseline / "inventory.json").read_text())["after"]
prefix = "/reactor/Li_Enthalpy_Outlet_Candidate"
for key, field in (("blocks", "relative"), ("parameters", "key"), ("charts", "path")):
    assert before[key] == [x for x in after[key] if not x[field].startswith(prefix)]
assert before["settings"] == after["settings"]
assert set(before["edges"]) - set(after["edges"]) == {"/reactor/Sum15#1->/reactor/Goto3#1"}
expected = {f"/reactor/{name}#1->{prefix}#{i}" for i, name in enumerate(("From33", "Integrator7", "Constant1", "hA1"), 1)}
expected.add(prefix + "#1->/reactor/Goto3#1")
added = set(after["edges"]) - set(before["edges"])
assert expected <= added
assert all(all(part.startswith(prefix + "/") for part in e.split("->")) for e in added - expected)
assert sum(b["types"] == "Integrator" for b in before["blocks"]) == sum(b["types"] == "Integrator" for b in after["blocks"])

summaries = {"hA_only": json.loads((baseline / "candidate/summary.json").read_text()),
             "enthalpy": json.loads((run / "summary.json").read_text())}
paths = {"hA_only": baseline / "candidate/signals.csv", "enthalpy": run / "signals.csv"}
assert sha(baseline / "reactor_ha_candidate.slx") == summaries["enthalpy"]["baseline_sha256"]
assert sha(run / "reactor_li_candidate.slx") == summaries["enthalpy"]["model_sha256"]
assert sha(source / "Lithium_property_simulink.m") == "666a3a9d7bcb45e0e80afca4bd30e02bd19098ce72cc56bfe9a5f528c67b4c4f"
metrics, data, residuals, hashes = {}, {}, {}, {}
for case, path in paths.items():
    assert sha(path) == summaries[case]["signals_sha256"]
    a = np.genfromtxt(path, delimiter=",", names=True)
    assert all(np.isfinite(a[n]).all() for n in a.dtype.names)
    t = a["time_s"]
    assert t[0] == 0 and t[-1] == 14000 and np.all(np.diff(t) > 0)
    assert np.all(a["lithium_mdot_reactor"] == 4.572)
    assert np.all(a["lithium_mdot_ihx"] == 4.572) and np.all(a["rotor_speed"] == 55090)
    ti, to, tf = (a[n] for n in ("reactor_inlet_T", "reactor_outlet_T", "Tfuel_K"))
    assert np.all((453.7 <= ti) & (ti <= to) & (to <= 1608))
    qfuel = (.2906/2.246e-5)*(tf-(ti+to)/2)
    # Independent fixed Gauss quadrature vs runtime MATLAB adaptive integral.
    x, w = np.polynomial.legendre.leggauss(32)
    temps = (ti[:, None]+to[:, None])/2+(to-ti)[:, None]*x/2
    cp = .9615*1000*(104400/temps**2-135.1/temps+4.180)
    qli = 4.572*(to-ti)/2*(cp @ w)
    gap = qfuel-qli
    assert np.max(np.abs(qfuel-a["Qfuel_W"])) < .001
    if case == "hA_only":
        assert np.max(np.abs(gap)) > 80000
    else:
        assert np.max(np.abs(gap)) < .001
        assert np.max(np.abs(qli-a["Q_Li_enthalpy_W"])) < .001
        assert np.max(np.abs(qli/(4.572*(to-ti))-a["cpbar_J_kgK"])) < 1e-6
    tail = t >= 13000
    assert tail.sum() >= 2
    names = ["reactor_outlet_T", "reactor_inlet_T", "turbine_inlet_T", "reactor_power", "Tfuel_K"]
    metrics[case] = dict(final={n: float(a[n][-1]) for n in names}, samples=len(a),
        max_enthalpy_gap_W=float(np.max(np.abs(gap))), final_enthalpy_gap_W=float(gap[-1]),
        final_Li_boundary_enthalpy_W=float(qli[-1]),
        tail_peak_to_peak={n: float(np.ptp(a[n][tail])) for n in names},
        reactor_outlet_minus_table52_K=float(to[-1]-1600))
    data[case], residuals[case] = a, gap
    hashes[str(path)] = sha(path)
for key in ("Tfuel_K", "reactor_power", "reactor_inlet_T", "turbine_inlet_T"):
    assert data["hA_only"][key][0] == data["enthalpy"][key][0]

out = run / "analysis"
out.mkdir(exist_ok=False)
fig, axes = plt.subplots(2, 2, figsize=(12, 7), layout="constrained")
styles = (("hA_only", "Previous hA-only candidate", "#636363", "--"),
          ("enthalpy", "Same hA + Li enthalpy candidate", "#1776b6", "-"))
targets = {"reactor_outlet_T": 1600, "reactor_inlet_T": 1443.27, "turbine_inlet_T": 1522.96}
for ax, name, title, scale in zip(axes.flat,
        ["reactor_outlet_T", "reactor_inlet_T", "turbine_inlet_T", "reactor_power"],
        ["Reactor outlet", "IHX hot outlet / reactor inlet", "IHX cold outlet / turbine inlet", "Reactor power"],
        [1, 1, 1, .001]):
    for case, label, color, style in styles:
        ax.plot(data[case]["time_s"], data[case][name]*scale, style, color=color, label=label)
    if name in targets:
        ax.axhline(targets[name], color="#333333", ls=":", lw=1, label="Table 5.2 reference")
    ax.set(xlim=(0, 500), xlabel="Simulation time (s)", ylabel="Temperature (K)" if scale == 1 else "Power (kW)", title=title)
    ax.grid(alpha=.2)
axes[0, 0].legend(fontsize=8)
fig.suptitle("Li-enthalpy-only change on the preserved hA candidate; unchanged warm initial states\n"
             "First 500 s of completed 14000 s records, not the thesis component startup curves", fontsize=11)
fig.savefig(out / "li_enthalpy_first500s.png", dpi=160)
plt.close(fig)
fig, ax = plt.subplots(figsize=(9, 4.5), layout="constrained")
for case, label, color, style in styles:
    ax.plot(data[case]["time_s"], residuals[case]/1000, style, color=color, label=label)
ax.axhline(0, lw=.7, color="#333333")
ax.set(xlim=(0, 14000), xlabel="Simulation time (s)", ylabel="Heat-rate difference (kW)",
       title="Fuel heat transfer minus Li boundary enthalpy rate\nNot a complete IHX wall/fluid energy audit")
ax.grid(alpha=.2); ax.legend(fontsize=9)
fig.savefig(out / "li_enthalpy_balance_14000s.png", dpi=160)
plt.close(fig)

paper = root / "空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf"
assert sha(paper) == "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a"
for path in [run / "inventory.json", run / "summary.json", run / "status.json", run / "diary.txt", run / "result.mat",
             run / "reactor_li_candidate.slx", baseline / "reactor_ha_candidate.slx", baseline / "candidate/result.mat",
             source / "Lithium_property_simulink.m", source / "HeXe_property_simulink.m", paper,
             offline / "offline_points.csv", offline / "diary.txt", Path(__file__),
             *[root / "tests" / n for n in ("test_reactor_li_enthalpy_outlet.m", "reactor_li_enthalpy_outlet.m", "run_reactor_li_enthalpy_candidate.m")],
             *out.iterdir()]:
    hashes[str(path)] = sha(path)
archive = subprocess.check_output(["git", "rev-parse", "archive/pre-restart-20260824^{}"], cwd=root, text=True).strip()
assert archive == "8f625c268c35a95c18a626305c1aa6a79ae2ace7"
report = dict(metrics=metrics, protected_files=len(protected), archive_commit=archive,
    block_counts=[len(before["blocks"]), len(after["blocks"])], changed_existing_parameters=0,
    added_edges=sorted(added), removed_edges=inv["removed_edges"], sha256=hashes,
    limits=["Only reactor outlet enthalpy convention changed on an unpromoted hA candidate",
           "Existing 0.9615 calibration retained; not validated as original literature",
           "Warm heating domain only; not full startup domain",
           "One new run versus a hash-verified saved baseline run",
           "No full IHX energy audit or thesis transient-curve acceptance performed"],
    numerical_run_completed=True, model_acceptance_passed=False)
(out / "verification.json").write_text(json.dumps(report, indent=2, ensure_ascii=False)+"\n")
print(json.dumps(metrics, indent=2))
print("LI_ENTHALPY_AUDIT_PASS_NOT_THESIS_ACCEPTANCE; OUTPUT=" + str(out))
