# A3 Capture Dependency Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace machine-specific protected paths with a repository-local immutable 34-record archive, freeze the exact formal-root existence state, migrate A3 Task 2–4 consumers to the portable contract, and prove the revised Task 5 snapshot is self-contained before any formal run.

**Architecture:** A deterministic Python publisher materializes governance-only archive bytes and two fixed manifests. Candidate, runner, and analyzer resolve protected/formal inputs exclusively from repository-relative records under their supplied `repoRoot`. A real captured-root no-simulation preflight closes the cross-language dependency graph before the existing Task 5 one-shot capture workflow resumes.

**Tech Stack:** Python 3 (`csv`, `json`, `hashlib`, `pathlib`, `unittest`), MATLAB/Simulink R2025a official APIs, Git, SHA-256, JSON, existing A3 zero-simulation hooks.

---

## Fixed constants and authority

- Approved design: `docs/superpowers/specs/2026-09-01-a3-capture-dependency-closure-design.md` at commit `fd83c06`.
- Original recovery manifest SHA-256:
  `33f7a4b4bbda5e47932ec9345e490a42b68d5a8636bf541891840c76fde6ed64`.
- Deterministic portable manifest SHA-256:
  `22f7d010caf32b0b30150f668fc53a642cf1432f877c6a9e4c8eac0531f41ee3`.
- Deterministic formal-root state SHA-256:
  `38ede7e582be9f7fd90142948de005de5b518b042d92db616311f4930bdc352d`.
- Formal-root observation commit:
  `aaeee0ceb9220e65686fdbbef6ab9b702c7135ff`.
- Protected logical record count: 34; archive paths are exactly
  `data/provenance/baselines/f8bcd83/protected_objects/row_001` through
  `row_034`, one ordinary file per row directory.
- Formal state has exactly eight records, seven present files, and an absent root
  `final_dynamic_24a.slx`.
- The exact formal records are:

| Repository-relative path | Exists | SHA-256 |
|---|---:|---|
| `final_steady_24a.slx` | true | `a93cd94b6c5a0c941fe9eed40d8aea779019cbdb26fe2558df65f7c81c9dc159` |
| `final_dynamic_24a.slx` | false | empty string |
| `HeXe_property_simulink.m` | true | `2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2` |
| `Lithium_property_simulink.m` | true | `f0c2aad44e8701212e924371fe027d7b3814a32cd5df3a32f8a0ccf09abb7f1c` |
| `hexe_compressor_lookup.mat` | true | `f9c85bc1ae831333fac5f868f15a6f82ea1c1716ee17f23dfb301f4618c9f579` |
| `radiator_table.mat` | true | `3f6e8a08f6ec9253b84d07f8eff11d2b093f785bafcfde515f2c6af4ec263304` |
| `turbine_table1.mat` | true | `10e72638374c530e2032d9bfe39b060d4181b0467bf69e03196efa0b90c4971d` |
| `turbine_table2.mat` | true | `cda85dc4480a7723a0ef52bda0fb6f2795e14dfe1167ac74b38a8d64d5b58c33` |

- This plan must not modify a formal SLX, root MAT, property function, A3 candidate value, paper gate, or formal authorization state.
- Every MATLAB command in Tasks 1–5 is zero-simulation. The only permitted model action remains one diagram `update` in a temporary preflight candidate.

## File-responsibility map

| File | Single responsibility |
|---|---|
| `tests/publish_a3_capture_dependency_closure.py` | Deterministically publish and verify the 34-row portable archive and formal-root state |
| `tests/test_publish_a3_capture_dependency_closure.py` | Derivation, hash, collision, tamper, symlink, idempotence, and no-external-read verification tests |
| `data/provenance/baselines/f8bcd83/portable_protected_manifest.json` | Portable logical-row-to-repository-object mapping |
| `data/provenance/baselines/f8bcd83/formal_root_state.json` | Exact eight-record root existence/hash state |
| `data/provenance/baselines/f8bcd83/protected_objects/**` | Immutable bytes for all 34 logical protected rows, including duplicates |
| `tests/create_fig519_ihx_r2_hexe_shift_candidate.m` | Consume portable protected/formal manifests while creating the zero-simulation candidate |
| `tests/run_fig519_ihx_r2_hexe_shift.m` | Bind portable protected/formal manifests at the exact-once call gate |
| `tests/analyze_fig519_ihx_r2_hexe_shift.py` | Validate and durably archive the revised full immutable snapshot |
| existing Task 2–4 test files | Lock capture-local resolution and zero-simulation behavior |
| `docs/superpowers/plans/2026-09-01-ihx-r2-hexe-shift-a3.md` | Parent A3 plan with revised Task 5 exact closure |

### Task 1: Publish the portable governance archive

**Files:**
- Create: `tests/publish_a3_capture_dependency_closure.py`
- Create: `tests/test_publish_a3_capture_dependency_closure.py`
- Create: `data/provenance/baselines/f8bcd83/portable_protected_manifest.json`
- Create: `data/provenance/baselines/f8bcd83/formal_root_state.json`
- Create: `data/provenance/baselines/f8bcd83/protected_objects/row_001/**` through `row_034/**`

- [ ] **Step 1: Write failing derivation and formal-state tests**

Add tests that call only pure Python public interfaces:

```python
import unittest

from tests.publish_a3_capture_dependency_closure import (
    build_formal_root_state,
    build_portable_manifest,
    publish,
    verify_only,
)

class DependencyClosureTests(unittest.TestCase):
    def test_portable_manifest_preserves_all_logical_rows(self):
        payload = build_portable_manifest(REPO_ROOT)
        self.assertEqual(payload["schema"], "steady53_protected_portable_manifest_v1")
        self.assertEqual(payload["source_manifest_sha256"], SOURCE_MANIFEST_SHA256)
        self.assertEqual(
            [r["record_index"] for r in payload["records"]], list(range(1, 35))
        )
        self.assertEqual(
            len({r["archive_repository_relative_path"] for r in payload["records"]}),
            34,
        )

    def test_formal_state_preserves_absent_dynamic_root(self):
        payload = build_formal_root_state(REPO_ROOT)
        by_path = {r["repository_relative_path"]: r for r in payload["records"]}
        self.assertEqual(len(by_path), 8)
        self.assertEqual(
            by_path["final_dynamic_24a.slx"],
            {
                "repository_relative_path": "final_dynamic_24a.slx",
                "exists": False,
                "sha256": "",
            },
        )
        self.assertEqual(sum(bool(r["exists"]) for r in payload["records"]), 7)
```

Also add a test method that requires exact deterministic JSON bytes:

```python
def test_canonical_manifest_hashes_are_fixed(self):
    self.assertEqual(
        sha256(canonical_json(build_portable_manifest(REPO_ROOT))),
        "22f7d010caf32b0b30150f668fc53a642cf1432f877c6a9e4c8eac0531f41ee3",
    )
    self.assertEqual(
        sha256(canonical_json(build_formal_root_state(REPO_ROOT))),
        "38ede7e582be9f7fd90142948de005de5b518b042d92db616311f4930bdc352d",
    )
```

- [ ] **Step 2: Run RED**

```bash
python3 -m unittest -v tests.test_publish_a3_capture_dependency_closure
python3 -O -m unittest -v tests.test_publish_a3_capture_dependency_closure
```

Expected: import failure because the publisher does not exist.

- [ ] **Step 3: Implement deterministic builders and strict verification**

Implement these public interfaces:

```python
def build_portable_manifest(repo_root: Path) -> dict[str, object]: ...
def build_formal_root_state(repo_root: Path) -> dict[str, object]: ...
def publish(repo_root: Path) -> None: ...
def verify_only(repo_root: Path) -> None: ...
```

The canonical serializer is exactly:

```python
def canonical_json(payload: object) -> bytes:
    return (json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")
```

`build_portable_manifest` must read the original 34-row CSV once, verify its fixed SHA, verify every `resolved_path` byte hash, and assign
`protected_objects/row_{record_index:03d}/{Path(resolved_path).name}`. The two source absolute path fields are copied as provenance strings but never reused for reads by `verify_only`.

`publish` must use private staging plus no-replace hard-link publication. It must publish all 34 files and both manifests, fsync files/directories, reject an existing non-identical target, and be idempotent for byte-identical targets.

`verify_only` must read only the original CSV, the two portable governance files, the 34 repository-local archive files, and the seven current formal root files. It must not stat or open any CSV `resolved_path` outside `repo_root`.

- [ ] **Step 4: Add destructive-boundary and provenance tests**

Test all of the following with temporary output roots or injected filesystem hooks:

- source manifest row count, column names, fixed SHA, and resolved byte hash;
- 34 unique archive relative paths even when source hashes or basenames repeat;
- missing row, duplicate row index/path, extra row, wrong hash, symlink file/ancestor, and path escape;
- publication collision with existing regular file, symlink, or directory;
- verification after renaming the external `_副本` directory out of view, proving no external read is needed after publication;
- exact formal eight-set, seven present hashes, and absent root dynamic model;
- failure if `final_dynamic_24a.slx` appears at the formal root;
- `verify_only` performs zero writes and preserves mtimes.

- [ ] **Step 5: Run GREEN and publish governance bytes**

```bash
python3 -m unittest -v tests.test_publish_a3_capture_dependency_closure
python3 -O -m unittest -v tests.test_publish_a3_capture_dependency_closure
python3 tests/publish_a3_capture_dependency_closure.py --publish
python3 tests/publish_a3_capture_dependency_closure.py --verify-only
```

Expected: all tests pass; the two manifest hashes equal the fixed constants; 34 archive files exist; root `final_dynamic_24a.slx` remains absent.

- [ ] **Step 6: Commit Task 1**

Stage only the publisher, its test, the two manifests, and `protected_objects/**`:

```bash
git add tests/publish_a3_capture_dependency_closure.py \
  tests/test_publish_a3_capture_dependency_closure.py \
  data/provenance/baselines/f8bcd83/portable_protected_manifest.json \
  data/provenance/baselines/f8bcd83/formal_root_state.json \
  data/provenance/baselines/f8bcd83/protected_objects
git commit -m "归档A3可移植保护依赖"
```

### Task 2: Migrate the zero-simulation candidate generator

**Files:**
- Modify: `tests/create_fig519_ihx_r2_hexe_shift_candidate.m`
- Modify: `tests/test_create_fig519_ihx_r2_hexe_shift_candidate.m`
- Modify: `tests/test_fig519_ihx_r2_hexe_contract.py`

- [ ] **Step 1: Write failing portable-resolution tests**

Add MATLAB behavior hooks that build a temporary captured `repoRoot` containing the portable manifests, 34 archived objects, runtime9, source baseline, and the seven present formal root files. Require:

```matlab
hooks = create_fig519_ihx_r2_hexe_shift_candidate("__a3_test_hooks__", pwd);
result = hooks.testPortableCapturedDependencyClosure();
verifyEqual(testCase, result.protected_count, 34);
verifyEqual(testCase, result.formal_record_count, 8);
verifyEqual(testCase, result.formal_existing_count, 7);
verifyEqual(testCase, result.runtime_count, 9);
verifyEqual(testCase, result.state_count, 40);
verifyEqual(testCase, result.solver_count, 37);
verifyEqual(testCase, result.simulation_call_count, 0);
```

Add negative cases for a missing archive row, portable-manifest hash mismatch, archive symlink, unexpected captured-root `final_dynamic_24a.slx`, and a missing present formal file.

The Python static contract must reject executable use of `source_original_path`, `source_resolved_path`, or CSV `resolved_path` in candidate/runner/analyzer source.

- [ ] **Step 2: Run RED**

```bash
python3 -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "r=runtests('tests/test_create_fig519_ihx_r2_hexe_shift_candidate.m'); assertSuccess(r)"
```

Expected: missing hook and old absolute-path protected resolution failures. Output must not contain a simulation marker.

- [ ] **Step 3: Implement portable protected and formal readers**

Replace `protectedIdentities(manifestPath, repoRoot)` with a reader of
`portable_protected_manifest.json`. It must verify both fixed manifest hashes, exact schema/count/index/path uniqueness, and read each object only from `repoRoot + archive_repository_relative_path` with no-follow identity/SHA checks.

Replace dynamic `formalIdentities` discovery with `formal_root_state.json`. Always emit exact eight records in manifest order. For `exists=false`, require the captured root path to be absent and emit empty fileKey/hash. For `exists=true`, require the fixed SHA and no-follow identity.

Persist both governance manifest hashes and capture-local repository-relative paths in `patch_audit.json`. Preserve the existing two-IC/common-delta, 40-state, 37-solver, mask/topology/workspace, FileGen, publication, and final-inventory gates.

- [ ] **Step 4: Run the complete zero-simulation regression**

```bash
python3 -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
python3 -O -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "r=runtests('tests/test_create_fig519_ihx_r2_hexe_shift_candidate.m'); assertSuccess(r)"
```

Expected: all pass; exactly two IC writes, one diagram update, zero runner/simulation/start, formal root files unchanged.

- [ ] **Step 5: Commit Task 2 and obtain two-stage review**

```bash
git add tests/create_fig519_ihx_r2_hexe_shift_candidate.m \
  tests/test_create_fig519_ihx_r2_hexe_shift_candidate.m \
  tests/test_fig519_ihx_r2_hexe_contract.py
git commit -m "迁移A3候选到可移植依赖"
```

Require independent spec review followed by code-quality review. Any Critical or Important finding blocks Task 3.

### Task 3: Migrate the exact-once runner call gate

**Files:**
- Modify: `tests/run_fig519_ihx_r2_hexe_shift.m`
- Modify: `tests/test_run_fig519_ihx_r2_hexe_shift.m`
- Modify: `tests/test_fig519_ihx_r2_hexe_contract.py`

- [ ] **Step 1: Write failing captured call-gate tests**

Extend the runner hooks to consume a candidate audit built under a captured root. Require exact protected34/formal8/runtime9 sets from the two portable manifests, all protected absolute paths inside captured `repoRoot`, and no use of the live repository or `_副本`.

Add stable finite-replacement tests for portable manifest, formal state, one archived protected object, one present formal file, candidate, audit, and each of the three captured MATLAB helpers. Every case must fail before the synthetic call gate and report `simulation_call_count=0`.

- [ ] **Step 2: Run RED**

```bash
python3 -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "r=runtests('tests/test_run_fig519_ihx_r2_hexe_shift.m'); assertSuccess(r)"
```

Expected: old live-manifest validation fails; no `BEGIN_A3_500` marker.

- [ ] **Step 3: Implement the portable call gate**

Load protected/formal expectations only from the captured portable manifests. Bind both governance files and every resolved object into `invocationBinding`. Revalidate schema, fixed manifest hashes, exact sets, canonical capture-local paths, fileKey/dev/inode, and SHA immediately before and after the one existing direct call.

Keep the direct call exactly once and unchanged:

```matlab
runResult = run_steady53_case(candidatePath, 500, true);
```

Do not add a retry, dynamic dispatch, controller, simulation hook, or second call path.

- [ ] **Step 4: Run GREEN and commit**

```bash
python3 -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
python3 -O -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "r=runtests({'tests/test_create_fig519_ihx_r2_hexe_shift_candidate.m','tests/test_run_fig519_ihx_r2_hexe_shift.m'}); assertSuccess(r)"
git add tests/run_fig519_ihx_r2_hexe_shift.m \
  tests/test_run_fig519_ihx_r2_hexe_shift.m \
  tests/test_fig519_ihx_r2_hexe_contract.py
git commit -m "绑定A3 runner可移植依赖"
```

Expected: all zero-simulation tests pass, output contains no `BEGIN_A3_500`, and no formal A3 run directory exists. Obtain spec and quality review before Task 4.

### Task 4: Migrate offline analysis and durable snapshot verification

**Files:**
- Modify: `tests/analyze_fig519_ihx_r2_hexe_shift.py`
- Modify: `tests/test_fig519_ihx_r2_hexe_contract.py`

- [ ] **Step 1: Write failing full-closure and SHA parser tests**

Build a Task 5-shaped synthetic snapshot whose immutable set is the deduplicated union of exact9 executables, original9 data groups, original recovery manifest, portable manifest, formal state, 34 objects, and seven formal root files. Require the analyzer to archive every byte and verify every SHA.

Add RED cases for missing/extra archive row, duplicate SHA path, root `final_dynamic_24a.slx`, a changed formal hash, a live absolute protected path, and an internal blank line in `SHA256SUMS`.

Require both publication and `verify_only` to reject the same blank-line input before durable manifest commit.

- [ ] **Step 2: Run RED**

```bash
python3 -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
python3 -O -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
```

Expected: current nine-data-group allowlist and inconsistent SHA parser tests fail.

- [ ] **Step 3: Implement one portable resolver and one SHA parser**

Use the portable manifest/formal state for exact identity validation and require all audit paths to be capture-local. Extend the immutable allowlist to the exact closure in the parent plan. Copy every `SHA256SUMS` entry into durable `captured_snapshot/` and rehash it in `verify_only`.

Implement one parser used by publish and verify:

```python
def parse_sha256sums(data: bytes) -> dict[str, str]:
    text = data.decode("utf-8")
    if not text or "\r" in text or any(not line for line in text.split("\n")[:-1]):
        raise SnapshotValidationError("SHA256SUMS contains an empty or non-canonical line")
    # Each remaining line is 64 lowercase hex characters, two spaces, and one safe POSIX path.
```

The parser must reject duplicate paths, absolute paths, backslashes, `.`/`..` components, symlinks, and undeclared files. It must accept one final newline but no internal blank line.

- [ ] **Step 4: Re-run all Task 4 transaction and tamper tests**

```bash
python3 -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
python3 -O -m unittest -v tests.test_fig519_ihx_r2_hexe_contract
python3 -m py_compile tests/analyze_fig519_ihx_r2_hexe_shift.py
```

Expected: all pure/offline tests pass, including pre-simulation failure, five failure classes, consumed-manifest rebuilding, coordinated tamper, crash recovery, and verify-only mtime checks.

- [ ] **Step 5: Commit Task 4 and repeat two-stage review**

```bash
git add tests/analyze_fig519_ihx_r2_hexe_shift.py \
  tests/test_fig519_ihx_r2_hexe_contract.py
git commit -m "闭合A3耐久快照依赖"
```

Task 4 is complete only when spec and quality reviews report no Critical or Important findings.

### Task 5: Prove the cross-language closure and hand back to the parent Task 5

**Files:**
- Modify only if tests require: existing Task 1–4 files listed above
- Runtime only: temporary captured-root fixtures under ignored `tmp/`
- Modify: `docs/superpowers/plans/2026-09-01-ihx-r2-hexe-shift-a3.md` only through the already-approved parent-plan revision

- [ ] **Step 1: Run the complete closure gate**

```bash
python3 -m unittest -v \
  tests.test_publish_a3_capture_dependency_closure \
  tests.test_fig519_ihx_r2_hexe_contract \
  tests.test_publish_fig518a_anchor_evidence
python3 -O -m unittest -v \
  tests.test_publish_a3_capture_dependency_closure \
  tests.test_fig519_ihx_r2_hexe_contract \
  tests.test_publish_fig518a_anchor_evidence
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "r=runtests({'tests/test_create_fig519_ihx_r2_hexe_shift_candidate.m','tests/test_run_fig519_ihx_r2_hexe_shift.m'}); assertSuccess(r)"
```

Expected: no `BEGIN_A3_500`; protected=34, formal records=8, formal existing=7, runtime=9, states=40, solver=37; formal A3 directory absent.

- [ ] **Step 2: Verify formal and governance boundaries**

```bash
git diff --exit-code aaeee0ceb9220e65686fdbbef6ab9b702c7135ff -- \
  final_steady_24a.slx final_dynamic_24a.slx '*.mat' \
  HeXe_property_simulink.m Lithium_property_simulink.m
test ! -e final_dynamic_24a.slx
test ! -e tmp/fig519_ihx_r2_hexe_20260901_A3
git diff --check
```

Expected: formal diff empty, root dynamic absent, formal A3 absent, diff check clean.

- [ ] **Step 3: Obtain closure reviews**

Dispatch a fresh spec reviewer, then a fresh code-quality reviewer. Both must inspect the actual captured-root behavior, not only live-root synthetic fixtures. Any Critical or Important issue blocks the parent Task 5.

- [ ] **Step 4: Resume the revised parent Task 5**

After both reviews are Ready, continue at
`docs/superpowers/plans/2026-09-01-ihx-r2-hexe-shift-a3.md` Task 5. Build the committed runtime capture, reach `READY_NO_SIMULATION`, and stop for the separate phrase `批准 A3 单次正式运行`.
