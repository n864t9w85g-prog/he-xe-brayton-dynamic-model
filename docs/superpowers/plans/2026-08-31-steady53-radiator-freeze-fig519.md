# Steady 5.3 Radiator Evidence Freeze and Figure 5.19 Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Durably preserve the completed Figure 5.18(d) evidence, then build a traceable Figure 5.19 observation contract, explain the current flat power traces, and run one isolated reactor-initial-condition counterfactual without modifying any formal model.

**Architecture:** Publish byte-identical evidence and the exact f8bcd83 runtime dependencies into Git-tracked provenance directories, with literal SHA256 contracts and no repeated A1/radiator runs. Build Figure 5.19 paper evidence independently from the model, audit direct-versus-derived power signals, run one instrumented 500 s reference from the immutable baseline, and only then run one API-patched diagnostic copy that changes the reactor power initial condition as a falsification experiment.

**Tech Stack:** Python 3 standard library, Pillow, NumPy, Matplotlib, MATLAB R2025a, Simulink official APIs, MATLAB `matlab.unittest`, Git, SHA256.

---

## Execution constraints

- Execute in the current repository because the evidence sources in `tmp/` and several diagnostic scripts are untracked and are not present in a fresh worktree.
- Never run `git clean`, delete `tmp/`, delete untracked files, or stage unrelated files.
- Use `apply_patch` for text edits. Byte-identical `.mat`, `.png`, `.m`, and `.mat` lookup publication may use the hash-gated publisher scripts in this plan; those scripts copy through a temporary file and refuse overwrite-on-mismatch.
- Do not repeat the radiator 14000 s initial-condition runs, the A1 96/12/11 pipeline, the A1 500 s runs, or the A1 14000 s runs.
- Do not edit, save, or promote root `final_steady_24a.slx`, root `final_dynamic_24a.slx`, any formal `.mat`, or either property function.
- Every Simulink mutation is applied to a new file below `tmp/` by `set_param`/`save_system`; SLX/XML inspection is read-only.
- Stage and commit only the files listed in each task.

## File responsibility map

### Durable f8bcd83 runtime

- `data/provenance/baselines/f8bcd83/runtime/`: byte-identical property, table, initialization dependencies, and original `tests/steady53` helper sources required to load or reconstruct diagnostics without relying on the cleanup-prone historical snapshot.
- `tests/steady53/`: path-adapted working copies created from the immutable helper sources during Task 3; they are not part of the byte-identity runtime verifier.
- `tests/publish_f8bcd83_runtime.py`: one-time atomic publisher plus permanent `--verify-only` hash gate.
- `tests/test_publish_f8bcd83_runtime.py`: literal source/destination/hash contract.

### Figure 5.18(d) freeze

- `data/provenance/steady53/fig5_18d/`: paper points, two completed IC runs, A1 screen/selection/summaries, manifest, and fixed negative-result README.
- `tests/publish_fig518d_evidence.py`: atomic publisher and permanent verifier.
- `tests/test_publish_fig518d_evidence.py`: exact counts, hashes, and status-gate tests.
- `tests/radiator_curve_energy_check.py`: tracked no-fit energy/compatibility diagnostic using only durable inputs.
- `tests/radiator_parameter_family_check.py`: tracked constant-ratio family incompatibility diagnostic.

### Figure 5.19 observation and experiments

- `data/provenance/steady53/fig5_19/`: source page, paper points, calibration, signal contract, baseline summaries, experiment summaries, hashes, and README.
- `tests/digitize_fig519.py`: deterministic scan-coordinate extraction and overlay generation.
- `tests/test_digitize_fig519.py`: calibration, point-count, and physically bounded trace tests.
- `tests/analyze_fig519_baseline.py`: existing-output reuse, direct/derived power arithmetic, and paper comparison.
- `tests/test_analyze_fig519_baseline.py`: baseline flatness and electrical-definition guards.
- `tests/audit_fig519_initialization.m`: official-API state/input/signal inventory plus one unmodified 500 s instrumented reference.
- `tests/test_audit_fig519_initialization.m`: isolation, state count, IC, and no-rewrite tests.
- `tests/create_fig519_reactor_ic_candidate.m`: one-whitelist-change diagnostic candidate generator.
- `tests/run_fig519_reactor_ic_counterfactual.m`: blocking 500 s runner for that candidate.
- `tests/analyze_fig519_counterfactual.py`: raw-curve comparison and falsification classification; never promotes a parameter.
- `tests/test_fig519_counterfactual.py`: exact-one-change and no-promotion guards.
- `docs/steady53_fig519_progress_20260831.md`: evidence-ranked result and next decision.

## Task 1: Publish the f8bcd83 runtime dependency bundle

**Files:**

- Create: `tests/test_publish_f8bcd83_runtime.py`
- Create: `tests/publish_f8bcd83_runtime.py`
- Create by publisher: `data/provenance/baselines/f8bcd83/runtime/*`
- Modify: `data/provenance/baselines/f8bcd83/baseline_manifest.csv`
- Modify: `data/provenance/baselines/f8bcd83/README.md`

- [ ] **Step 1: Write the failing literal-contract test**

Create `tests/test_publish_f8bcd83_runtime.py` with the exact expected map:

```python
from pathlib import Path
import unittest

from tests import publish_f8bcd83_runtime as publisher


ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {
    "runtime/HeXe_property_simulink.m": "2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2",
    "runtime/Lithium_property_simulink.m": "666a3a9d7bcb45e0e80afca4bd30e02bd19098ce72cc56bfe9a5f528c67b4c4f",
    "runtime/hexe_compressor_lookup.mat": "f9c85bc1ae831333fac5f868f15a6f82ea1c1716ee17f23dfb301f4618c9f579",
    "runtime/radiator_table.mat": "3f6e8a08f6ec9253b84d07f8eff11d2b093f785bafcfde515f2c6af4ec263304",
    "runtime/turbine_table1.mat": "10e72638374c530e2032d9bfe39b060d4181b0467bf69e03196efa0b90c4971d",
    "runtime/turbine_table2.mat": "6ff94cce373b67a143e9a992ec693ef17a910440eb4218cdf796543ba48c8a38",
    "runtime/start.m": "0de14c8d7e56e22871800f0c84f6eccd5b00e34ae7c20a3501752f45a09effec",
    "runtime/sys_param_rad_fixed.m": "bbdcf30dcd2fd7859092af0d85a79ed5dabc6da6c298f1d064ed11d612f30d5b",
    "runtime/paper54_constants.m": "545e9b7653b4a47759e746e33a52a184e69c1455911929ce096d1a6eb6558345",
    "runtime/tests/steady53/create_component_harness.m": "0f536ffaff9345e5cc85af37bdfa6a385db0e54bd7f0adcedbd81b95fdcd2dd0",
    "runtime/tests/steady53/steady53_component_boundaries.m": "8e2092ef2a9a183a7e4b3cd04fc05949d3648de873833391f262eed13f72ed26",
    "runtime/tests/steady53/steady53_signal_manifest.m": "7807290de1b02cf4c2e513976a8c95e5780201ce5fdae0bdd97679b0f2e835bd",
    "runtime/tests/steady53/reset_steady53_property_warning_state.m": "04f1be8b20c3b48f17e468c1dd15a282e15ea08f14f255f5a6f3d269f2d44ff0",
    "runtime/tests/steady53/run_steady53_case.m": "6ec6f09c9d6ef32520b28248588d5ba0b31f3cf99acd0f6b0bc5bdff7f45e79a",
}


class RuntimePublicationTests(unittest.TestCase):
    def test_literal_contract(self):
        self.assertEqual(publisher.EXPECTED_SHA256, EXPECTED)

    def test_verify_rejects_missing_or_changed_files(self):
        with self.assertRaises(publisher.PublicationError):
            publisher.verify_tree(ROOT / "tmp/deliberately_missing_runtime")

    def test_status_gates_are_fixed(self):
        self.assertFalse(publisher.STATUS["paper_reproduced"])
        self.assertFalse(publisher.STATUS["formal_promotion"])
        self.assertEqual(publisher.STATUS["source_commit"],
                         "f8bcd833e816eb681982b7dd04364e4b856948e3")


if __name__ == "__main__":
    unittest.main(verbosity=2)
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
python3 -m unittest -v tests.test_publish_f8bcd83_runtime
```

Expected: import failure for `tests.publish_f8bcd83_runtime`.

- [ ] **Step 3: Implement the atomic publisher**

Create `tests/publish_f8bcd83_runtime.py` with:

```python
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import shutil


ROOT = Path(__file__).resolve().parents[1]
HISTORICAL = ROOT / "tmp/steady53_curves_20260828/source_f8bcd83"
BASELINE = ROOT / "data/provenance/baselines/f8bcd83"
STATUS = {
    "source_commit": "f8bcd833e816eb681982b7dd04364e4b856948e3",
    "paper_reproduced": False,
    "formal_promotion": False,
}
EXPECTED_SHA256 = {
    "runtime/HeXe_property_simulink.m": "2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2",
    "runtime/Lithium_property_simulink.m": "666a3a9d7bcb45e0e80afca4bd30e02bd19098ce72cc56bfe9a5f528c67b4c4f",
    "runtime/hexe_compressor_lookup.mat": "f9c85bc1ae831333fac5f868f15a6f82ea1c1716ee17f23dfb301f4618c9f579",
    "runtime/radiator_table.mat": "3f6e8a08f6ec9253b84d07f8eff11d2b093f785bafcfde515f2c6af4ec263304",
    "runtime/turbine_table1.mat": "10e72638374c530e2032d9bfe39b060d4181b0467bf69e03196efa0b90c4971d",
    "runtime/turbine_table2.mat": "6ff94cce373b67a143e9a992ec693ef17a910440eb4218cdf796543ba48c8a38",
    "runtime/start.m": "0de14c8d7e56e22871800f0c84f6eccd5b00e34ae7c20a3501752f45a09effec",
    "runtime/sys_param_rad_fixed.m": "bbdcf30dcd2fd7859092af0d85a79ed5dabc6da6c298f1d064ed11d612f30d5b",
    "runtime/paper54_constants.m": "545e9b7653b4a47759e746e33a52a184e69c1455911929ce096d1a6eb6558345",
    "runtime/tests/steady53/create_component_harness.m": "0f536ffaff9345e5cc85af37bdfa6a385db0e54bd7f0adcedbd81b95fdcd2dd0",
    "runtime/tests/steady53/steady53_component_boundaries.m": "8e2092ef2a9a183a7e4b3cd04fc05949d3648de873833391f262eed13f72ed26",
    "runtime/tests/steady53/steady53_signal_manifest.m": "7807290de1b02cf4c2e513976a8c95e5780201ce5fdae0bdd97679b0f2e835bd",
    "runtime/tests/steady53/reset_steady53_property_warning_state.m": "04f1be8b20c3b48f17e468c1dd15a282e15ea08f14f255f5a6f3d269f2d44ff0",
    "runtime/tests/steady53/run_steady53_case.m": "6ec6f09c9d6ef32520b28248588d5ba0b31f3cf99acd0f6b0bc5bdff7f45e79a",
}


class PublicationError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def destination(relative: str) -> Path:
    return BASELINE / relative


def source(relative: str) -> Path:
    return HISTORICAL / relative.removeprefix("runtime/")


def publish_file(src: Path, dst: Path, expected: str) -> None:
    if not src.is_file() or sha256(src) != expected:
        raise PublicationError(f"source identity mismatch: {src}")
    if dst.exists():
        if sha256(dst) != expected:
            raise PublicationError(f"refusing overwrite: {dst}")
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    temporary = dst.with_name(dst.name + ".publishing")
    if temporary.exists():
        raise PublicationError(f"stale temporary file: {temporary}")
    shutil.copyfile(src, temporary)
    if sha256(temporary) != expected:
        raise PublicationError(f"temporary copy mismatch: {temporary}")
    os.replace(temporary, dst)


def verify_tree(root: Path = ROOT) -> None:
    for relative, expected in EXPECTED_SHA256.items():
        path = destination(relative) if root == ROOT else root / relative
        if not path.is_file() or sha256(path) != expected:
            raise PublicationError(f"runtime verification failed: {path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    if not args.verify_only:
        for relative, expected in EXPECTED_SHA256.items():
            publish_file(source(relative), destination(relative), expected)
    verify_tree()
    print("F8BCD83_RUNTIME_PASS; FILES=14; PAPER_REPRODUCED=false")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run GREEN and publish the files**

Run:

```bash
python3 -m unittest -v tests.test_publish_f8bcd83_runtime
python3 tests/publish_f8bcd83_runtime.py
python3 tests/publish_f8bcd83_runtime.py --verify-only
```

Expected: 3 tests pass; publisher prints `F8BCD83_RUNTIME_PASS; FILES=14; PAPER_REPRODUCED=false` twice.

- [ ] **Step 5: Extend the baseline manifest and README**

Append the 14 literal entries to `baseline_manifest.csv` with role `steady53_runtime_dependency` or `steady53_test_helper`, and add this text to `README.md`:

```markdown
The `runtime/` files are byte-identical f8bcd83 dependencies required to load the steady baseline without relying on `tmp/`. Original helper sources are preserved below `runtime/tests/steady53/`; editable working copies below repository `tests/steady53/` are created and reviewed separately.
```

Run:

```bash
python3 tests/publish_f8bcd83_runtime.py --verify-only
git diff --check
```

Expected: runtime verification passes; no whitespace errors.

- [ ] **Step 6: Commit only Task 1**

```bash
git add tests/publish_f8bcd83_runtime.py tests/test_publish_f8bcd83_runtime.py \
  data/provenance/baselines/f8bcd83/runtime \
  data/provenance/baselines/f8bcd83/baseline_manifest.csv \
  data/provenance/baselines/f8bcd83/README.md
git commit -m "固化f8bcd83稳态运行依赖"
```

## Task 2: Publish the completed Figure 5.18(d) evidence

**Files:**

- Create: `tests/publish_fig518d_evidence.py`
- Create: `tests/test_publish_fig518d_evidence.py`
- Create by publisher: `data/provenance/steady53/fig5_18d/**`

- [ ] **Step 1: Write the failing evidence-contract test**

The test must assert these exact facts:

```python
def test_published_contract(self):
    report = publisher.verify_published()
    self.assertEqual(report["paper_point_count"], 12)
    self.assertEqual(report["ic_mat_count"], 2)
    self.assertEqual(report["offline_row_count"], 96)
    self.assertEqual(report["representative_count"], 12)
    self.assertEqual(report["eligible_count"], 11)
    self.assertEqual(report["representative_manifest_count"], 11)
    self.assertEqual(report["ineligible_without_manifest"],
                     ["T300_fd1p45_one__legacy_transfer"])
    self.assertEqual(report["stage_500_passed"], 3)
    self.assertEqual(report["stage_14000_passed"], 3)
    self.assertEqual(report["a1_identifiability"],
                     "multiple_conditionally_feasible_packages")
    self.assertFalse(report["paper_reproduced"])
    self.assertFalse(report["formal_promotion"])
```

Also test that a mismatching destination raises `PublicationError` and that the README contains all five fixed machine-readable lines from the approved design.

- [ ] **Step 2: Run RED**

```bash
python3 -m unittest -v tests.test_publish_fig518d_evidence
```

Expected: import failure for `tests.publish_fig518d_evidence`.

- [ ] **Step 3: Implement the publisher and manifest**

Use the `publish_file` atomic-copy pattern from Task 1. The source-to-target set is exactly:

```text
tmp/steady53_curves_20260828/radiator_scan_points.csv
  -> paper_curve/points.csv
tmp/steady53_curves_20260828/radiator_scan_provenance.json
  -> paper_curve/provenance.json
tmp/steady53_curves_20260828/radiator_ic/{ic_250.mat,ic_250_wall.csv,ic_250_outlet.csv,ic_407.mat,ic_407_wall.csv,ic_407_outlet.csv,diary.txt}
  -> initial_condition_runs/
tmp/radiator_A1_20260830_A2/offline_screen/{offline_96.csv,offline_rejection_log.csv}
  -> a1_summary/
tmp/radiator_A1_20260830_A2/representatives/{representative_matrix.csv,selection.json}
  -> a1_summary/
tmp/radiator_A1_20260830_A2/representatives/*/parameter_manifest.json
  -> a1_summary/representative_manifests/，发布当前实际存在的 11 个合格候选清单，目标文件名取各源文件父目录的候选 ID 并加 `.json`
tmp/radiator_A1_20260830_A2/comparisons/advance_14000.json
  -> a1_summary/advance_14000.json
tmp/radiator_A1_20260830_A2/source_contract/{source_contract.json,unit_contract.json,output_hashes.json}
  -> a1_summary/
tmp/radiator_A1_20260830_A2/final_audit/{preparation_summary.json,batch_500_summary.json,summary_500.json,batch_14000_summary.json,summary_14000.json,report.md}
  -> a1_summary/
```

The publisher must derive SHA256 and byte count from each source, write `manifest.csv` only after all copies verify, and refuse to overwrite any existing nonmatching file. Write `README.md` with:

```text
paper_reproduced = false
author_implementation_status = not_uniquely_identified
current_equation_family_status = incompatible_with_both_digitized_curves
a1_identifiability = multiple_conditionally_feasible_packages
formal_promotion = false
```

The publisher must also verify that `representative_matrix.csv` has 12 fixed roles, `selection.json` has `eligible_count=11`, and exactly 11 source `parameter_manifest.json` files exist. The sole ineligible role `T300_fd1p45_one__legacy_transfer` has no generated per-candidate manifest because it was rejected before SLX preparation; its complete parameters and rejection reasons remain in `representative_matrix.csv`. This distinction is evidence, not a missing-file error, and must be stated in the README.

- [ ] **Step 4: Run GREEN and publish once**

```bash
python3 -m unittest -v tests.test_publish_fig518d_evidence
python3 tests/publish_fig518d_evidence.py
python3 tests/publish_fig518d_evidence.py --verify-only
```

Expected: contract tests pass and verifier reports `FIG518D_EVIDENCE_PASS; PAPER_POINTS=12; A1_14000_PASS=3`.

- [ ] **Step 5: Confirm no transient was rerun**

```bash
find data/provenance/steady53/fig5_18d -type f | sort
git diff --name-only -- final_steady_24a.slx final_dynamic_24a.slx '*.mat' \
  HeXe_property_simulink.m Lithium_property_simulink.m
```

Expected: only published provenance files appear; formal-file diff is empty. The `.mat` glob in the second command refers to root/formal tracked files; newly published evidence MAT files are expected additions under `data/provenance/`.

- [ ] **Step 6: Commit only Task 2**

```bash
git add tests/publish_fig518d_evidence.py tests/test_publish_fig518d_evidence.py \
  data/provenance/steady53/fig5_18d
git commit -m "固化图5.18d与散热器A1证据"
```

## Task 3: Rewire radiator diagnostics and harnesses to durable inputs

**Files:**

- Modify: `tests/radiator_a1_contract.py`
- Modify: `tests/test_radiator_a1_contract.py`
- Modify: `tests/prepare_radiator_a1_candidates.m`
- Modify: `tests/run_radiator_a1_candidate.m`
- Create from existing untracked file and modify: `tests/radiator_curve_energy_check.py`
- Create from existing untracked file and modify: `tests/radiator_parameter_family_check.py`
- Create from immutable helper source and modify: `tests/steady53/create_component_harness.m`
- Create from immutable helper source: `tests/steady53/steady53_component_boundaries.m`
- Create from immutable helper source: `tests/steady53/steady53_signal_manifest.m`
- Create from immutable helper source: `tests/steady53/reset_steady53_property_warning_state.m`
- Create from immutable helper source: `tests/steady53/run_steady53_case.m`
- Create: `tests/test_fig518d_durable_paths.py`

- [ ] **Step 1: Write a failing no-volatile-authority test**

Create `tests/test_fig518d_durable_paths.py`:

```python
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
FILES = (
    "tests/radiator_a1_contract.py",
    "tests/radiator_curve_energy_check.py",
    "tests/radiator_parameter_family_check.py",
    "tests/prepare_radiator_a1_candidates.m",
    "tests/run_radiator_a1_candidate.m",
    "tests/steady53/create_component_harness.m",
)


class DurablePathTests(unittest.TestCase):
    def test_no_volatile_authority_paths(self):
        combined = "\n".join((ROOT / name).read_text() for name in FILES)
        self.assertNotIn("tmp/steady53_curves_20260828/source_f8bcd83", combined)
        self.assertNotIn("tmp/steady53_curves_20260828/radiator_scan", combined)
        self.assertIn("data/provenance/baselines/f8bcd83", combined)
        self.assertIn("data/provenance/steady53/fig5_18d", combined)


if __name__ == "__main__":
    unittest.main(verbosity=2)
```

- [ ] **Step 2: Run RED**

```bash
python3 -m unittest -v tests.test_fig518d_durable_paths
```

Expected: failure showing the historical `tmp/steady53_curves_20260828` paths.

- [ ] **Step 3: Apply the minimal path-only changes**

First create the working helper copies from their immutable sources:

```bash
mkdir -p tests/steady53
for name in create_component_harness.m steady53_component_boundaries.m \
  steady53_signal_manifest.m reset_steady53_property_warning_state.m \
  run_steady53_case.m; do
  src="data/provenance/baselines/f8bcd83/runtime/tests/steady53/$name"
  dst="tests/steady53/$name"
  if [ -e "$dst" ] && ! cmp -s "$src" "$dst"; then
    echo "refusing to overwrite different helper: $dst" >&2
    exit 1
  fi
done
for name in create_component_harness.m steady53_component_boundaries.m \
  steady53_signal_manifest.m reset_steady53_property_warning_state.m \
  run_steady53_case.m; do
  src="data/provenance/baselines/f8bcd83/runtime/tests/steady53/$name"
  dst="tests/steady53/$name"
  [ -e "$dst" ] || cp "$src" "$dst"
  cmp -s "$src" "$dst" || exit 1
done
```

The first loop refuses any pre-existing byte mismatch. The second loop creates only missing files and verifies all five working copies byte-for-byte before applying path edits.

Use these definitions in Python diagnostics:

```python
REPO = Path(__file__).resolve().parents[1]
EVIDENCE = REPO / "data/provenance/steady53/fig5_18d"
SOURCE = REPO / "data/provenance/baselines/f8bcd83"
RUNTIME = SOURCE / "runtime"
SCAN_POINTS = EVIDENCE / "paper_curve/points.csv"
SCAN_PROVENANCE = EVIDENCE / "paper_curve/provenance.json"
```

Change `radiator_a1_contract.CURVE_EVIDENCE_HASHES` and its literal test to:

```python
CURVE_EVIDENCE_HASHES = {
    "data/provenance/steady53/fig5_18d/paper_curve/points.csv":
        "6aed804bf1ac57832055dab34483bdcb25567a5b902e5b3c6b85cb7129e8849b",
    "data/provenance/steady53/fig5_18d/paper_curve/provenance.json":
        "fe35a863731ff5394095f5d268a988cb45120a1382db9fd53bc0599e8f98e0cd",
}
```

In both A1 MATLAB entry points use:

```matlab
runtimeDir = fullfile(repo, 'data', 'provenance', 'baselines', ...
    'f8bcd83', 'runtime');
helperDir = fullfile(repo, 'tests', 'steady53');
assert(isfolder(runtimeDir) && isfolder(helperDir));
addpath(runtimeDir, helperDir, fullfile(repo, 'tests'));
evalin('base', "run('" + ...
    replace(fullfile(runtimeDir, 'start.m'), "'", "''") + "')");
```

In `create_component_harness.m`, replace its root-derived source with:

```matlab
repo = string(fileparts(fileparts(fileparts(mfilename('fullpath')))));
sourcePath = fullfile(repo, 'data', 'provenance', 'baselines', ...
    'f8bcd83', 'final_steady_24a.slx');
sourceModel = "final_steady_24a";
runtimeDir = fullfile(repo, 'data', 'provenance', 'baselines', ...
    'f8bcd83', 'runtime');
addpath(runtimeDir, fullfile(repo, 'tests', 'steady53'));
```

Put generated harnesses below `tmp/steady53/components/`; do not change boundaries, state initial conditions, solver, or component blocks.

- [ ] **Step 4: Run Python GREEN**

```bash
python3 -m unittest -v \
  tests.test_fig518d_durable_paths \
  tests.test_publish_fig518d_evidence \
  tests.test_radiator_a1_contract
python3 tests/radiator_curve_energy_check.py --self-test
python3 tests/radiator_parameter_family_check.py --self-test
```

Expected: all tests pass; no SLX simulation is executed.

- [ ] **Step 5: Run the two-candidate preparation regression only**

```bash
matlab -batch "addpath('tests','tests/steady53'); r=runtests('tests/test_prepare_radiator_a1_candidates.m'); assertSuccess(r)"
```

Expected: 1 MATLAB test passes. This creates and compiles two disposable candidates; it does not run 500 s or 14000 s simulations.

- [ ] **Step 6: Verify protected files and commit**

```bash
python3 tests/audit_cleanup_protected_manifest.py --verify-only \
  data/provenance/baselines/f8bcd83/protected_manifest_recovery.csv
git diff --check
git add tests/radiator_a1_contract.py tests/test_radiator_a1_contract.py \
  tests/prepare_radiator_a1_candidates.m tests/run_radiator_a1_candidate.m \
  tests/radiator_curve_energy_check.py tests/radiator_parameter_family_check.py \
  tests/steady53/create_component_harness.m \
  tests/steady53/steady53_component_boundaries.m \
  tests/steady53/steady53_signal_manifest.m \
  tests/steady53/reset_steady53_property_warning_state.m \
  tests/steady53/run_steady53_case.m tests/test_fig518d_durable_paths.py
git commit -m "迁移散热器诊断到耐久证据"
```

Expected: protected audit reports 34/34 resolved; only listed files are committed.

## Task 4: Digitize Figure 5.19 independently of the model

**Files:**

- Create: `tests/digitize_fig519.py`
- Create: `tests/test_digitize_fig519.py`
- Create by publisher: `data/provenance/steady53/fig5_19/source_page_106.png`
- Create by publisher: `data/provenance/steady53/fig5_19/paper_points.csv`
- Create by publisher: `data/provenance/steady53/fig5_19/provenance.json`
- Create by publisher: `data/provenance/steady53/fig5_19/digitization_overlay.png`
- Create by publisher: `data/provenance/steady53/fig5_19/manifest.csv`
- Create by publisher: `data/provenance/steady53/fig5_19/README.md`

- [ ] **Step 1: Write the failing calibration and trace tests**

Test the literal calibrations and bounded results:

```python
def test_literal_axis_calibration(self):
    self.assertEqual(digitizer.PANELS["reactor"].x_pair, (179, 503, 0.0, 500.0))
    self.assertEqual(digitizer.PANELS["reactor"].y_pair, (341, 593, 3750.0, 1750.0))
    self.assertEqual(digitizer.PANELS["turbine"].y_pair, (338, 580, 2300.0, 1800.0))
    self.assertEqual(digitizer.PANELS["compressor"].y_pair, (675, 925, 1350.0, 1100.0))
    self.assertEqual(digitizer.PANELS["electrical"].y_pair, (701, 925, 1100.0, 600.0))

def test_extracted_points_are_model_independent_and_bounded(self):
    rows = digitizer.extract_points(digitizer.SOURCE_PAGE)
    self.assertEqual(len(rows), 60)
    by_panel = digitizer.group_by_panel(rows)
    self.assertTrue(3150 < by_panel["reactor"][0]["power_kW"] < 3225)
    self.assertTrue(2640 < by_panel["reactor"][-1]["power_kW"] < 2690)
    self.assertTrue(2190 < by_panel["turbine"][-1]["power_kW"] < 2230)
    self.assertTrue(1200 < by_panel["compressor"][-1]["power_kW"] < 1225)
    self.assertTrue(985 < by_panel["electrical"][-1]["power_kW"] < 1015)
```

Also assert source page SHA256 `770d193eaca80742ef5ece0ef5ba6d0bc20ad7aaa8ca2ac9b60a4799d1f0a1e2`, 15 fixed sample times per panel, and `paper_reproduced=false` in generated metadata.

The only accepted source page is:

```python
SOURCE_PAGE = ROOT / "tmp/steady53_recheck_20260827/paper-106.png"
SOURCE_PAGE_SHA256 = "770d193eaca80742ef5ece0ef5ba6d0bc20ad7aaa8ca2ac9b60a4799d1f0a1e2"
THESIS_PDF_SHA256 = "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a"
```

The digitizer must hash-gate this file before reading it and publish the same bytes as `data/provenance/steady53/fig5_19/source_page_106.png`. It must refuse any pre-existing destination with a different hash.

- [ ] **Step 2: Run RED**

```bash
python3 -m unittest -v tests.test_digitize_fig519
```

Expected: import failure for `tests.digitize_fig519`.

- [ ] **Step 3: Implement deterministic backward trace extraction**

Use these complete data definitions:

```python
@dataclass(frozen=True)
class Panel:
    panel_id: str
    x_pair: tuple[int, int, float, float]
    y_pair: tuple[int, int, float, float]
    power_allowance_kW: float


PANELS = {
    "reactor": Panel("a", (179, 503, 0.0, 500.0),
                     (341, 593, 3750.0, 1750.0), 25.0),
    "turbine": Panel("b", (555, 880, 0.0, 500.0),
                     (338, 580, 2300.0, 1800.0), 6.0),
    "compressor": Panel("c", (179, 503, 0.0, 500.0),
                        (675, 925, 1350.0, 1100.0), 3.0),
    "electrical": Panel("d", (555, 881, 0.0, 500.0),
                        (701, 925, 1100.0, 600.0), 8.0),
}
SAMPLE_TIMES = (10, 15, 20, 30, 40, 50, 75, 100, 150, 200,
                230, 300, 400, 450, 495)
```

For each panel, process sample times from 495 s backward. At each mapped x-column, combine `x-1:x+1`, threshold grayscale `<120`, split contiguous dark-pixel y groups, and choose the group whose center is nearest the already accepted later-time center. Reject empty columns, axis-border groups, or jumps over 80 pixels. Convert pixels by the two literal calibration pairs. This is image-trace continuity, not model-guided point selection.

Write the CSV columns required by the design plus `power_allowance_kW=panel.power_allowance_kW` and `time_allowance_s=3`. Write the original PDF hash `983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a`, page identity, thresholds, fixed sample times, and limitations to `provenance.json`. Plot every accepted pixel on the untouched source page in `digitization_overlay.png`.

- [ ] **Step 4: Run GREEN, publish, and visually inspect overlay**

```bash
python3 -m unittest -v tests.test_digitize_fig519
python3 tests/digitize_fig519.py
python3 tests/digitize_fig519.py --verify-only
```

Expected: 60 points, four panels, source hash match, and no model files read by the digitizer. Open the overlay and confirm every marker lies on the intended black trace; if a marker is wrong, adjust only the image-tracing rule or fixed sample time, never by consulting a model curve.

- [ ] **Step 5: Commit Task 4**

```bash
git add tests/digitize_fig519.py tests/test_digitize_fig519.py \
  data/provenance/steady53/fig5_19
git commit -m "建立图5.19功率曲线数字化证据"
```

## Task 5: Preserve and analyze the existing flat power baseline

**Files:**

- Create: `tests/analyze_fig519_baseline.py`
- Create: `tests/test_analyze_fig519_baseline.py`
- Add by hash-gated publication: `data/provenance/steady53/fig5_19/model_baseline/baseline.mat`
- Add by hash-gated publication: `data/provenance/steady53/fig5_19/model_baseline/baseline_P_sw.csv`
- Add by hash-gated publication: `data/provenance/steady53/fig5_19/model_baseline/baseline_WT_sw.csv`
- Add by hash-gated publication: `data/provenance/steady53/fig5_19/model_baseline/baseline_Wc_sw.csv`
- Create: `data/provenance/steady53/fig5_19/baseline_metrics.json`
- Create: `data/provenance/steady53/fig5_19/signal_contract.json`

- [ ] **Step 1: Write failing baseline tests**

Tests must require:

```python
def test_saved_baseline_is_flat_but_not_paper_reproduction(self):
    result = analysis.analyze()
    self.assertLess(result["signals"]["reactor"]["peak_to_peak_W"], 0.2)
    self.assertLess(result["signals"]["turbine"]["peak_to_peak_W"], 0.2)
    self.assertLess(result["signals"]["compressor"]["peak_to_peak_W"], 0.3)
    self.assertLess(result["signals"]["electrical_paper_eta"]["peak_to_peak_W"], 0.5)
    self.assertFalse(result["paper_reproduced"])

def test_electrical_definitions_remain_separate(self):
    result = analysis.analyze()
    self.assertEqual(result["electrical"]["paper_eta"], 0.98)
    self.assertEqual(result["electrical"]["historical_metric_eta"], 0.96527)
    self.assertEqual(result["electrical"]["direct_generator_signal"], None)
    self.assertGreater(result["electrical"]["final_definition_gap_kW"], 15.0)
```

Also require exact 14000 s final time, monotonically nondecreasing times, finite values, PDF/baseline/model hashes, and four separate paper/model comparisons.

- [ ] **Step 2: Run RED**

```bash
python3 -m unittest -v tests.test_analyze_fig519_baseline
```

Expected: import failure for `tests.analyze_fig519_baseline`.

- [ ] **Step 3: Publish the saved raw baseline byte-for-byte**

Extend the Figure 5.19 manifest publisher with the four exact source files below. Compute and freeze their SHA256 before copying; do not rerun the model:

```text
tmp/steady53_curves_20260828/results/baseline.mat
tmp/steady53_curves_20260828/results/baseline_P_sw.csv
tmp/steady53_curves_20260828/results/baseline_WT_sw.csv
tmp/steady53_curves_20260828/results/baseline_Wc_sw.csv
```

Run the publisher twice, with the second run in `--verify-only` mode. Expected: destination hashes equal source hashes and the formal model hash remains unchanged.

- [ ] **Step 4: Implement baseline arithmetic and comparison**

`analyze()` must:

1. load the three CSV series in watts;
2. assert identical time vectors ending at 14000 s;
3. compute `shaft_net = turbine - compressor`;
4. compute two explicitly named derived series: `0.98*shaft_net` and `0.96527*shaft_net`;
5. never label either derived series as a direct generator output;
6. compare only the first 500 s to the 60 paper points using linear interpolation of the unmodified model series;
7. write peak-to-peak, start, end, RMSE, max error, peak/valley direction, and per-panel squared-error contribution;
8. emit `paper_reproduced=false` and `formal_promotion=false`.

Write `signal_contract.json` with exactly these identities:

```json
{
  "reactor": {"model_signal": "P_sw", "kind": "direct_workspace_signal", "api_trace_status": "required_in_task_6"},
  "turbine": {"model_signal": "WT_sw", "kind": "direct_component_power", "api_trace_status": "required_in_task_6"},
  "compressor": {"model_signal": "Wc_sw", "kind": "direct_component_power", "api_trace_status": "required_in_task_6"},
  "electrical_paper_eta": {"formula": "0.98*(WT_sw-Wc_sw)", "kind": "offline_derived", "direct_generator_signal": null},
  "electrical_historical_metric": {"formula": "0.96527*(WT_sw-Wc_sw)", "kind": "historical_offline_derived", "accepted_for_fig519": false},
  "paper_reproduced": false,
  "formal_promotion": false
}
```

`required_in_task_6` is a fixed workflow status, not an unknown implementation placeholder. Task 6 must replace it with a completed API trace record before the phase report can pass.

- [ ] **Step 5: Run GREEN and verify deterministic reread**

```bash
python3 -m unittest -v tests.test_analyze_fig519_baseline
python3 tests/analyze_fig519_baseline.py
python3 tests/analyze_fig519_baseline.py --verify-only
```

Expected: tests pass, flatness limits hold, and the second run performs no writes.

- [ ] **Step 6: Commit Task 5**

```bash
git add tests/analyze_fig519_baseline.py tests/test_analyze_fig519_baseline.py \
  data/provenance/steady53/fig5_19/model_baseline \
  data/provenance/steady53/fig5_19/baseline_metrics.json \
  data/provenance/steady53/fig5_19/signal_contract.json \
  data/provenance/steady53/fig5_19/manifest.csv
git commit -m "固化图5.19当前平直功率基线"
```

## Task 6: Audit initialization and direct power paths with official APIs

**Files:**

- Modify working copy: `tests/steady53/run_steady53_case.m`
- Create: `tests/audit_fig519_initialization.m`
- Create: `tests/test_audit_fig519_initialization.m`
- Create at runtime: `tmp/fig519_initialization_20260831_A1/raw_reference.mat`
- Publish summary: `data/provenance/steady53/fig5_19/initialization_audit.json`
- Modify: `data/provenance/steady53/fig5_19/signal_contract.json`

- [ ] **Step 1: Adapt the recovered runner to the durable runtime**

In `tests/steady53/run_steady53_case.m`, set:

```matlab
repo = string(fileparts(fileparts(fileparts(mfilename('fullpath')))));
runtimeDir = fullfile(repo, 'data', 'provenance', 'baselines', ...
    'f8bcd83', 'runtime');
startPath = fullfile(runtimeDir, 'start.m');
addpath(runtimeDir, fullfile(repo, 'tests', 'steady53'));
```

Keep all cleanup, warning escalation, logging, source-hash-before/after, and no-save behavior. Do not change `etaGenerator=0.96527`; it remains a named historical metric and is not used as the Figure 5.19 accepted electrical definition.

- [ ] **Step 2: Write the failing MATLAB audit test**

The test creates a unique `tmp/` directory and requires:

```matlab
result = audit_fig519_initialization(outputDir);
verifyEqual(testCase, result.model_sha256, ...
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
verifyEqual(testCase, result.state_count, 40);
verifyEqual(testCase, result.reference_final_time_s, 500);
verifyTrue(testCase, result.reference_success);
verifyFalse(testCase, result.direct_generator_signal_found);
verifyTrue(testCase, result.source_hash_unchanged);
verifyFalse(testCase, result.paper_reproduced);
verifyFalse(testCase, result.formal_promotion);
verifyNotEmpty(testCase, result.solver_contract.solver_name);
verifyTrue(testCase, result.solver_contract.stop_time_dependency_checked);
verifyTrue(testCase, result.boundary_contract.all_inputs_classified);
verifyTrue(testCase, result.initial_residuals.all_items_accounted_for);
verifyTrue(testCase, result.flat_start_explanation.has_state_evidence);
verifyTrue(testCase, result.flat_start_explanation.has_signal_path_evidence);
```

Also require `reactor/Integrator6` initial condition `2660960.9141046703`, reactor temperature initial condition `1721.8648882133552`, 34 resolved protected entries, and the following fixed JSON sections:

```text
state_inventory
boundary_contract
solver_contract
power_signal_paths
initial_residuals
flat_start_explanation
```

`initial_residuals` must contain the named records `reactor_power_derivative`, `shaft_excess_power`, `ihx_energy`, `recuperator_energy`, `precooler_energy`, and `radiator_energy`. Each record must be either `status="computed"` with value, unit, formula and source paths, or `status="not_observable"` with the exact missing direct signals. Missing observability is recorded as evidence and must not be replaced by an inferred fitted value.

- [ ] **Step 3: Run RED**

```bash
matlab -batch "addpath('tests','tests/steady53'); r=runtests('tests/test_audit_fig519_initialization.m'); assertSuccess(r)"
```

Expected: undefined function `audit_fig519_initialization`.

- [ ] **Step 4: Implement the API audit and one justified reference run**

`audit_fig519_initialization(outputDir)` must:

1. verify `outputDir` is a new directory below repository `tmp/`;
2. verify the immutable baseline SHA256;
3. add only durable runtime and `tests/steady53` to path;
4. run durable `start.m` in a base-workspace snapshot;
5. load the baseline without saving;
6. obtain the 40 state paths from `steady53_signal_manifest` and read each `InitialCondition` with `get_param`;
7. use `get_param(model,'Solver')`, `get_param(model,'SolverType')`, `get_param(model,'FixedStep')`, `get_param(model,'MaxStep')`, `get_param(model,'StopTime')`, compiled sample-time APIs, and all root Inport source blocks to classify solver, sample-time, StopTime dependence, and every fixed/time-varying boundary input;
8. execute `blocks=find_system(model,'FollowLinks','on','LookUnderMasks','all','BlockType','ToWorkspace')`, filter with `strcmp(string(get_param(blocks,'VariableName')),'P_sw')`, require exactly one result, and record its upstream source through `get_param(block,'PortConnectivity')`;
9. record the direct turbine path `TAC/Turbine` output 4 and compressor path `TAC/Compressor` output 2 from the manifest;
10. search all To Workspace and Outport blocks for a direct TAC generator/electrical power signal and record the negative result rather than inventing one;
11. trace the paths needed for reactor-power derivative, shaft excess power, and IHX/recuperator/precooler/radiator energy residuals; for each named residual, record either the exact formula/unit/source paths and computed value or the exact direct signals that are absent;
12. close the model without saving;
13. call `run_steady53_case(modelPath,500,true)` exactly once to obtain all states and direct signals;
14. calculate each state’s t=0 value, 500 s value, absolute change, relative change where defined, and first-sample slope;
15. write `flat_start_explanation` as a machine-readable list of the specific near-zero state derivatives and their traced paths to each of the four power definitions; a generic `initial_conditions_wrong` label is forbidden;
16. save the unmodified `runResult` to `raw_reference.mat` and write a compact `initialization_audit.json`;
17. recheck source and protected hashes.

The JSON must include `reference_run_reason="missing direct state and derivative evidence in prior saved baseline"`, `repeated_prior_experiment=false`, `paper_reproduced=false`, and `formal_promotion=false`.

- [ ] **Step 5: Run GREEN and publish only the compact summary**

```bash
matlab -batch "addpath('tests','tests/steady53'); r=runtests('tests/test_audit_fig519_initialization.m'); assertSuccess(r)"
```

Expected: one 500 s unmodified instrumented reference completes; the test reports 40 states and unchanged source hash.

Copy the verified JSON through the Figure 5.19 publisher into `data/provenance/steady53/fig5_19/initialization_audit.json`. Keep `raw_reference.mat` in its unique `tmp/` directory and add its SHA256 and absolute/relative location to the durable manifest.

Replace the three `api_trace_status` fields in `signal_contract.json` with the actual block paths and `status="verified_by_official_api"`; set the electrical entry to `status="no_direct_generator_signal_found"`.

- [ ] **Step 6: Verify and commit Task 6**

```bash
python3 tests/analyze_fig519_baseline.py --verify-only
python3 tests/audit_cleanup_protected_manifest.py --verify-only \
  data/provenance/baselines/f8bcd83/protected_manifest_recovery.csv
git diff --check
git add tests/steady53/run_steady53_case.m tests/audit_fig519_initialization.m \
  tests/test_audit_fig519_initialization.m \
  data/provenance/steady53/fig5_19/initialization_audit.json \
  data/provenance/steady53/fig5_19/signal_contract.json \
  data/provenance/steady53/fig5_19/manifest.csv
git commit -m "审计图5.19初始状态与功率信号链"
```

## Task 7: Run the first single-variable falsification experiment

**Files:**

- Create: `tests/create_fig519_reactor_ic_candidate.m`
- Create: `tests/run_fig519_reactor_ic_counterfactual.m`
- Create: `tests/analyze_fig519_counterfactual.py`
- Create: `tests/test_fig519_counterfactual.py`
- Create at runtime: `tmp/fig519_reactor_ic_20260831_A1/**`
- Publish summary: `data/provenance/steady53/fig5_19/reactor_ic_counterfactual.json`

- [ ] **Step 1: Write the failing exact-one-change test**

The Python test must inspect the candidate audit and require:

```python
self.assertEqual(audit["changed_blocks"], ["reactor/Integrator6"])
self.assertEqual(audit["changed_parameters"], ["InitialCondition"])
self.assertEqual(audit["source_sha256"],
                 "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391")
self.assertEqual(audit["candidate_value_identity"],
                 "figure_5_19_digitized_t10_proxy_not_author_t0")
self.assertFalse(audit["paper_reproduced"])
self.assertFalse(audit["formal_promotion"])
```

Also require unchanged solver, all other 39 state initial conditions, runtime dependencies, MAT files, property files, and protected manifest.

- [ ] **Step 2: Run RED**

```bash
python3 -m unittest -v tests.test_fig519_counterfactual
```

Expected: missing candidate audit/analyzer implementation.

- [ ] **Step 3: Implement the API candidate generator**

`create_fig519_reactor_ic_candidate(runDir)` must:

1. create `runDir` below `tmp/` and refuse an existing destination;
2. copy the immutable baseline to `runDir/candidate.slx` and verify the source hash;
3. read the earliest reactor row from durable `paper_points.csv`; it must be the fixed 10 s sample;
4. set only `candidate/reactor/Integrator6.InitialCondition` to `1000*power_kW`;
5. save, close, reopen, and update the candidate through official APIs;
6. compare all 40 state IC strings and model solver parameters to the source;
7. write `patch_audit.json` with exact changed path/parameter and the identity string above;
8. leave the source model byte-identical.

This experiment is explicitly circular as a reproduction validation and therefore may only answer the falsification question: “Can the full four-power transient be explained by changing the reactor power state alone?” It must never be used to declare Figure 5.19 reproduced.

- [ ] **Step 4: Implement the blocking runner and analyzer**

The MATLAB runner calls `run_steady53_case(candidatePath,500,true)`, saves raw output below `runDir/run/`, and verifies candidate/source/protected hashes before and after.

The Python analyzer must calculate:

- reactor, turbine, compressor, `0.98*shaft_net`, and historical `0.96527*shaft_net` raw curves;
- paper-point RMSE, maximum error, start/end error, peak/valley direction and time;
- change relative to the unmodified instrumented reference;
- whether reactor response became non-flat relative to 10× reference peak-to-peak noise;
- whether each TAC power became non-flat by the same predeclared noise-ratio rule;
- whether all four paper direction sequences were reproduced.

Its conclusion enum is exactly one of:

```text
reactor_ic_alone_falsified
reactor_ic_alone_not_falsified_but_not_validated
numerical_or_physical_gate_failed
```

It always writes `paper_reproduced=false`, `author_initial_state_identified=false`, and `formal_promotion=false`.

- [ ] **Step 5: Run GREEN tests, then the one approved experiment**

```bash
python3 -m unittest -v tests.test_fig519_counterfactual
matlab -batch "addpath('tests','tests/steady53'); runDir=fullfile(pwd,'tmp','fig519_reactor_ic_20260831_A1'); create_fig519_reactor_ic_candidate(runDir); run_fig519_reactor_ic_counterfactual(runDir)"
python3 tests/analyze_fig519_counterfactual.py tmp/fig519_reactor_ic_20260831_A1
python3 tests/analyze_fig519_counterfactual.py tmp/fig519_reactor_ic_20260831_A1 --verify-only
```

Expected process result: candidate reaches 500 s or produces a preserved, classified model failure; hashes remain unchanged. Do not prescribe the scientific conclusion before reading the output.

- [ ] **Step 6: Publish the compact summary and commit**

Publish only `patch_audit.json`, the compact analysis JSON, raw-output SHA256/location, and run status into `reactor_ic_counterfactual.json`. Keep raw MAT/CSV and candidate SLX in the unique `tmp/` run directory.

```bash
git add tests/create_fig519_reactor_ic_candidate.m \
  tests/run_fig519_reactor_ic_counterfactual.m \
  tests/analyze_fig519_counterfactual.py tests/test_fig519_counterfactual.py \
  data/provenance/steady53/fig5_19/reactor_ic_counterfactual.json \
  data/provenance/steady53/fig5_19/manifest.csv
git commit -m "验证图5.19反应堆功率初值单变量假设"
```

## Task 8: Publish the evidence-ranked phase report and run the full gate

**Files:**

- Create: `docs/steady53_fig519_progress_20260831.md`
- Create: `tests/test_fig519_end_to_end_contract.py`
- Modify: `data/provenance/steady53/fig5_19/README.md`

- [ ] **Step 1: Write the failing end-to-end contract test**

Require all durable artifacts, all manifest hashes, four digitized panels, completed API signal identities, baseline/reference/counterfactual summaries, and these fixed gates:

```python
self.assertFalse(status["figure_5_18d_reproduced"])
self.assertFalse(status["figure_5_19_reproduced"])
self.assertFalse(status["section_5_3_reproduced"])
self.assertFalse(status["section_5_4_reproduced"])
self.assertFalse(status["formal_model_modified"])
self.assertFalse(status["formal_promotion"])
```

The test must reject `selected_best_candidate`, automatic envelope expansion, time shifting, smoothing, a fitted electrical efficiency, or a claim that the digitized t=10 reactor value is the author’s t=0 initial condition.

- [ ] **Step 2: Run RED**

```bash
python3 -m unittest -v tests.test_fig519_end_to_end_contract
```

Expected: missing final report/status fields.

- [ ] **Step 3: Write the report from evidence, not expectation**

The report must contain:

1. ✅ exact files/runs completed in this phase;
2. ✅ Figure 5.18(d) freeze result and A1 non-uniqueness;
3. ✅ paper Figure 5.19 digitization method and scan allowances;
4. ✅ direct/derived signal identities and the absence/presence of a direct generator signal;
5. ✅ current initialization inventory and why the original baseline is flat, naming specific states and paths;
6. ❓ the single-variable experiment result, explicitly bounded to that candidate;
7. ❌ what remains unknown about the author’s full initial-state vector and boundary application;
8. a next action chosen by the actual enum from Task 7, without adding a second experiment in this phase;
9. fixed `paper_reproduced=false` and no-formal-change statements unless all approved independent gates truly passed.

Update the Figure 5.19 README to point to the report and list the result enum verbatim.

- [ ] **Step 4: Run the full fresh verification**

```bash
python3 -m unittest -v \
  tests.test_publish_f8bcd83_runtime \
  tests.test_publish_fig518d_evidence \
  tests.test_fig518d_durable_paths \
  tests.test_radiator_a1_contract \
  tests.test_digitize_fig519 \
  tests.test_analyze_fig519_baseline \
  tests.test_fig519_counterfactual \
  tests.test_fig519_end_to_end_contract
python3 tests/publish_f8bcd83_runtime.py --verify-only
python3 tests/publish_fig518d_evidence.py --verify-only
python3 tests/digitize_fig519.py --verify-only
python3 tests/analyze_fig519_baseline.py --verify-only
python3 tests/audit_cleanup_protected_manifest.py --verify-only \
  data/provenance/baselines/f8bcd83/protected_manifest_recovery.csv
matlab -batch "addpath('tests','tests/steady53'); r=runtests({'tests/test_prepare_radiator_a1_candidates.m','tests/test_audit_fig519_initialization.m'}); assertSuccess(r)"
git diff --check
git diff --name-only -- final_steady_24a.slx final_dynamic_24a.slx '*.mat' \
  HeXe_property_simulink.m Lithium_property_simulink.m
```

Expected:

- all Python tests pass;
- all verify-only commands pass without writes;
- both MATLAB tests pass;
- 34/34 protected items resolve with no mismatch;
- no whitespace errors;
- formal-file diff is empty.

- [ ] **Step 5: Commit the report and final contract**

```bash
git add docs/steady53_fig519_progress_20260831.md \
  tests/test_fig519_end_to_end_contract.py \
  data/provenance/steady53/fig5_19/README.md
git commit -m "记录图5.19初始化根因阶段结果"
```

- [ ] **Step 6: Stop at the scientific decision gate**

Do not start a second counterfactual automatically. Report one of these next actions:

- if `reactor_ic_alone_falsified`: identify the next single state family from the measured influence graph and request approval for its written experiment specification;
- if `reactor_ic_alone_not_falsified_but_not_validated`: seek an independent source for that initial state before any promotion discussion;
- if `numerical_or_physical_gate_failed`: trace the failure upstream before proposing another initial-state change.

In every branch, keep the formal steady and dynamic models unchanged.
