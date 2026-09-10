"""Compare the authorized IHX candidate with an identically configured baseline."""
import argparse
import csv
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
assert run.is_relative_to(REPO / "tmp")
assert "ALL_FOUR_CASES_COMPLETE_SOURCE_PROTECTED_NOT_THESIS_ACCEPTANCE" in (run / "diary.txt").read_text()
assert (run / "protected_before.csv").read_bytes() == (run / "protected_after.csv").read_bytes()
summary = json.loads((run / "summary.json").read_text())
assert len(summary) == 4
points_path = REPO / "tmp/tpf255e6c2_bcc0_4262_883f_5caf6d3f6a0d/analysis/paper_ihx_points.csv"
provenance = json.loads(points_path.with_name("metrics.json").read_text())
scan = REPO / "tmp/steady53_recheck_20260827/paper-105.png"
assert hashlib.sha256(scan.read_bytes()).hexdigest() == provenance["source_image_sha256"]
with points_path.open() as stream:
    points = [{k: float(v) for k, v in row.items()} for row in csv.DictReader(stream)]
paper_t = np.array([p["time_s"] for p in points])
hashes = {}


def read(case, name, end):
    path = run / case / (name + ".csv")
    a = np.loadtxt(path, delimiter=",", ndmin=2)
    assert a.shape[1] == 2 and np.isfinite(a).all()
    assert a[0, 0] == 0 and a[-1, 0] == end and np.all(np.diff(a[:, 0]) >= 0)
    hashes[f"{case}/{name}.csv"] = hashlib.sha256(path.read_bytes()).hexdigest()
    return a[:, 0], a[:, 1]


series, metrics = {}, {}
for case in ("original_500", "candidate_500"):
    data = {"hot": read(case, "y_001", 500), "cold": read(case, "y_003", 500)}
    t1, w1 = read(case, "state_05", 500)
    t2, w2 = read(case, "state_10", 500)
    assert np.array_equal(t1, t2)
    data["wall"] = (t1, (w1 + w2) / 2)
    series[case] = data
    metrics[case] = {"region1_wall_final_K": float(w1[-1]), "region2_wall_final_K": float(w2[-1])}
    for name, (t, y) in data.items():
        reference = np.array([p[name + "_K"] for p in points])
        deviations = np.interp(paper_t, t, y) - reference
        metrics[case][name] = dict(
            initial_K=float(y[0]), final_K=float(y[-1]), minimum_K=float(y.min()),
            minimum_sample_time_s=float(t[y.argmin()]), at50_K=float(np.interp(50, t, y)),
            paper_last_sample_K=float(reference[-1]),
            final_minus_paper_last_sample_K=float(y[-1] - reference[-1]),
            scan_sample_rmse_K=float(np.sqrt(np.mean(deviations ** 2))),
            scan_sample_max_abs_difference_K=float(np.max(np.abs(deviations))),
            status="Read-off comparison only; wall mapping unverified; not a formal acceptance score.",
        )

# Independently recompute power closure from the exported CSV rather than
# trusting the MATLAB summary. CSV precision sets this audit's numerical floor.
power_checks = {}
for item in summary:
    case, end = item["name"], item["final_time"]
    case_checks = {}
    for r in (1, 2):
        def get(name):
            return read(case, f"r{r}_{name}", end)
        names = ["hot_q1", "hot_q2", "wall_hot", "cold_q", "hot_adv1", "hot_adv2",
                 "cold_adv1", "cold_adv2", "hot_half_capacity", "cold_half_capacity",
                 "wall_capacity", "hot_d1", "hot_d2", "cold_d1", "cold_d2", "wall_d"]
        arrays = {n: get(n) for n in names}
        t = arrays[names[0]][0]
        assert all(np.array_equal(t, a[0]) for a in arrays.values())
        a = {n: v[1] for n, v in arrays.items()}
        bh, bc, bw = [a[n] for n in ("hot_half_capacity", "cold_half_capacity", "wall_capacity")]
        residuals = {
            "hot1": bh*a["hot_d1"]-a["hot_adv1"]+a["hot_q1"],
            "hot2": bh*a["hot_d2"]-a["hot_adv2"]+a["hot_q2"],
            "cold1": bc*a["cold_d1"]-a["cold_adv1"]-.5*a["cold_q"],
            "cold2": bc*a["cold_d2"]-a["cold_adv2"]-.5*a["cold_q"],
            "wall": bw*a["wall_d"]-a["wall_hot"]+a["cold_q"],
            "allocation": a["wall_hot"]-a["hot_q1"]-a["hot_q2"],
            "sum": bh*(a["hot_d1"]+a["hot_d2"])+bc*(a["cold_d1"]+a["cold_d2"])
                   +bw*a["wall_d"]-sum(a[n] for n in ("hot_adv1", "hot_adv2", "cold_adv1", "cold_adv2")),
        }
        peaks = {n: float(np.max(np.abs(v))) for n, v in residuals.items()}
        assert max(peaks.values()) < 1e-5, peaks
        if case.startswith("candidate"):
            tx, x = read(case, f"state_{3 + 5*(r-1):02}", end)
            ty, y = read(case, f"state_{4 + 5*(r-1):02}", end)
            tz, z = read(case, f"state_{5 + 5*(r-1):02}", end)
            assert np.array_equal(t, tx) and np.array_equal(t, ty) and np.array_equal(t, tz)
            local_errors = [float(np.max(np.abs(a["hot_q1"] - .5*10544*7.031*(x-z)))),
                            float(np.max(np.abs(a["hot_q2"] - .5*10544*7.031*(y-z))))]
            # Exported temperatures have about 11 digits after the decimal:
            # multiplying subtraction error by hA can leave sub-micro-watt noise.
            assert max(local_errors) < 1e-5
            peaks["local_hot_formula_max_W"] = max(local_errors)
        case_checks[f"region{r}"] = peaks
    power_checks[case] = case_checks

out = run / "analysis"
out.mkdir(exist_ok=False)
report = dict(comparison=metrics, power_checks_W=power_checks, runs=summary,
              scan_sha256=provenance["source_image_sha256"],
              paper_samples_sha256=hashlib.sha256(points_path.read_bytes()).hexdigest(),
              reading_uncertainty="Approximately +/-3 K, +/-2 s; not an acceptance threshold.",
              wall_definition="Arithmetic mean of two model walls, NOT verified as thesis T_IHX.",
              power_scope="Instantaneous implemented power balances, not independent variable-cp enthalpy validation.",
              input_hashes=hashes)
fig, axes = plt.subplots(1, 3, figsize=(15, 5), layout="constrained")
for ax, name, title in zip(axes, ("hot", "cold", "wall"),
                          ("Hot outlet", "Cold outlet", "Two-wall mean (mapping unverified)")):
    for case, label, color, style in [("original_500", "Original equations", "tab:gray", "--"),
                                       ("candidate_500", "Local hot-cell candidate", "tab:blue", "-")]:
        t, y = series[case][name]
        ax.plot(t, y, style, color=color, lw=1.7, label=label)
    ax.errorbar(paper_t, [p[name+"_K"] for p in points], xerr=2, yerr=3,
                fmt="o", color="black", mfc="white", ms=4, capsize=2, label="Original scan samples")
    ax.set(xlim=(0, 70), xlabel="Time (s)", ylabel="Temperature (K)", title=title)
    ax.grid(alpha=.2)
axes[0].legend(fontsize=8, loc="lower right")
fig.suptitle("IHX: approved heat-allocation candidate vs unchanged equations; both simulated to 500 s\n"
             "Same 1200 K initial states, boundary inputs, coefficients and solver; no fitting or time shifts", fontsize=11)
fig.savefig(out / "ihx_local_hot_vs_paper.png", dpi=160)
plt.close(fig)

fig, ax = plt.subplots(figsize=(8, 4.5), layout="constrained")
old = REPO / "tmp/tp5ab81620_f711_416b_81ee_2c8d9710662b/delta_4/state_04.csv"
old_hash = hashlib.sha256(old.read_bytes()).hexdigest()
old_provenance = json.loads((old.parents[1] / "analysis/metrics.json").read_text())
assert old_hash == old_provenance["inputs_sha256"]["delta_4/state_04.csv"]
hashes["previous_uniform_step/delta_4/state_04.csv"] = old_hash
old_a = np.loadtxt(old, delimiter=",")
ax.plot(old_a[:, 0], old_a[:, 1]-1200, "--", color="tab:red", label="Original: region 1 hot outlet")
for n, label in [("state_04", "Candidate: region 1 hot outlet"),
                 ("state_09", "Candidate: region 2 hot outlet")]:
    t, y = read("candidate_plus4", n, 2)
    ax.plot(t, y-1200, label=label)
ax.axhline(0, color="black", lw=.7)
ax.set(xlim=(0, 2), xlabel="Time (s)", ylabel="Temperature minus 1200 K (K)",
       title="Uniform 1200 K initial states; only hot inlet raised to 1204 K")
ax.grid(alpha=.2); ax.legend(fontsize=9)
fig.savefig(out / "ihx_positive_step_before_after.png", dpi=160)
plt.close(fig)
(out / "metrics.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(metrics, indent=2))
print("ALL_CSV_POWER_CHECKS_PASSED; OUTPUT=" + str(out))
