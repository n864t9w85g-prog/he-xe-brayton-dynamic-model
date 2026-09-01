# IHX R2 He-Xe Thermal-State Shift A3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, preflight, execute exactly once after a separate approval, and evidence-rank the `20260901_A3` IHX region-2 He-Xe two-state/one-scalar 500 s counterfactual without modifying or promoting a formal model.

**Architecture:** A pure-Python contract fixes the decimal candidate and scientific state machine. MATLAB API code creates and audits a candidate copy and a one-call runner. A Python preflight builds a self-contained captured repository snapshot, while a captured one-shot executor owns the only authorized MATLAB invocation. Offline analysis publishes raw evidence and a cross-family history transactionally after the run.

**Tech Stack:** Python 3 (`unittest`, `decimal`, `hashlib`, `json`, `csv`, `subprocess`), MATLAB/Simulink R2025a official APIs, Git, SHA-256, JSON/CSV/MAT artifacts.

---

## Fixed authority boundaries

- The approved design is `docs/superpowers/specs/2026-09-01-ihx-r2-hexe-shift-a3-design.md` at commit `b248299`.
- The approved dependency-closure amendment is
  `docs/superpowers/specs/2026-09-01-a3-capture-dependency-closure-design.md`
  at commit `fd83c06`; its implementation plan is
  `docs/superpowers/plans/2026-09-01-a3-capture-dependency-closure.md`.
- The dependency-closure amendment supersedes the original Task 5 dependency
  list wherever they differ. Complete its Tasks 1–5 and both review gates
  before starting this plan's Task 5 runtime capture.
- Tasks 1–5 are zero-simulation implementation and preflight work.
- Task 6 is a hard human gate. Do not execute it until the user explicitly says **“批准 A3 单次正式运行”** after the READY evidence is reported.
- The first formal command invocation consumes A3. Never retry it automatically, even if no model integration occurred.
- Tasks 7–8 are offline publication and verification only; they must not invoke the model again.
- Never modify `final_steady_24a.slx`, `final_dynamic_24a.slx`, root `*.mat`, `HeXe_property_simulink.m`, or `Lithium_property_simulink.m`.

## File-responsibility map

| File | Single responsibility |
|---|---|
| `tests/fig519_ihx_r2_hexe_contract.py` | Immutable decimal values, direction/nonflat gates, enums, and false promotion flags |
| `tests/publish_fig518a_anchor_evidence.py` | Publish/verify the fixed Figure 5.18(a) source page and anchor provenance |
| `tests/create_fig519_ihx_r2_hexe_shift_candidate.m` | Create and audit the two-IC/one-delta candidate through official APIs; never simulate |
| `tests/run_fig519_ihx_r2_hexe_shift.m` | Invoke captured `run_steady53_case` once and write raw/status/curves |
| `tests/analyze_fig519_ihx_r2_hexe_shift.py` | Validate A3 artifacts, compute fixed metrics, classify, and publish durable evidence/history |
| `tests/prepare_fig519_ihx_r2_hexe_a3.py` | Build and verify the self-contained read-only captured repository snapshot |
| `tests/execute_fig519_ihx_r2_hexe_a3_once.py` | Own the exact-once subprocess call and immutable execution record |
| `tests/publish_a3_capture_dependency_closure.py` | Publish and verify the repository-local protected/formal dependency closure |
| `tests/test_fig519_ihx_r2_hexe_contract.py` | Pure contract and analyzer tests, including `python -O`-safe failures |
| `tests/test_publish_a3_capture_dependency_closure.py` | Portable archive, formal-state, collision, symlink, and no-external-read tests |
| `tests/test_publish_fig518a_anchor_evidence.py` | Anchor publisher integrity, idempotence, symlink, and no-write tests |
| `tests/test_prepare_fig519_ihx_r2_hexe_a3.py` | Capture completeness, self-containment, exact-once, and tamper tests |
| `tests/test_create_fig519_ihx_r2_hexe_shift_candidate.m` | MATLAB no-simulation candidate/API tests |
| `tests/test_run_fig519_ihx_r2_hexe_shift.m` | MATLAB no-simulation runner hook and marker tests |
| `data/provenance/steady53/fig5_18a/*` | Durable 1200 K visual-proxy source evidence |
| `data/provenance/baselines/f8bcd83/portable_protected_manifest.json` | Exact 34-row repository-local protected-object mapping |
| `data/provenance/baselines/f8bcd83/formal_root_state.json` | Exact eight-record formal-root presence/hash state |
| `data/provenance/baselines/f8bcd83/protected_objects/**` | One immutable repository-local byte object for each protected logical row |
| `data/provenance/steady53/fig5_19/ihx_r2_hexe_shift_A3/*` | Durable A3 execution, raw, curves, and analysis evidence |
| `data/provenance/steady53/fig5_19/initial_state_counterfactual_history.json` | Cross-family append-only attempt index |

### Task 1: Freeze the pure A3 contract and Figure 5.18(a) anchor

**Files:**
- Create: `tests/fig519_ihx_r2_hexe_contract.py`
- Create: `tests/test_fig519_ihx_r2_hexe_contract.py`
- Create: `tests/publish_fig518a_anchor_evidence.py`
- Create: `tests/test_publish_fig518a_anchor_evidence.py`
- Create by publisher: `data/provenance/steady53/fig5_18a/README.md`
- Create by publisher: `data/provenance/steady53/fig5_18a/source_page_105.png`
- Create by publisher: `data/provenance/steady53/fig5_18a/provenance.json`
- Create by publisher: `data/provenance/steady53/fig5_18a/manifest.csv`

- [ ] **Step 1: Write the failing decimal and state-machine tests**

```python
from decimal import Decimal
import unittest

from tests.fig519_ihx_r2_hexe_contract import (
    ANCHOR_IDENTITY, ATTEMPT_ID, NONFLAT_THRESHOLDS_W,
    PAPER_DIRECTIONS, SOURCE_MODEL_SHA256, candidate_contract, classify,
    promotion_flags,
)

class IhxR2HeXeContractTests(unittest.TestCase):
    def test_one_decimal_delta_drives_both_states(self):
        c = candidate_contract()
        self.assertEqual(ATTEMPT_ID, "20260901_A3")
        self.assertEqual(
            ANCHOR_IDENTITY,
            "figure_5_18a_t0_visual_proxy_not_author_initial_state",
        )
        self.assertEqual(c["anchor_K"], Decimal("1200.0000000000000"))
        self.assertEqual(c["delta_T_K"], Decimal("-193.6037139151003"))
        self.assertEqual(c["new_average_K"], Decimal("1052.2147530693003"))
        self.assertEqual(c["new_outlet_K"], Decimal("1200.0000000000000"))
        self.assertEqual(c["old_gap_K"], c["new_gap_K"])
        self.assertEqual(c["new_gap_K"], Decimal("147.7852469306997"))
        self.assertEqual(
            SOURCE_MODEL_SHA256,
            "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391",
        )

    def test_full_four_panel_gate_is_mechanical(self):
        self.assertEqual(PAPER_DIRECTIONS["reactor"], ("fall",))
        self.assertEqual(PAPER_DIRECTIONS["turbine"], ("rise",))
        self.assertEqual(PAPER_DIRECTIONS["compressor"], ("fall", "rise"))
        self.assertEqual(PAPER_DIRECTIONS["electrical_paper_eta"], ("rise", "fall"))
        self.assertEqual(
            NONFLAT_THRESHOLDS_W["compressor"],
            Decimal("2.2659989586099982"),
        )
        self.assertEqual(
            classify(True, PAPER_DIRECTIONS, {name: True for name in PAPER_DIRECTIONS}),
            "ihx_r2_hexe_shift_alone_not_falsified_but_not_validated",
        )
        failed = dict(PAPER_DIRECTIONS)
        failed["compressor"] = ()
        self.assertEqual(
            classify(True, failed, {name: True for name in PAPER_DIRECTIONS}),
            "ihx_r2_hexe_shift_alone_falsified",
        )
        self.assertEqual(
            classify(False, {}, {}), "numerical_or_physical_gate_failed"
        )
        self.assertEqual(
            promotion_flags(),
            {"paper_reproduced": False,
             "author_initial_state_identified": False,
             "formal_promotion": False},
        )
```

- [ ] **Step 2: Run RED**

Run:

```bash
python3 -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
```

Expected: `ModuleNotFoundError: No module named 'tests.fig519_ihx_r2_hexe_contract'`.

- [ ] **Step 3: Implement the exact pure contract without `assert`**

Create this public core in `tests/fig519_ihx_r2_hexe_contract.py`:

```python
from decimal import Decimal
from collections.abc import Mapping, Sequence

ATTEMPT_ID = "20260901_A3"
ANCHOR_IDENTITY = "figure_5_18a_t0_visual_proxy_not_author_initial_state"
SOURCE_MODEL_SHA256 = "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391"
AVERAGE_PATH = "final_steady_24a/IHX/IHX_region_2/T_c1_average_Integrator"
OUTLET_PATH = "final_steady_24a/IHX/IHX_region_2/T_c2_out_Integrator"
OLD_AVERAGE_K = Decimal("1245.8184669844006")
OLD_OUTLET_K = Decimal("1393.6037139151003")
ANCHOR_K = Decimal("1200.0000000000000")
PAPER_DIRECTIONS = {
    "reactor": ("fall",),
    "turbine": ("rise",),
    "compressor": ("fall", "rise"),
    "electrical_paper_eta": ("rise", "fall"),
}
NONFLAT_THRESHOLDS_W = {
    "reactor": Decimal("0.5141158541664481"),
    "turbine": Decimal("1.609319536946714"),
    "compressor": Decimal("2.2659989586099982"),
    "electrical_paper_eta": Decimal("3.7926344096194953"),
}

class ContractError(RuntimeError):
    pass

def candidate_contract() -> dict[str, Decimal]:
    delta = ANCHOR_K - OLD_OUTLET_K
    new_average = OLD_AVERAGE_K + delta
    new_outlet = OLD_OUTLET_K + delta
    result = {
        "anchor_K": ANCHOR_K, "delta_T_K": delta,
        "old_average_K": OLD_AVERAGE_K, "old_outlet_K": OLD_OUTLET_K,
        "new_average_K": new_average, "new_outlet_K": new_outlet,
        "old_gap_K": OLD_OUTLET_K - OLD_AVERAGE_K,
        "new_gap_K": new_outlet - new_average,
    }
    if result["old_gap_K"] != result["new_gap_K"]:
        raise ContractError("one-scalar gap preservation failed")
    return result

def promotion_flags() -> dict[str, bool]:
    return {"paper_reproduced": False,
            "author_initial_state_identified": False,
            "formal_promotion": False}

def classify(numerical_gate: bool,
             directions: Mapping[str, Sequence[str]],
             nonflat: Mapping[str, bool]) -> str:
    if not numerical_gate:
        return "numerical_or_physical_gate_failed"
    complete = all(tuple(directions.get(name, ())) == expected
                   and nonflat.get(name) is True
                   for name, expected in PAPER_DIRECTIONS.items())
    return ("ihx_r2_hexe_shift_alone_not_falsified_but_not_validated"
            if complete else "ihx_r2_hexe_shift_alone_falsified")
```

- [ ] **Step 4: Add anchor publication tests and publisher**

The test must lock these literals and reject any symlink, extra file, mismatched hash, or verify-only write:

```python
PDF_SHA = "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a"
PAGE_SHA = "da9e9a536d0dda98152fa694d942b393ca2f5f5d10b720dbd79692ac694cc95c"
EXPECTED = {
    "pdf_page": 105,
    "printed_page": 90,
    "figure": "5.18(a)",
    "anchor_K": "1200.0000000000000",
    "anchor_identity": ANCHOR_IDENTITY,
    "paper_reproduced": False,
    "formal_promotion": False,
}
```

`publish_fig518a_anchor_evidence.py` must use exclusive staged files, fsync, manifest-last commit, and a `--verify-only` path that recomputes the page/PDF hashes and writes nothing. Publish the existing byte-identical `paper-105.png`; do not redraw or enhance it.

- [ ] **Step 5: Run GREEN in normal and optimized modes**

Run:

```bash
python3 -m unittest -v \
  tests.test_fig519_ihx_r2_hexe_contract \
  tests.test_publish_fig518a_anchor_evidence
python3 -O -m unittest -v \
  tests.test_fig519_ihx_r2_hexe_contract \
  tests.test_publish_fig518a_anchor_evidence
python3 tests/publish_fig518a_anchor_evidence.py
python3 tests/publish_fig518a_anchor_evidence.py --verify-only
```

Expected: all tests pass and the final command prints exactly `FIG518A_ANCHOR_VERIFY_PASS`.

- [ ] **Step 6: Commit Task 1**

```bash
git add tests/fig519_ihx_r2_hexe_contract.py \
  tests/test_fig519_ihx_r2_hexe_contract.py \
  tests/publish_fig518a_anchor_evidence.py \
  tests/test_publish_fig518a_anchor_evidence.py \
  data/provenance/steady53/fig5_18a
git commit -m "固化图5.18a的A3温度锚点证据"
```

### Task 2: Build the no-simulation MATLAB candidate generator

**Files:**
- Create: `tests/create_fig519_ihx_r2_hexe_shift_candidate.m`
- Create: `tests/test_create_fig519_ihx_r2_hexe_shift_candidate.m`
- Modify: `tests/test_fig519_ihx_r2_hexe_contract.py`

- [ ] **Step 1: Write the failing MATLAB API contract**

The test must call only a test hook or a fresh temporary candidate path and must never call `sim`:

```matlab
function tests = test_create_fig519_ihx_r2_hexe_shift_candidate
tests = functiontests(localfunctions);
end

function testCandidateUsesOneDelta(testCase)
repo = string(fileparts(fileparts(mfilename("fullpath"))));
out = string(tempname(fullfile(repo, "tmp")));
cleanup = onCleanup(@() removeOwned(out)); %#ok<NASGU>
audit = create_fig519_ihx_r2_hexe_shift_candidate(out, repo);
verifyEqual(testCase, audit.attempt_id, "20260901_A3");
verifyEqual(testCase, audit.delta_T_K, -193.6037139151003, "AbsTol", 1e-12);
verifyEqual(testCase, audit.changed_state_count, 2);
verifyEqual(testCase, audit.unchanged_state_count, 38);
verifyEqual(testCase, audit.solver_parameter_count, 37);
verifyEqual(testCase, audit.source_model_sha256, "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
verifyFalse(testCase, audit.paper_reproduced);
verifyFalse(testCase, audit.author_initial_state_identified);
verifyFalse(testCase, audit.formal_promotion);
verifyFalse(testCase, isfile(fullfile(out, "run", "raw_result.mat")));
end
```

- [ ] **Step 2: Run RED**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "r=runtests('tests/test_create_fig519_ihx_r2_hexe_shift_candidate.m'); assertSuccess(r)"
```

Expected: undefined function `create_fig519_ihx_r2_hexe_shift_candidate`.

- [ ] **Step 3: Implement the exact API patch**

The generator signature must be:

```matlab
function audit = create_fig519_ihx_r2_hexe_shift_candidate(runDir, repoRoot)
```

It must copy the frozen source model, load the copy, and apply only this central block:

```matlab
averagePath = model + "/IHX/IHX_region_2/T_c1_average_Integrator";
outletPath = model + "/IHX/IHX_region_2/T_c2_out_Integrator";
oldAverage = str2double(get_param(averagePath, "InitialCondition"));
oldOutlet = str2double(get_param(outletPath, "InitialCondition"));
anchor_K = 1200.0000000000000;
delta_T_K = anchor_K - oldOutlet;
newAverage = oldAverage + delta_T_K;
newOutlet = oldOutlet + delta_T_K;
if abs(oldAverage - 1245.8184669844006) > 1e-12 || abs(oldOutlet - 1393.6037139151003) > 1e-12 || abs(delta_T_K + 193.6037139151003) > 1e-12 || abs(newAverage - 1052.2147530693003) > 1e-12
    error("steady53:A3DecimalContract", "A3 decimal contract mismatch.");
end
set_param(averagePath, "InitialCondition", sprintf("%.17g", newAverage));
set_param(outletPath, "InitialCondition", sprintf("%.17g", newOutlet));
```

Reuse the A2 generator's state, solver, semantic topology, runtime, protected, workspace, file-generation, symlink, exclusive-write, and SHA helpers by copying their complete implementations into this focused file. Change validation from exactly one changed state to exactly these two paths, and add an explicit common-delta/gap-preservation record. After applying the two API changes, call `set_param(model, "SimulationCommand", "update")` once to satisfy the approved no-integration diagram-update preflight, then repeat the exact-change, 40-state, 37-solver, topology, runtime, protected-file, workspace, and file-generation audits before closing the model. Do not call `sim`, `SimulationCommand='start'`, or save any formal model.

- [ ] **Step 4: Add static anti-drift tests**

Extend the Python test to require exactly two literal `set_param` calls whose parameter name is `InitialCondition`, forbid XML/zip editing, forbid `sim(`, and require the identity string and both full block paths.

- [ ] **Step 5: Run GREEN**

```bash
python3 -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
python3 -O -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "r=runtests('tests/test_create_fig519_ihx_r2_hexe_shift_candidate.m'); assertSuccess(r)"
```

Expected: Python passes and MATLAB reports `1 Passed, 0 Failed, 0 Incomplete`.

- [ ] **Step 6: Commit Task 2**

```bash
git add tests/create_fig519_ihx_r2_hexe_shift_candidate.m \
  tests/test_create_fig519_ihx_r2_hexe_shift_candidate.m \
  tests/test_fig519_ihx_r2_hexe_contract.py
git commit -m "实现IHX双状态单自由度候选生成器"
```

### Task 3: Build the one-call MATLAB runner without executing it

**Files:**
- Create: `tests/run_fig519_ihx_r2_hexe_shift.m`
- Create: `tests/test_run_fig519_ihx_r2_hexe_shift.m`
- Modify: `tests/test_fig519_ihx_r2_hexe_contract.py`

- [ ] **Step 1: Write the failing source and hook tests**

Require the top-level runner body to contain exactly this one blocking call and no retry loop:

```matlab
runResult = run_steady53_case(candidatePath, 500, true);
```

The MATLAB hook test must invoke:

```matlab
hooks = run_fig519_ihx_r2_hexe_shift("__a3_test_hooks__", pwd);
hooks.testExclusiveTextCreation();
hooks.testExclusiveDirectoryCreation();
```

and verify that no model is loaded and no run directory named `fig519_ihx_r2_hexe_20260901_A3` is created.

- [ ] **Step 2: Run RED**

```bash
python3 -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "r=runtests('tests/test_run_fig519_ihx_r2_hexe_shift.m'); assertSuccess(r)"
```

Expected: missing runner/hook failures.

- [ ] **Step 3: Implement the runner**

Use this signature:

```matlab
function status = run_fig519_ihx_r2_hexe_shift(runDir, repoRoot)
```

Copy the complete A2 runner safety helpers, but validate the A3 patch schema and two-path/common-delta identity. The top-level runner must:

```matlab
writeExclusiveText(fullfile(runPath, "experiment_started.json"), jsonencode(startRecord, PrettyPrint=true));
runResult = run_steady53_case(candidatePath, 500, true);
save(fullfile(runPath, "raw_result.mat"), "runResult", "-v7.3");
writePowerAndStateCurves(fullfile(runPath, "candidate_curves.csv"), runResult);
writeReferenceCurves(fullfile(runPath, "reference_curves.csv"), repoRoot);
writeExclusiveText(fullfile(runPath, "run_status.json"), jsonencode(status, PrettyPrint=true));
```

`candidate_curves.csv` columns must be exactly:

```text
time_s,reactor_W,turbine_W,compressor_W,ihx_r2_average_K,ihx_r2_outlet_K
```

Failure status must contain real error id/report and actual artifact locators; never create fake raw or curve files.

- [ ] **Step 4: Run GREEN in no-simulation mode**

```bash
python3 -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
python3 -O -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "r=runtests('tests/test_run_fig519_ihx_r2_hexe_shift.m'); assertSuccess(r)"
```

Expected: all pass; test output must not contain `BEGIN_A3_500`.

- [ ] **Step 5: Commit Task 3**

```bash
git add tests/run_fig519_ihx_r2_hexe_shift.m \
  tests/test_run_fig519_ihx_r2_hexe_shift.m \
  tests/test_fig519_ihx_r2_hexe_contract.py
git commit -m "实现IHX A3单次运行合同"
```

### Task 4: Implement offline A3 analysis and transactional publication

**Files:**
- Create: `tests/analyze_fig519_ihx_r2_hexe_shift.py`
- Modify: `tests/test_fig519_ihx_r2_hexe_contract.py`
- Test fixtures: temporary directories created by the test only

- [ ] **Step 1: Write failing synthetic-analysis tests**

Build three synthetic fixtures with fixed CSV rows:

```python
def test_three_enums_and_false_promotions(self):
    success = synthetic_a3_run(
        directions=PAPER_DIRECTIONS,
        peak_to_peak_W={name: float(limit) * 2
                        for name, limit in NONFLAT_THRESHOLDS_W.items()},
    )
    self.assertEqual(
        analyze(success)["conclusion"],
        "ihx_r2_hexe_shift_alone_not_falsified_but_not_validated",
    )
    success["directions"]["reactor"] = []
    self.assertEqual(
        analyze(success)["conclusion"],
        "ihx_r2_hexe_shift_alone_falsified",
    )
    success["numerical_gate_passed"] = False
    self.assertEqual(
        analyze(success)["conclusion"],
        "numerical_or_physical_gate_failed",
    )
    self.assertEqual(analyze(success)["promotion"], promotion_flags())
```

Also require byte-for-byte reuse of A2's `paper_points.csv`, panel allowances, direction algorithm behavior, baseline noise, and signal identities.

- [ ] **Step 2: Run RED**

```bash
python3 -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
```

Expected: import failure for `analyze_fig519_ihx_r2_hexe_shift`.

- [ ] **Step 3: Implement validation and metrics**

Create these explicit public interfaces and lock each return/error contract in tests:

| Function | Exact inputs | Exact successful return |
|---|---|---|
| `validate_patch_audit` | `audit: object, candidate: Path` | validated `dict[str, object]` |
| `validate_run_status` | `status: object, run_dir: Path` | validated `dict[str, object]` |
| `read_candidate_curves` | `path: Path` | `dict[str, list[float]]` |
| `direction_sequence` | `points: list[tuple[float, float, float]]` | `list[str]` |
| `analyze` | `run_dir: Path` | complete `dict[str, object]` result |
| `publish` | `run_dir: Path, capture_dir: Path, durable_dir: Path, history_path: Path` | `None` after manifest-last commit |
| `verify_only` | `durable_dir: Path, history_path: Path` | `None` with zero writes |

Every validator raises a named non-`AssertionError` exception on invalid input. `publish` must consume the captured execution bytes and logs rather than consulting an uncaptured live helper.

Copy the complete finite-number, path containment, no-symlink, CSV parsing, interpolation, direction, RMSE, reference-change, lock, exclusive-write, fsync, manifest-last, transaction recovery, and verify-only implementations from the A2 analyzer into the A3-focused module. Replace the A2 candidate schema with the common-delta/two-state schema. Never use `assert` for production validation.

The analyzer must derive the fourth panel only as `electrical_paper_eta_W = 0.98 * (turbine_W - compressor_W)`. Add a synthetic test that fails for `0.96527`, a direct-generator alias, a sign reversal, or any column other than the captured `WT_sw`/`Wc_sw` identities in `signal_contract.json`.

The history payload must be:

```python
{
  "summary_schema": "steady53_fig519_initial_state_counterfactual_history_v1",
  "history_mode": "append_only_attempt_references",
  "reactor_history": {
    "path": "data/provenance/steady53/fig5_19/reactor_ic_counterfactual.json",
    "sha256": sha256(REACTOR_HISTORY.read_bytes()),
    "attempt_ids": ["20260831_A1", "20260901_A2"],
  },
  "attempts": [{"attempt_id": "20260901_A3", "summary": a3_summary}],
  "paper_reproduced": False,
  "author_initial_state_identified": False,
  "formal_promotion": False,
}
```

- [ ] **Step 4: Add publication crash/tamper tests**

Test failure after each staged write and before manifest commit. Verify recovery is idempotent, old A1/A2 bytes never change, raw/CSV hashes are bound, symlinks and coordinated JSON/manifest tampering are rejected, and `--verify-only` preserves mtimes.

- [ ] **Step 5: Run GREEN**

```bash
python3 -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
python3 -O -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
```

Expected: all A3 pure/offline tests pass.

- [ ] **Step 6: Commit Task 4**

```bash
git add tests/analyze_fig519_ihx_r2_hexe_shift.py \
  tests/test_fig519_ihx_r2_hexe_contract.py
git commit -m "实现IHX A3离线判据与证据事务"
```

### Task 4A: Close the portable dependency graph before capture

**Files:**
- Implement and verify every file named by
  `docs/superpowers/plans/2026-09-01-a3-capture-dependency-closure.md`
- Do not create the Task 5 runtime capture in this task

- [ ] **Step 1: Execute the approved closure plan Tasks 1–5 in order**

Use the supplemental plan as the executable specification. It must publish the
34-row repository-local protected archive, freeze the exact eight-record formal
root state, migrate candidate/runner/analyzer consumers, and prove a real
captured-root zero-simulation preflight.

- [ ] **Step 2: Enforce the two-stage closure review gate**

Obtain an independent specification review followed by an independent
code-quality review of the completed closure. Any Critical or Important finding
blocks Task 5. The reviewers must inspect actual captured-root behavior and
confirm that no consumer reads a protected object from a live or external
absolute path.

- [ ] **Step 3: Confirm the formal boundary before Task 5**

Require all of the following before proceeding:

```text
protected logical records = 34
formal records = 8
formal present records = 7
root final_dynamic_24a.slx = absent
run_steady53_case call count = 0
formal command invocation count = 0
```

Task 5 may start only after the supplemental plan is complete and both reviews
report Ready.

### Task 5: Build the self-contained capture and reach READY without simulation

**Files:**
- Create: `tests/prepare_fig519_ihx_r2_hexe_a3.py`
- Create: `tests/execute_fig519_ihx_r2_hexe_a3_once.py`
- Create: `tests/test_prepare_fig519_ihx_r2_hexe_a3.py`
- Runtime only: `tmp/fig519_ihx_r2_hexe_20260901_A3_capture/**`

- [ ] **Step 1: Write failing capture-completeness tests**

Require a snapshot rooted at:

```text
tmp/fig519_ihx_r2_hexe_20260901_A3_capture/repo_snapshot/
```

and require these exact executable/data groups:

```python
EXECUTABLES = (
    "tests/prepare_fig519_ihx_r2_hexe_a3.py",
    "tests/create_fig519_ihx_r2_hexe_shift_candidate.m",
    "tests/run_fig519_ihx_r2_hexe_shift.m",
    "tests/steady53/run_steady53_case.m",
    "tests/steady53/steady53_signal_manifest.m",
    "tests/steady53/reset_steady53_property_warning_state.m",
    "tests/analyze_fig519_ihx_r2_hexe_shift.py",
    "tests/fig519_ihx_r2_hexe_contract.py",
    "tests/execute_fig519_ihx_r2_hexe_a3_once.py",
)
DATA_GROUPS = (
    "data/provenance/baselines/f8bcd83/final_steady_24a.slx",
    "data/provenance/baselines/f8bcd83/runtime",
    "data/provenance/steady53/fig5_18a",
    "data/provenance/steady53/fig5_19/paper_points.csv",
    "data/provenance/steady53/fig5_19/model_baseline",
    "data/provenance/steady53/fig5_19/signal_contract.json",
    "data/provenance/steady53/fig5_19/initialization_audit.json",
    "data/provenance/steady53/fig5_19/reactor_ic_counterfactual.json",
    "data/provenance/steady53/fig5_19/manifest.csv",
)
CLOSURE_GOVERNANCE = (
    "data/provenance/baselines/f8bcd83/protected_manifest_recovery.csv",
    "data/provenance/baselines/f8bcd83/portable_protected_manifest.json",
    "data/provenance/baselines/f8bcd83/formal_root_state.json",
    "data/provenance/baselines/f8bcd83/protected_objects",
)
FORMAL_ROOT_PRESENT = (
    "final_steady_24a.slx",
    "HeXe_property_simulink.m",
    "Lithium_property_simulink.m",
    "hexe_compressor_lookup.mat",
    "radiator_table.mat",
    "turbine_table1.mat",
    "turbine_table2.mat",
)
FORMAL_ROOT_ABSENT = ("final_dynamic_24a.slx",)
```

The exact immutable input set is the deduplicated union of `EXECUTABLES`, every
ordinary file recursively contained by `DATA_GROUPS` and `CLOSURE_GOVERNANCE`,
and every file in `FORMAL_ROOT_PRESENT`. `SHA256SUMS` must list every immutable
file exactly once in sorted POSIX-path order. `FORMAL_ROOT_ABSENT` is an absence
contract, not a copied input. The snapshot `tmp/` tree is excluded from the
immutable input set.

The tests must reject missing/extra executables, missing/extra protected archive
rows or files, duplicate manifest paths, symlinks, writable immutable snapshot
files, hash mismatch, a present captured-root `final_dynamic_24a.slx`, a changed
formal-root hash, any protected path resolved outside the captured repository,
an internal blank line or duplicate path in `SHA256SUMS`, live-repo MATLAB paths
in `command.txt`, an existing formal run directory, and any command containing a
retry loop. The one declared exception is the empty `repo_snapshot/tmp/` output
directory: it must be mode `0700`, excluded from the immutable-input file
manifest, and rejected if it contains a pre-existing formal A3 run directory.

- [ ] **Step 2: Run RED**

```bash
python3 -m unittest -v tests.test_prepare_fig519_ihx_r2_hexe_a3
```

Expected: missing prepare/execute modules.

- [ ] **Step 3: Implement snapshot preparation**

`prepare_fig519_ihx_r2_hexe_a3.py` must:

1. verify Task 1–4 tests and frozen identities;
2. create the capture directory exclusively with mode `0700`;
3. copy the exact repository tree subset above as regular files, preserving
   bytes, including both closure governance manifests, all 34 logical protected
   archive objects, and the seven present formal-root files; never copy or
   recreate root `final_dynamic_24a.slx`;
4. write `tracked_diff.patch`, `git_head.txt`, `git_status_porcelain_v1_z.bin`, `untracked_paths.json`, `SHA256SUMS`, and `preflight_status.json`;
5. record the resolved Python and MATLAB executable paths, versions, and SHA-256 identities as system-runtime provenance;
6. make immutable snapshot files mode `0400` and immutable directories `0500`, while keeping only the empty `repo_snapshot/tmp/` output directory mode `0700`;
7. before MATLAB, verify the fixed source-manifest and portable-manifest hashes,
   exact protected34/formal8/formal-present7 sets, formal exact hashes, captured
   root dynamic absence, and that no executable protected path leaves the
   captured repository;
8. invoke the captured candidate generator through MATLAB once in
   `repo_snapshot/tmp/fig519_ihx_r2_hexe_20260901_A3_preflight`, without calling
   the runner, and bind its protected34/formal8/formal-present7/runtime9,
   40-state/37-solver/common-delta/update-diagram audit into
   `preflight_status.json`;
9. reverify all immutable-input hashes after the preflight and verify the 34/34
   protected manifest plus unchanged A1/A2 canonical summary bytes;
10. implement `--archive-consumed-execution` as a model-read-only verifier of already-existing execution artifacts; it writes exactly one new outer-capture file, `consumed_execution_manifest.json`, by exclusive create after hashing the claim, command, logs, exit code, execution record, candidate audit, status, and every raw/CSV artifact that actually exists; it must reject an absent invocation claim and must never launch a subprocess;
11. write `command.txt` that calls only the captured executor;
12. keep `repo_snapshot/tmp/fig519_ihx_r2_hexe_20260901_A3` absent.

The exact command text must be:

```text
python3 tmp/fig519_ihx_r2_hexe_20260901_A3_capture/repo_snapshot/tests/execute_fig519_ihx_r2_hexe_a3_once.py --execute
```

Immediately after argument parsing, the captured executor must atomically create `formal_invocation.claim` before self-hash or any other fallible validation. It must then self-hash against `SHA256SUMS`, verify every immutable snapshot file, reject any undeclared file outside the writable output directory, and run at most one MATLAB subprocess with captured paths. A hash, path, or subprocess-start failure after the claim is still a consumed A3 attempt and must exclusively write the truthful `stdout.log`, `stderr.log`, `formal_exit_code.txt`, UTC/monotonic timestamps, and `execution_record.json`; it must never remove the claim. Its MATLAB batch expression must be exactly:

```matlab
repoRoot=string(pwd); addpath(fullfile(repoRoot,'tests'),fullfile(repoRoot,'tests','steady53')); runDir=fullfile(repoRoot,'tmp','fig519_ihx_r2_hexe_20260901_A3'); create_fig519_ihx_r2_hexe_shift_candidate(runDir,repoRoot); run_fig519_ihx_r2_hexe_shift(runDir,repoRoot)
```

The subprocess `cwd` must be the captured `repo_snapshot`, not the live repository.

- [ ] **Step 4: Test exact-once without MATLAB simulation**

Inject a temporary fake executable into the executor unit test. The fake process writes a synthetic valid run status and increments a file counter. Verify the first call records count 1 and the second call fails before subprocess launch because `formal_invocation.claim` exists. Add a tampered-snapshot case that creates the claim, records subprocess count 0 and a truthful validation failure, and still rejects a second invocation. This unit test must never call MATLAB.

- [ ] **Step 5: Run all zero-simulation gates**

```bash
python3 -m unittest -v \
  tests.test_publish_a3_capture_dependency_closure \
  tests.test_fig519_ihx_r2_hexe_contract \
  tests.test_publish_fig518a_anchor_evidence \
  tests.test_prepare_fig519_ihx_r2_hexe_a3
python3 -O -m unittest -v \
  tests.test_publish_a3_capture_dependency_closure \
  tests.test_fig519_ihx_r2_hexe_contract \
  tests.test_publish_fig518a_anchor_evidence \
  tests.test_prepare_fig519_ihx_r2_hexe_a3
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "r=runtests({'tests/test_create_fig519_ihx_r2_hexe_shift_candidate.m','tests/test_run_fig519_ihx_r2_hexe_shift.m'}); assertSuccess(r)"
```

Expected: all Python and MATLAB no-simulation tests pass and output contains no `BEGIN_A3_500` marker.

- [ ] **Step 6: Commit Task 5 code before creating the runtime capture**

```bash
git add tests/prepare_fig519_ihx_r2_hexe_a3.py \
  tests/execute_fig519_ihx_r2_hexe_a3_once.py \
  tests/test_prepare_fig519_ihx_r2_hexe_a3.py
git commit -m "准备IHX A3单次运行快照"
```

- [ ] **Step 7: Create and verify the runtime capture from the committed bytes**

```bash
python3 tests/prepare_fig519_ihx_r2_hexe_a3.py --prepare
python3 tests/prepare_fig519_ihx_r2_hexe_a3.py --verify-only
```

Expected final line: `FIG519_IHX_R2_HEXE_A3_PREFLIGHT=READY_NO_SIMULATION`. The preflight candidate audit must exist, the formal A3 run directory must still be absent, `run_steady53_case_call_count=0`, and `formal_command_invocation_count=0`.

- [ ] **Step 8: Stop and report READY**

Report snapshot hashes, zero simulation count, protected/source identities, exact command, and the fact that A3 is still unconsumed. Request the separate human authorization phrase **“批准 A3 单次正式运行”**. Do not proceed automatically.

### Task 6: Execute the one authorized A3 formal command

**Files:**
- Read only: `tmp/fig519_ihx_r2_hexe_20260901_A3_capture/command.txt`
- Runtime output: `tmp/fig519_ihx_r2_hexe_20260901_A3_capture/repo_snapshot/tmp/fig519_ihx_r2_hexe_20260901_A3/**`
- Runtime evidence: `tmp/fig519_ihx_r2_hexe_20260901_A3_capture/{stdout.log,stderr.log,formal_exit_code.txt,execution_record.json,formal_invocation.claim}`

- [ ] **Step 1: Verify the human gate**

Proceed only if the user has explicitly authorized **“批准 A3 单次正式运行”** after Task 5 READY. Otherwise stop.

- [ ] **Step 2: Re-run verify-only without writes**

```bash
python3 tmp/fig519_ihx_r2_hexe_20260901_A3_capture/repo_snapshot/tests/prepare_fig519_ihx_r2_hexe_a3.py \
  --verify-only \
  --capture-dir tmp/fig519_ihx_r2_hexe_20260901_A3_capture
test ! -e tmp/fig519_ihx_r2_hexe_20260901_A3_capture/repo_snapshot/tmp/fig519_ihx_r2_hexe_20260901_A3
```

Expected: READY/absent; no invocation claim yet.

- [ ] **Step 3: Execute command.txt exactly once**

Read the one line from `command.txt`; compare its SHA to `preflight_status.json`; execute that exact line once. Do not reconstruct it manually and do not wrap it in a retrying command.

Expected successful case: formal exit `0`, `run_steady53_case_call_count=1`, `retry_count=0`, `candidate_final_time_s=500`. Any other outcome is preserved as the consumed A3 result.

- [ ] **Step 4: Stop all model execution**

After the process exits, do not invoke MATLAB, the captured executor, candidate generator, or runner again. Compute hashes and inspect status using Python/read-only shell commands only.

### Task 7: Analyze and publish the consumed result offline

**Files:**
- Modify/create through publisher: `data/provenance/steady53/fig5_19/ihx_r2_hexe_shift_A3/**`
- Create: `data/provenance/steady53/fig5_19/initial_state_counterfactual_history.json`
- Modify: `data/provenance/steady53/fig5_19/manifest.csv`
- Modify: `data/provenance/steady53/fig5_19/README.md`
- Modify: `docs/steady53_fig519_progress_20260831.md`
- Modify: `tests/test_fig519_end_to_end_contract.py`

- [ ] **Step 1: Archive execution without running it**

```bash
python3 tmp/fig519_ihx_r2_hexe_20260901_A3_capture/repo_snapshot/tests/prepare_fig519_ihx_r2_hexe_a3.py \
  --archive-consumed-execution \
  --capture-dir tmp/fig519_ihx_r2_hexe_20260901_A3_capture
python3 tmp/fig519_ihx_r2_hexe_20260901_A3_capture/repo_snapshot/tests/prepare_fig519_ihx_r2_hexe_a3.py \
  --verify-only \
  --capture-dir tmp/fig519_ihx_r2_hexe_20260901_A3_capture
```

Expected: `FIG519_IHX_R2_HEXE_A3_EXECUTION=VERIFIED_NO_RERUN`.

- [ ] **Step 2: Run offline analysis and publication**

```bash
python3 tmp/fig519_ihx_r2_hexe_20260901_A3_capture/repo_snapshot/tests/analyze_fig519_ihx_r2_hexe_shift.py \
  --run-dir tmp/fig519_ihx_r2_hexe_20260901_A3_capture/repo_snapshot/tmp/fig519_ihx_r2_hexe_20260901_A3 \
  --capture-dir tmp/fig519_ihx_r2_hexe_20260901_A3_capture \
  --durable-dir data/provenance/steady53/fig5_19/ihx_r2_hexe_shift_A3 \
  --history-path data/provenance/steady53/fig5_19/initial_state_counterfactual_history.json
python3 tmp/fig519_ihx_r2_hexe_20260901_A3_capture/repo_snapshot/tests/analyze_fig519_ihx_r2_hexe_shift.py \
  --verify-only \
  --durable-dir data/provenance/steady53/fig5_19/ihx_r2_hexe_shift_A3 \
  --history-path data/provenance/steady53/fig5_19/initial_state_counterfactual_history.json
```

Expected: exactly one of the three approved enums. Missing raw/curves after a pre-simulation failure must remain missing and be described truthfully.

- [ ] **Step 3: Extend the end-to-end contract before docs**

Add a failing test that requires the exact A3 enum, durable raw/status/log hashes when present, the cross-family history reference to immutable A1/A2, and all six reproduction/promotion flags false. It must reject claims of author t0, a second anchor, parameter scanning, 14000 s extension, or formal model modification.

- [ ] **Step 4: Update README and phase report from machine evidence**

Record the actual enum and metrics with ✅/❓/❌ grades from `决策自律准则.md`. State that this result is bounded to one scalar/two dependent states. Do not write “improved” unless a predeclared reported metric actually improved, and never translate improvement into validation.

- [ ] **Step 5: Run publication and regression tests**

```bash
python3 -m unittest -v \
  tests.test_fig519_ihx_r2_hexe_contract \
  tests.test_publish_fig518a_anchor_evidence \
  tests.test_prepare_fig519_ihx_r2_hexe_a3 \
  tests.test_fig519_end_to_end_contract
python3 -O -m unittest -v \
  tests.test_fig519_ihx_r2_hexe_contract \
  tests.test_publish_fig518a_anchor_evidence \
  tests.test_prepare_fig519_ihx_r2_hexe_a3 \
  tests.test_fig519_end_to_end_contract
```

Expected: all pass without model execution.

- [ ] **Step 6: Commit Task 7**

Stage only code, docs, and durable evidence explicitly named by `git status`; do not stage unrelated untracked historical diagnostics.

```bash
git add tests/analyze_fig519_ihx_r2_hexe_shift.py \
  tests/test_fig519_ihx_r2_hexe_contract.py \
  tests/test_fig519_end_to_end_contract.py \
  data/provenance/steady53/fig5_19/ihx_r2_hexe_shift_A3 \
  data/provenance/steady53/fig5_19/initial_state_counterfactual_history.json \
  data/provenance/steady53/fig5_19/manifest.csv \
  data/provenance/steady53/fig5_19/README.md \
  docs/steady53_fig519_progress_20260831.md
git commit -m "记录IHX热状态A3单次反事实结果"
```

### Task 8: Run the complete gate and stop at the next scientific decision

**Files:**
- Verify only; no new scientific files unless a test exposes a truthful documentation error

- [ ] **Step 1: Run the full Python suite in normal mode**

Before running, mechanically verify that the first eight pre-A3 modules still discover exactly the previously reported 101 tests:

```bash
python3 - <<'PY'
import unittest
modules = (
    "tests.test_publish_f8bcd83_runtime",
    "tests.test_publish_fig518d_evidence",
    "tests.test_fig518d_durable_paths",
    "tests.test_radiator_a1_contract",
    "tests.test_digitize_fig519",
    "tests.test_analyze_fig519_baseline",
    "tests.test_fig519_counterfactual",
    "tests.test_prepare_fig519_reactor_ic_a2",
)
count = sum(unittest.defaultTestLoader.loadTestsFromName(name).countTestCases()
            for name in modules)
if count != 101:
    raise SystemExit(f"legacy regression count drifted: {count}")
print("LEGACY_FIG519_PYTHON_TEST_COUNT=101")
PY
```

Then run those 101 legacy tests together with the prior end-to-end contract and every new A3 test:

```bash
python3 -m unittest -v \
  tests.test_publish_f8bcd83_runtime \
  tests.test_publish_fig518d_evidence \
  tests.test_fig518d_durable_paths \
  tests.test_radiator_a1_contract \
  tests.test_digitize_fig519 \
  tests.test_analyze_fig519_baseline \
  tests.test_fig519_counterfactual \
  tests.test_prepare_fig519_reactor_ic_a2 \
  tests.test_publish_a3_capture_dependency_closure \
  tests.test_fig519_ihx_r2_hexe_contract \
  tests.test_publish_fig518a_anchor_evidence \
  tests.test_prepare_fig519_ihx_r2_hexe_a3 \
  tests.test_fig519_end_to_end_contract
```

Expected: the first command prints `LEGACY_FIG519_PYTHON_TEST_COUNT=101`; all legacy, prior end-to-end, and A3 tests pass.

- [ ] **Step 2: Run the same suite under `python -O`**

Replace `python3` with `python3 -O` in the Step 1 command.

Expected: identical pass count; no validation disappears under optimization.

- [ ] **Step 3: Run all verify-only gates**

```bash
python3 tests/publish_f8bcd83_runtime.py --verify-only
python3 tests/publish_a3_capture_dependency_closure.py --verify-only
python3 tests/publish_fig518d_evidence.py --verify-only
python3 tests/publish_fig518a_anchor_evidence.py --verify-only
python3 tests/digitize_fig519.py --verify-only
python3 tests/analyze_fig519_baseline.py --verify-only
python3 tests/prepare_fig519_reactor_ic_a2.py --verify-only
python3 tests/analyze_fig519_counterfactual.py --verify-only \
  tmp/fig519_reactor_ic_20260901_A2
python3 tmp/fig519_ihx_r2_hexe_20260901_A3_capture/repo_snapshot/tests/prepare_fig519_ihx_r2_hexe_a3.py \
  --verify-only \
  --capture-dir tmp/fig519_ihx_r2_hexe_20260901_A3_capture
python3 tmp/fig519_ihx_r2_hexe_20260901_A3_capture/repo_snapshot/tests/analyze_fig519_ihx_r2_hexe_shift.py \
  --verify-only \
  --durable-dir data/provenance/steady53/fig5_19/ihx_r2_hexe_shift_A3 \
  --history-path data/provenance/steady53/fig5_19/initial_state_counterfactual_history.json
```

Expected: each fixed success marker is printed; no mtimes change.

- [ ] **Step 4: Run MATLAB no-simulation tests**

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "r=runtests({'tests/test_prepare_radiator_a1_candidates.m','tests/test_audit_fig519_initialization.m','tests/test_create_fig519_ihx_r2_hexe_shift_candidate.m','tests/test_run_fig519_ihx_r2_hexe_shift.m'}); assertSuccess(r)"
```

Expected: `4 Passed, 0 Failed, 0 Incomplete`; no A3 model run marker.

- [ ] **Step 5: Verify protected and formal files**

```bash
python3 tests/publish_a3_capture_dependency_closure.py --verify-only
test ! -e final_dynamic_24a.slx
git diff --check
git diff --name-only b248299..HEAD -- \
  final_steady_24a.slx final_dynamic_24a.slx '*.mat' \
  HeXe_property_simulink.m Lithium_property_simulink.m
```

Expected: protected 34/34 and formal 8/7 verification passes, root dynamic is
absent, no whitespace errors exist, and the formal-file diff is empty.

- [ ] **Step 6: Perform two-stage review**

Run a specification review and then a code/evidence review. If the user selected Subagent-Driven execution, use separate reviewer agents; if the user selected Inline Execution, perform two explicitly separated review passes locally. Both passes must confirm: one scalar/two dependent states, exact one consumed formal invocation, no retry, complete contemporaneous snapshot, mechanical enum, truthful failure artifacts, durable raw evidence, immutable A1/A2, false promotion flags, and formal-file zero diff.

- [ ] **Step 7: Stop and report the actual scientific branch**

Do not choose another state family or run 14000 s automatically. Report the actual enum, all four direction/nonflat results, RMSE/peak/valley metrics, evidence limitations, commits, and the next human decision required by the approved design.
