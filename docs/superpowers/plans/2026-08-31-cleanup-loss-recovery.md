# Cleanup Loss Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recover the exact pre-cleanup A1 model baselines, make them durable Git-tracked provenance assets, migrate the A1 contract away from an ephemeral `tmp/` authority, preserve interrupted Task 3 work, and return the project to the approved A1 execution path without modifying model behavior.

**Architecture:** Export the two SLX files byte-for-byte from local Git commit `f8bcd83`, verify them against the pre-cleanup SHA256 values, and publish them atomically under `data/provenance/baselines/f8bcd83/`. Keep the old absolute-path manifest immutable as incident evidence, audit its 34 entries through exact-hash resolution, and make the runtime A1 contract depend on the durable steady baseline rather than an ignored temporary copy. Re-establish the interrupted Task 3 tests before implementing the smallest builder hardening required by those tests, then resume the existing A1 plan at Task 4.

**Tech Stack:** Git object plumbing, Python 3 standard library (`argparse`, `csv`, `hashlib`, `json`, `pathlib`, `subprocess`, `tempfile`, `unittest`), existing A1 Python modules, SHA256, MATLAB/Simulink only after this recovery plan is complete.

---

## Execution contract

Read before execution:

- `AGENTS.md`
- `决策自律准则.md`
- `交付边界约束_v4.md`
- `验收标准_论文5.4.md`
- `docs/superpowers/specs/2026-08-31-cleanup-loss-recovery-design.md`
- `docs/superpowers/specs/2026-08-30-radiator-a1-staged-parameter-envelope-design.md`
- `docs/superpowers/plans/2026-08-30-radiator-a1-staged-parameter-envelope.md`

Fixed identities:

```text
source repository:
/Users/ikunsredemptionmac/Downloads/不接入转子稳态模型_副本

source commit:
f8bcd833e816eb681982b7dd04364e4b856948e3

steady SHA256:
0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391

dynamic SHA256:
2bed798bcd3d32c15b7771907e8cd5452aa4171a0b87335af7c8769ed6987790

historical protected manifest SHA256:
496e4bbbbe5786bbb21b63d3c320dcfdf3c741935736624ed2912ab81afc9a0a

interrupted Task 3 test working-tree Git blob:
e47b25b0fa1d1c9e45d4d7251a3f5094cdff31b2
```

Hard boundaries:

- Do not load or simulate any SLX during Tasks 1–9.
- Do not edit an SLX or its internal XML. Recovery is byte-for-byte export only.
- Do not replace the expected steady baseline with the different root `final_steady_24a.slx`.
- Do not modify formal `.mat` files or `HeXe_property_simulink.m`.
- Do not delete or clean untracked files.
- Do not rewrite `protected_after.csv`.
- Stage only the exact files listed by each commit step.
- Stop immediately on a SHA256, source-commit, path-whitelist, or tree-cleanliness mismatch.

## File map

| Path | Action | Responsibility |
|---|---|---|
| `tests/test_build_radiator_a1_screen.py` | Preserve, then keep as Test | Interrupted Task 3 hardening contract |
| `tests/test_recover_cleanup_baselines.py` | Create | Recovery source, hash, overwrite, and atomicity tests |
| `tests/recover_cleanup_baselines.py` | Create | Export exact Git blobs and atomically publish durable provenance package |
| `data/provenance/baselines/f8bcd83/final_steady_24a.slx` | Create from verified blob | Durable A1 authority |
| `data/provenance/baselines/f8bcd83/final_dynamic_24a.slx` | Create from verified blob | Historical recovery asset only |
| `data/provenance/baselines/f8bcd83/baseline_manifest.csv` | Generate | Exact commit, size, SHA256, and role registry |
| `data/provenance/baselines/f8bcd83/README.md` | Generate | Identity and non-promotion boundary |
| `tests/test_audit_cleanup_protected_manifest.py` | Create | 34-row historical-manifest resolution tests |
| `tests/audit_cleanup_protected_manifest.py` | Create | Resolve each old path to its original file or an exact durable hash equivalent |
| `data/provenance/baselines/f8bcd83/protected_manifest_recovery.csv` | Generate | Immutable audit result for all 34 old rows |
| `tests/test_radiator_a1_contract.py` | Modify | Lock durable baseline path and historical-manifest mode |
| `tests/radiator_a1_contract.py` | Modify | Verify durable authority; validate old manifest identity without external absolute-path dependency |
| `tests/build_radiator_a1_screen.py` | Modify | Complete interrupted deterministic/atomic/provenance hardening |
| `docs/cleanup_recovery_audit_20260831.md` | Create | Evidence-graded recovery report and next-plan pointer |

## Task 1: Freeze the interrupted Task 3 test contract

**Files:**

- Preserve: `tests/test_build_radiator_a1_screen.py`

- [ ] **Step 1: Recheck the exact working-tree identity**

Run:

```bash
git hash-object tests/test_build_radiator_a1_screen.py
git rev-parse HEAD:tests/test_build_radiator_a1_screen.py
git diff --numstat -- tests/test_build_radiator_a1_screen.py
```

Expected:

```text
e47b25b0fa1d1c9e45d4d7251a3f5094cdff31b2
881d5d5391956097bf7611d4f56267481d1a98bd
457	0	tests/test_build_radiator_a1_screen.py
```

If the first hash differs, stop and inspect the new diff before staging anything.

- [ ] **Step 2: Confirm the diff contains only the interrupted hardening tests**

Run:

```bash
git diff --check -- tests/test_build_radiator_a1_screen.py
git diff -- tests/test_build_radiator_a1_screen.py
```

Expected: no whitespace errors; additions cover rejection logging, schema closure, JSON finite-value rejection, atomic rollback, provenance hashes, proxy recomputation, strict source identity, unplanned-output refusal, exact output hashes, and non-promotion flags.

- [ ] **Step 3: Commit only the preserved test contract**

Run:

```bash
git add -- tests/test_build_radiator_a1_screen.py
git diff --cached --name-only
git commit -m "保存误清理前散热器A1加固测试"
```

Expected: the cached-name command prints exactly `tests/test_build_radiator_a1_screen.py`; the commit contains no implementation or model file.

## Task 2: Add a tested exact-blob recovery utility

**Files:**

- Create: `tests/test_recover_cleanup_baselines.py`
- Create: `tests/recover_cleanup_baselines.py`

- [ ] **Step 1: Write recovery tests before implementation**

Create `tests/test_recover_cleanup_baselines.py` with tests that use a temporary Git repository and synthetic blobs:

```python
from __future__ import annotations

import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest

from tests import recover_cleanup_baselines as recovery


class RecoverCleanupBaselinesTests(unittest.TestCase):
    def make_source(self, root: Path) -> tuple[Path, str, dict[str, bytes]]:
        source = root / "source"
        source.mkdir()
        subprocess.run(["git", "init", "-q", str(source)], check=True)
        subprocess.run(
            ["git", "-C", str(source), "config", "user.name", "test"],
            check=True,
        )
        subprocess.run(
            ["git", "-C", str(source), "config", "user.email", "test@example.invalid"],
            check=True,
        )
        payloads = {
            "final_steady_24a.slx": b"synthetic-steady-slx\x00",
            "final_dynamic_24a.slx": b"synthetic-dynamic-slx\x00",
        }
        for name, payload in payloads.items():
            (source / name).write_bytes(payload)
        subprocess.run(["git", "-C", str(source), "add", "--all"], check=True)
        subprocess.run(
            ["git", "-C", str(source), "commit", "-qm", "fixture"],
            check=True,
        )
        commit = subprocess.run(
            ["git", "-C", str(source), "rev-parse", "HEAD"],
            check=True,
            stdout=subprocess.PIPE,
            text=True,
        ).stdout.strip()
        return source, commit, payloads

    def test_recover_publishes_exact_atomic_package(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source, commit, payloads = self.make_source(root)
            expected = {
                name: recovery.ExpectedBlob(
                    hashlib.sha256(payload).hexdigest(), len(payload), role
                )
                for (name, payload), role in zip(
                    payloads.items(),
                    ("a1_steady_authority", "historical_dynamic_only"),
                    strict=True,
                )
            }
            output = root / "out" / "f8bcd83"
            recovery.recover(source, commit, output, expected, "2026-08-31")
            for name, payload in payloads.items():
                self.assertEqual((output / name).read_bytes(), payload)
            self.assertTrue((output / "baseline_manifest.csv").is_file())
            self.assertTrue((output / "README.md").is_file())

    def test_wrong_hash_leaves_no_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source, commit, payloads = self.make_source(root)
            expected = {
                name: recovery.ExpectedBlob("0" * 64, len(payload), "invalid")
                for name, payload in payloads.items()
            }
            output = root / "out" / "f8bcd83"
            with self.assertRaises(recovery.RecoveryError):
                recovery.recover(source, commit, output, expected, "2026-08-31")
            self.assertFalse(output.exists())

    def test_existing_mismatched_output_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source, commit, payloads = self.make_source(root)
            output = root / "out" / "f8bcd83"
            output.mkdir(parents=True)
            marker = output / "user-data.txt"
            marker.write_text("preserve\n", encoding="utf-8")
            expected = {
                name: recovery.ExpectedBlob(
                    hashlib.sha256(payload).hexdigest(), len(payload), "role"
                )
                for name, payload in payloads.items()
            }
            with self.assertRaises(FileExistsError):
                recovery.recover(source, commit, output, expected, "2026-08-31")
            self.assertEqual(marker.read_text(encoding="utf-8"), "preserve\n")

    def test_materialize_exact_file_is_idempotent_and_refuses_mismatch(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "durable.slx"
            target = root / "tmp" / "compatibility.slx"
            source.write_bytes(b"exact-baseline")
            expected = hashlib.sha256(source.read_bytes()).hexdigest()
            recovery.materialize_exact_file(source, target, expected)
            recovery.materialize_exact_file(source, target, expected)
            self.assertEqual(target.read_bytes(), source.read_bytes())
            target.write_bytes(b"different-user-file")
            with self.assertRaises(FileExistsError):
                recovery.materialize_exact_file(source, target, expected)
            self.assertEqual(target.read_bytes(), b"different-user-file")


if __name__ == "__main__":
    unittest.main(verbosity=2)
```

- [ ] **Step 2: Run the tests and verify the module is missing**

Run:

```bash
python3 -m unittest tests.test_recover_cleanup_baselines -v
```

Expected: ERROR importing `tests.recover_cleanup_baselines`.

- [ ] **Step 3: Implement the recovery utility**

Create `tests/recover_cleanup_baselines.py`. The implementation must define:

```python
@dataclass(frozen=True)
class ExpectedBlob:
    sha256: str
    size_bytes: int
    role: str


EXPECTED_COMMIT = "f8bcd833e816eb681982b7dd04364e4b856948e3"
EXPECTED_BLOBS = {
    "final_steady_24a.slx": ExpectedBlob(
        "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391",
        617390,
        "a1_steady_authority",
    ),
    "final_dynamic_24a.slx": ExpectedBlob(
        "2bed798bcd3d32c15b7771907e8cd5452aa4171a0b87335af7c8769ed6987790",
        660489,
        "historical_dynamic_only",
    ),
}
```

`recover()` must perform this exact order:

1. resolve `commit^{commit}` and require the full hash to equal the requested commit;
2. read each blob with `git -C SOURCE cat-file blob COMMIT:NAME` into memory;
3. require exact byte count and SHA256 before creating the output directory;
4. render `baseline_manifest.csv` with columns `git_path,source_commit,size_bytes,sha256,role,recovery_date`;
5. render `README.md` stating that the dynamic file is historical evidence and does not reinstate old dynamic conclusions;
6. create a staging directory beside the destination;
7. write all four planned files to staging;
8. re-read and re-hash the staged files;
9. publish with one `os.replace(staging, output)` only when `output` does not exist;
10. remove staging on every exception without touching pre-existing paths.

Also implement:

```python
def materialize_exact_file(
    source: Path,
    destination: Path,
    expected_sha256: str,
) -> None:
    payload = source.read_bytes()
    actual = hashlib.sha256(payload).hexdigest()
    if actual != expected_sha256:
        raise RecoveryError(
            f"source hash mismatch: expected={expected_sha256}; actual={actual}"
        )
    if destination.exists() or destination.is_symlink():
        if destination.is_file() and not destination.is_symlink():
            existing = hashlib.sha256(destination.read_bytes()).hexdigest()
            if existing == expected_sha256:
                return
        raise FileExistsError(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        dir=destination.parent,
        prefix=f".{destination.name}.",
        delete=False,
    ) as handle:
        temporary = Path(handle.name)
        handle.write(payload)
    try:
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != expected_sha256:
            raise RecoveryError("temporary materialization hash mismatch")
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)
```

This helper is the explicit, hash-gated way to recreate the former `tmp/source_f8bcd83/` compatibility snapshot if a historical tool needs it. The A1 runtime contract must not use that compatibility copy as its authority.

Expose the CLI:

```text
python3 -m tests.recover_cleanup_baselines SOURCE_REPOSITORY OUTPUT_DIRECTORY
```

The CLI must call `recover()` with `EXPECTED_COMMIT`, `EXPECTED_BLOBS`, and recovery date `2026-08-31`, then print:

```text
CLEANUP_BASELINE_RECOVERY_PASS; FILES=2; SLX_NOT_LOADED
```

- [ ] **Step 4: Run recovery-unit tests**

Run:

```bash
python3 -m unittest tests.test_recover_cleanup_baselines -v
```

Expected: 4 tests, all PASS.

- [ ] **Step 5: Commit the recovery utility and tests**

Run:

```bash
git add -- tests/recover_cleanup_baselines.py tests/test_recover_cleanup_baselines.py
git diff --cached --check
git commit -m "实现误清理基线精确恢复工具"
```

Expected: one commit containing only the two Python files.

## Task 3: Recover and commit the durable baseline package

**Files:**

- Create: `data/provenance/baselines/f8bcd83/final_steady_24a.slx`
- Create: `data/provenance/baselines/f8bcd83/final_dynamic_24a.slx`
- Create: `data/provenance/baselines/f8bcd83/baseline_manifest.csv`
- Create: `data/provenance/baselines/f8bcd83/README.md`

- [ ] **Step 1: Recheck the source repository before export**

Run:

```bash
git -C '/Users/ikunsredemptionmac/Downloads/不接入转子稳态模型_副本' rev-parse --verify 'f8bcd83^{commit}'
git -C '/Users/ikunsredemptionmac/Downloads/不接入转子稳态模型_副本' fsck --full
```

Expected: first command prints `f8bcd833e816eb681982b7dd04364e4b856948e3`; `fsck` reports no corrupt or missing object.

- [ ] **Step 2: Run the recovery utility**

Run:

```bash
python3 -m tests.recover_cleanup_baselines \
  '/Users/ikunsredemptionmac/Downloads/不接入转子稳态模型_副本' \
  'data/provenance/baselines/f8bcd83'
```

Expected:

```text
CLEANUP_BASELINE_RECOVERY_PASS; FILES=2; SLX_NOT_LOADED
```

- [ ] **Step 3: Independently verify the recovered bytes**

Run:

```bash
shasum -a 256 \
  data/provenance/baselines/f8bcd83/final_steady_24a.slx \
  data/provenance/baselines/f8bcd83/final_dynamic_24a.slx
wc -c \
  data/provenance/baselines/f8bcd83/final_steady_24a.slx \
  data/provenance/baselines/f8bcd83/final_dynamic_24a.slx
```

Expected hashes and sizes:

```text
0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391  final_steady_24a.slx
2bed798bcd3d32c15b7771907e8cd5452aa4171a0b87335af7c8769ed6987790  final_dynamic_24a.slx
617390 final_steady_24a.slx
660489 final_dynamic_24a.slx
```

- [ ] **Step 4: Confirm no formal model changed**

Run:

```bash
git status --short
git diff --name-only -- final_steady_24a.slx final_dynamic_24a.slx '*.mat' HeXe_property_simulink.m
```

Expected: only the four new provenance-package files appear; the second command prints nothing.

- [ ] **Step 5: Commit the durable package**

Run:

```bash
git add -- data/provenance/baselines/f8bcd83
git diff --cached --name-only
git commit -m "固化误清理前A1模型基线"
```

Expected: exactly four files under `data/provenance/baselines/f8bcd83/` are committed.

## Task 4: Add a portable 34-row historical-manifest audit

**Files:**

- Create: `tests/test_audit_cleanup_protected_manifest.py`
- Create: `tests/audit_cleanup_protected_manifest.py`
- Runtime create: `data/provenance/baselines/f8bcd83/protected_manifest_recovery.csv`

- [ ] **Step 1: Write failing resolver tests**

Tests must construct a synthetic old manifest with three rows:

1. an original path that still exists and matches;
2. a missing original path whose hash has one exact durable replacement;
3. a missing original path whose hash has no durable replacement.

Assertions:

```python
self.assertEqual(rows[0]["resolution"], "original_path_hash_match")
self.assertEqual(rows[1]["resolution"], "durable_hash_equivalent")
self.assertEqual(rows[2]["resolution"], "unresolved")
self.assertEqual(summary["row_count"], 3)
self.assertEqual(summary["resolved_count"], 2)
self.assertEqual(summary["unresolved_count"], 1)
```

Add a second test requiring a duplicate durable hash to raise `AuditError` rather than selecting a replacement arbitrarily.

- [ ] **Step 2: Run tests and verify the audit module is missing**

Run:

```bash
python3 -m unittest tests.test_audit_cleanup_protected_manifest -v
```

Expected: ERROR importing `tests.audit_cleanup_protected_manifest`.

- [ ] **Step 3: Implement exact-hash resolution**

`tests/audit_cleanup_protected_manifest.py` must:

- parse only a CSV with header `paths,hashes`;
- reject malformed or duplicate rows;
- index only explicitly supplied durable files by SHA256;
- prefer a present original path only when its hash matches;
- use a durable replacement only when exactly one supplied durable file has the expected hash;
- mark all other rows unresolved;
- never copy, remove, or overwrite the old absolute paths;
- write a deterministic CSV with columns:

```text
original_path,expected_sha256,original_state,resolution,resolved_path,resolved_sha256
```

- exit nonzero when any row is unresolved.

- [ ] **Step 4: Run audit-unit tests**

Run:

```bash
python3 -m unittest tests.test_audit_cleanup_protected_manifest -v
```

Expected: all tests PASS.

- [ ] **Step 5: Run the real 34-row audit**

Run:

```bash
python3 -m tests.audit_cleanup_protected_manifest \
  tmp/tp7d213f64_7fad_4bfa_b722_0771b21d9640/protected_after.csv \
  data/provenance/baselines/f8bcd83/protected_manifest_recovery.csv \
  data/provenance/baselines/f8bcd83/final_steady_24a.slx \
  data/provenance/baselines/f8bcd83/final_dynamic_24a.slx
```

Expected:

```text
PROTECTED_MANIFEST_RECOVERY_PASS; ROWS=34; RESOLVED=34; ORIGINAL_PRESENT=31; DURABLE_EQUIVALENT=3
```

- [ ] **Step 6: Commit the audit utility, tests, and result**

Run:

```bash
git add -- \
  tests/audit_cleanup_protected_manifest.py \
  tests/test_audit_cleanup_protected_manifest.py \
  data/provenance/baselines/f8bcd83/protected_manifest_recovery.csv
git diff --cached --check
git commit -m "审计误清理前保护清单可恢复性"
```

Expected: one commit with exactly three files.

## Task 5: Migrate the A1 authority from `tmp/` to durable provenance

**Files:**

- Modify: `tests/test_radiator_a1_contract.py:10-19,51-61,159-171`
- Modify: `tests/radiator_a1_contract.py:11-23,190-289`

- [ ] **Step 1: Change the contract tests first**

Replace `BASELINE_RELATIVE` in `tests/test_radiator_a1_contract.py` with:

```python
BASELINE_RELATIVE = (
    "data/provenance/baselines/f8bcd83/final_steady_24a.slx"
)
PROTECTED_MODE = "historical_manifest_identity_only"
```

Extend `test_source_contract_verifies_hashes_and_preserves_status_gates`:

```python
self.assertEqual(result["protected_manifest_mode"], PROTECTED_MODE)
self.assertEqual(result["protected_count"], 34)
```

Add a test that copies the real 34-row manifest to a temporary file, changes one path to a unique nonexistent absolute path, recomputes the temporary manifest SHA256, and patches `contract.PROTECTED` plus `contract.PROTECTED_SHA256`. `verify_source_contract()` must still pass because runtime authority no longer depends on external working-tree paths.

- [ ] **Step 2: Run the focused contract tests and verify RED**

Run:

```bash
python3 -m unittest tests.test_radiator_a1_contract -v
```

Expected: FAIL because `contract.BASELINE` still points into `tmp/` and the result lacks `protected_manifest_mode`.

- [ ] **Step 3: Make the minimal contract migration**

In `tests/radiator_a1_contract.py`, set:

```python
BASELINE = (
    ROOT
    / "data/provenance/baselines/f8bcd83/final_steady_24a.slx"
)
PROTECTED_MANIFEST_MODE = "historical_manifest_identity_only"
```

Keep the exact existing values of `BASELINE_SHA256`, `PROTECTED`, and `PROTECTED_SHA256`.

Retain validation of the historical CSV header, 34-row count, unique nonempty absolute paths, and lowercase 64-character hashes. Remove only the loop that requires every historical absolute path to exist at runtime. Add this field to the return value:

```python
"protected_manifest_mode": PROTECTED_MANIFEST_MODE,
```

The separate Task 4 audit remains responsible for proving that all 34 old rows resolve by original path or exact durable equivalent.

- [ ] **Step 4: Run the contract tests**

Run:

```bash
python3 -m unittest tests.test_radiator_a1_contract -v
```

Expected: all contract tests PASS.

- [ ] **Step 5: Run the contract under optimized Python**

Run:

```bash
python3 -O -m unittest tests.test_radiator_a1_contract -v
```

Expected: all tests PASS; guards do not depend on `assert` statements.

- [ ] **Step 6: Commit the contract migration**

Run:

```bash
git add -- tests/radiator_a1_contract.py tests/test_radiator_a1_contract.py
git diff --cached --check
git commit -m "迁移散热器A1不可变基线合同"
```

Expected: one commit containing only the contract module and its test.

## Task 6: Re-establish the interrupted Task 3 RED baseline

**Files:**

- Test: `tests/test_build_radiator_a1_screen.py`
- Modify later: `tests/build_radiator_a1_screen.py`

- [ ] **Step 1: Run the preserved builder tests without modifying implementation**

Run:

```bash
python3 -m unittest tests.test_build_radiator_a1_screen -v
```

Expected: original Task 3 tests pass; new hardening tests fail in the following capability groups:

- schema/provenance closure;
- non-finite serialization preflight;
- strict source identity;
- proxy overflow and nonpositive derived quantities;
- exact planned-output hashing;
- rollback after mid-write failure;
- unplanned output entry rejection;
- non-promotion flags at every layer.

Record the exact failing-test names before changing code. A contract/baseline missing error at this stage is a recovery regression and must be fixed before continuing.

- [ ] **Step 2: Confirm the builder implementation is still the committed pre-cleanup version**

Run:

```bash
git hash-object tests/build_radiator_a1_screen.py
git rev-parse HEAD:tests/build_radiator_a1_screen.py
```

Expected: both commands print `c371fc73e05c8d786b127a3be11f6be80d884eb5`.

## Task 7: Harden source identity and proxy derivation

**Files:**

- Modify: `tests/build_radiator_a1_screen.py:24-188`
- Test: `tests/test_build_radiator_a1_screen.py:359-471,548-772,814-876`

- [ ] **Step 1: Implement exact role-source identity checks**

Update `_static_for_role()` so a match requires all of these identities, not only approximate numeric equality:

```text
branch_id
technology_maturity
flow_case and exact FLOWS evidence/unit/value
epsilon_case and exact EMISSIVITIES evidence/unit/value
sink_case and exact SINKS evidence/unit/value
h_case and exact H_ANCHORS evidence/unit/value
canonical row_id
condition_status in {eligible, rejected, unidentifiable_due_to_missing_input}
```

Reject empty contract-axis evidence. Numeric values must equal the frozen contract values exactly; do not use `_same()` for source identity. Require exactly one matching row.

- [ ] **Step 2: Implement structured proxy failure handling**

Compute:

```python
capacity = M_rad_kg * cp_proxy_J_kgK
conductance = (
    UA_W_K
    + 4.0
    * a1math.SIGMA
    * epsilon
    * A_rad_m2
    * Twall_K**3
)
tau = capacity / conductance
```

Wrap overflow and division failures. If `capacity`, `conductance`, or `tau` is non-finite or nonpositive:

```python
eligible_for_slx = False
timescale_relation = "not_available"
rejection_reasons = existing_reasons + (
    "nonpositive_or_nonfinite_proxy_derived_quantity",
)
```

Deduplicate the machine reason while preserving order. Never drop the fixed representative role.

- [ ] **Step 3: Add complete source, unit, and equation identity fields**

Every representative row and eligible manifest must contain the exact ordered fields asserted by `test_build_screen_exact_fields_units_order_and_statuses`. Build `unit_contract` as the exact dictionary asserted by `test_unit_contract_closes_every_physical_numeric_field`.

Set:

```python
equation_version = "radiator_a1_static_v1"
unit_contract_ref = "source_contract/unit_contract.json"
source_contract_ref = "source_contract/source_contract.json"
spec_path = "docs/superpowers/specs/2026-08-30-radiator-a1-staged-parameter-envelope-design.md"
run_time_record = {
    "mode": "deferred_to_execution_stage",
    "wall_clock_utc": None,
    "reason": "deterministic_offline_core",
}
paper_reproduced = False
formal_promotion = False
```

Hash the spec, generator, contract module, and math module with `contract.sha256()` at package-build time. `input_provenance` must have exactly the keys `branch`, `static_inputs`, and `cp_proxy`.

- [ ] **Step 4: Run the source/proxy subset**

Run:

```bash
python3 -m unittest -v \
  tests.test_build_radiator_a1_screen.BuildRadiatorA1ScreenTests.test_static_role_rejects_any_source_identity_drift \
  tests.test_build_radiator_a1_screen.BuildRadiatorA1ScreenTests.test_static_role_rejects_empty_contract_axis_evidence \
  tests.test_build_radiator_a1_screen.BuildRadiatorA1ScreenTests.test_proxy_derived_failures_are_structured_and_never_drop_roles \
  tests.test_build_radiator_a1_screen.BuildRadiatorA1ScreenTests.test_unit_contract_closes_every_physical_numeric_field \
  tests.test_build_radiator_a1_screen.BuildRadiatorA1ScreenTests.test_selection_and_all_layers_keep_nonpromotion_flags_false
```

Expected: all five tests PASS.

- [ ] **Step 5: Commit source/proxy hardening**

Run:

```bash
git add -- tests/build_radiator_a1_screen.py
git diff --cached --check
git commit -m "加固散热器A1来源与代理量闭合"
```

Expected: implementation-only commit; preserved tests remain unchanged from Task 1.

## Task 8: Make package publication preflighted, exact, and atomic

**Files:**

- Modify: `tests/build_radiator_a1_screen.py:191-348`
- Test: `tests/test_build_radiator_a1_screen.py:186-309,474-546,775-812`

- [ ] **Step 1: Render every payload in memory before touching output**

Add helpers with these contracts:

```python
def _json_bytes(value: Any) -> bytes:
    return (
        json.dumps(
            value,
            indent=2,
            sort_keys=True,
            allow_nan=False,
        )
        + "\n"
    ).encode("utf-8")


def _csv_bytes(rows: list[dict[str, Any]]) -> bytes:
    if not rows:
        raise ValueError("CSV rows must not be empty")
    fieldnames = list(rows[0])
    if any(list(row) != fieldnames for row in rows):
        raise ValueError("CSV rows must have identical ordered schema")
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=fieldnames, lineterminator="\n")
    writer.writeheader()
    writer.writerows(
        {key: _normalize_csv_value(value) for key, value in row.items()}
        for row in rows
    )
    return buffer.getvalue().encode("utf-8")
```

Build one `dict[PurePosixPath, bytes]` containing all source contracts, CSV files, selection JSON, and eligible manifests. Compute `output_hashes.json` from this in-memory dictionary and exclude only itself.

- [ ] **Step 2: Reject every pre-existing output entry before writing**

Require the resolved output to be a strict descendant of `ROOT/tmp`. If the output path exists, it must be an empty real directory with no files, directories, or symlinks. Any unplanned entry raises before `build_screen()` publishes bytes.

For every planned relative path, reject absolute paths, `..`, empty parts, and symlinked ancestors.

- [ ] **Step 3: Publish to a private staging tree and roll back on failure**

Add:

```python
def _write_bytes_exclusive(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as handle:
        handle.write(payload)
```

`write_screen()` must:

1. snapshot/preflight the empty output;
2. render and validate all payloads in memory;
3. create one staging directory beside the output;
4. call `_write_bytes_exclusive()` for every planned payload;
5. re-hash staged files and compare them with planned payload hashes;
6. move the staged children into the empty output only after all writes succeed;
7. on any exception, remove only the staging tree and anything created inside the originally empty output;
8. leave any pre-existing user file, directory, or symlink unchanged.

The rejection log must include every offline row whose `condition_status != "eligible"`, including `unidentifiable_due_to_missing_input`.

- [ ] **Step 4: Run atomic-publication tests**

Run:

```bash
python3 -m unittest -v \
  tests.test_build_radiator_a1_screen.BuildRadiatorA1ScreenTests.test_csv_schema_mismatch_is_rejected_before_any_write \
  tests.test_build_radiator_a1_screen.BuildRadiatorA1ScreenTests.test_json_nan_is_rejected_before_any_write \
  tests.test_build_radiator_a1_screen.BuildRadiatorA1ScreenTests.test_manifest_nan_and_unserializable_value_leave_no_partial_package \
  tests.test_build_radiator_a1_screen.BuildRadiatorA1ScreenTests.test_mid_write_oserror_rolls_back_only_created_tree \
  tests.test_build_radiator_a1_screen.BuildRadiatorA1ScreenTests.test_unplanned_output_entries_are_rejected_without_change \
  tests.test_build_radiator_a1_screen.BuildRadiatorA1ScreenTests.test_output_hashes_cover_exact_in_memory_planned_payloads \
  tests.test_build_radiator_a1_screen.BuildRadiatorA1ScreenTests.test_rejection_log_includes_every_noneligible_offline_status
```

Expected: all seven tests PASS.

- [ ] **Step 5: Run the entire Task 3 suite**

Run:

```bash
python3 -m unittest tests.test_build_radiator_a1_screen -v
python3 -O -m unittest tests.test_build_radiator_a1_screen -v
```

Expected: all tests PASS in normal and optimized Python.

- [ ] **Step 6: Commit publication hardening**

Run:

```bash
git add -- tests/build_radiator_a1_screen.py
git diff --cached --check
git commit -m "恢复散热器A1原子证据发布实现"
```

Expected: one implementation-only commit.

## Task 9: Run the recovery gate and publish the incident audit

**Files:**

- Create: `docs/cleanup_recovery_audit_20260831.md`

- [ ] **Step 1: Run all recovery and A1 offline tests**

Run:

```bash
python3 -m unittest -v \
  tests.test_recover_cleanup_baselines \
  tests.test_audit_cleanup_protected_manifest \
  tests.test_radiator_a1_contract \
  tests.test_radiator_a1_math \
  tests.test_build_radiator_a1_screen
```

Expected: all tests PASS.

- [ ] **Step 2: Generate a disposable fresh offline package**

Choose a new empty path under `tmp/`, never reuse an earlier run root:

```bash
python3 -m tests.build_radiator_a1_screen \
  tmp/radiator_A1_recovery_gate_20260831
```

Expected:

```text
RADIATOR_A1_OFFLINE_SCREEN_PASS; ROWS=96; NO_MODEL_LOAD
```

- [ ] **Step 3: Verify the package counts and source identity**

Run:

```bash
python3 -c "import csv,json,pathlib; r=pathlib.Path('tmp/radiator_A1_recovery_gate_20260831'); rows=list(csv.DictReader((r/'offline_screen/offline_96.csv').open())); reps=list(csv.DictReader((r/'representatives/representative_matrix.csv').open())); source=json.loads((r/'source_contract/source_contract.json').read_text()); assert len(rows)==96; assert len(reps)==12; assert source['baseline_sha256']=='0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391'; assert source['baseline_path']=='data/provenance/baselines/f8bcd83/final_steady_24a.slx'; assert not source['paper_reproduced']; assert not source['formal_promotion']; print({'rows':len(rows),'roles':len(reps),'baseline':source['baseline_sha256']})"
```

Expected: `rows` is 96, `roles` is 12, and the printed baseline is the exact steady SHA256.

- [ ] **Step 4: Recheck protected files and formal-model non-mutation**

Run:

```bash
shasum -a 256 tmp/tp7d213f64_7fad_4bfa_b722_0771b21d9640/protected_after.csv
git diff --name-only -- final_steady_24a.slx final_dynamic_24a.slx '*.mat' HeXe_property_simulink.m
git status --short
```

Expected: protected manifest hash is `496e4bbb...f9a0a`; formal-model diff is empty. Status may still list pre-existing unrelated untracked files, which must remain untouched.

- [ ] **Step 5: Write the evidence-graded audit report**

Create `docs/cleanup_recovery_audit_20260831.md` containing:

- ✅ source repository and full source commit;
- ✅ both recovered SHA256 values and byte sizes;
- ✅ historical manifest result `34 resolved / 31 original / 3 durable equivalent / 0 unresolved`;
- ✅ exact tests and commands run;
- ✅ formal-model and formal-data non-mutation result;
- ⚠️ interrupted implementation was reconstructed from preserved tests, not recovered as an original blob;
- ❓ untracked-file completeness remains unknowable without a pre-clean inventory;
- a pointer to `docs/superpowers/plans/2026-08-30-radiator-a1-staged-parameter-envelope.md`, resuming at Task 4;
- explicit `paper_reproduced = false` and `formal_promotion = false` statements.

- [ ] **Step 6: Commit the audit report**

Run:

```bash
git add -- docs/cleanup_recovery_audit_20260831.md
git diff --cached --check
git commit -m "记录误清理恢复验收结果"
```

Expected: report-only commit.

## Task 10: Resume the approved A1 plan at Task 4

**Files:**

- Read and execute: `docs/superpowers/plans/2026-08-30-radiator-a1-staged-parameter-envelope.md:854`

- [ ] **Step 1: Confirm the recovery completion gate**

Require all of the following before MATLAB is invoked:

```text
durable steady baseline hash = 0532e9dd...a5a391
durable dynamic historical hash = 2bed798b...87790
protected manifest rows resolved = 34/34
recovery/A1 offline Python tests = PASS
fresh offline rows = 96
fixed representative roles = 12
formal SLX/MAT/property-function diff = empty
```

- [ ] **Step 2: Continue with existing Task 4, not a rewritten scientific plan**

Resume at:

```text
Task 4: 用官方 API 建立断言保护的候选补丁
```

Carry forward one path substitution wherever the old A1 plan names the authority:

```text
old:
tmp/steady53_curves_20260828/source_f8bcd83/final_steady_24a.slx

new:
data/provenance/baselines/f8bcd83/final_steady_24a.slx
```

The SHA256 remains unchanged. Every other A1 restriction remains unchanged: official MATLAB/Simulink API modifications only, independent candidate copies, no formal-model mutation, no replacement of rejected fixed roles, `500 s` before `14000 s`, and no automatic promotion based on paper-curve similarity.

## Self-review checklist

- [ ] Every requirement in the 2026-08-31 recovery design maps to Tasks 1–10.
- [ ] No step edits or loads an SLX; binary recovery is exact Git-blob export.
- [ ] The current root steady model is never used as the historical A1 authority.
- [ ] The old absolute-path manifest remains byte-identical.
- [ ] Runtime A1 verification no longer depends on the external backup checkout.
- [ ] The three missing old paths remain visible in the incident audit rather than being hidden.
- [ ] The interrupted tests are committed before implementation changes.
- [ ] Builder changes are driven by named failing tests and split into source/proxy and publication commits.
- [ ] Normal and optimized Python both exercise hard gates.
- [ ] MATLAB remains blocked until the recovery completion gate passes.
- [ ] The old A1 plan resumes at Task 4 without changing the approved scientific envelope.
