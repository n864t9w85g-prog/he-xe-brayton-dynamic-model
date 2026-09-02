# Radiator Two-State Feasibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and execute one read-only offline feasibility gate that determines whether thesis Eq. (5.15), with constant positive `C_fluid` and `UA`, can jointly explain the digitized Figure 5.18(d) outlet and wall temperature histories.

**Architecture:** A strict evidence-contract module freezes the paper, digitization, units, cases, and protected formal files. A pure-math module computes interval coefficients, sign bounds, unrestricted/NNLS solutions, uncertainty-corner residuals, and the fixed result enum. A one-shot runner writes a fresh atomic evidence bundle under `tmp/`; a separate Decimal-based verifier re-derives the arithmetic before a minimal immutable summary is published under `data/provenance/`.

**Tech Stack:** Python 3.14 standard library (`csv`, `dataclasses`, `decimal`, `hashlib`, `itertools`, `json`, `math`, `pathlib`, `tempfile`, `unittest`); no MATLAB, Simulink, NumPy, SciPy, Wolfram, or network access.

---

## Fixed experiment contract

- Approved specification: `docs/superpowers/specs/2026-09-02-radiator-two-state-feasibility-design.md`.
- Specification SHA-256: `6bfab38ab3a3979b9ce1a38ef3cf162c464898c6ec1b4699a0dddb40c185898b`.
- Thesis PDF SHA-256: `983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a`.
- Digitized CSV SHA-256: `6aed804bf1ac57832055dab34483bdcb25567a5b902e5b3c6b85cb7129e8849b`.
- Digitization provenance SHA-256: `fe35a863731ff5394095f5d268a988cb45120a1382db9fd53bc0599e8f98e0cd`.
- Fixed inlet temperature: `609.58 K`.
- Fixed flow identities: `project_flow=6.95 kg/s` and `energy_closure_flow=7.134146337 kg/s`.
- Fixed energy paths: `inlet_cp` and `integral_enthalpy`.
- Fixed read-off allowances: `±3 K` and `±2 s`; these remain scan-reading allowances, not acceptance tolerances.
- Exactly four cases are evaluated: Cartesian product of the two fixed flows and two fixed energy paths. There is no continuous scan.
- No SLX may be loaded, compiled, simulated, unpacked, rewritten, or created.
- No formal SLX, top-level MAT, property function, digitized point, provenance record, or acceptance document may change.
- Every result must preserve `paper_reproduced=false`, `author_parameter_identified=false`, and `formal_promotion=false`.

## Result aggregation rule

Each of the four fixed cases receives a case enum. The overall enum is selected in this exact order:

```python
if all(case == "robustly_infeasible" for case in case_enums):
    overall = "constant_positive_two_state_robustly_infeasible"
elif all(case in {"robustly_infeasible", "reading_sensitive"}
         for case in case_enums):
    overall = (
        "constant_positive_two_state_"
        "nominally_infeasible_but_reading_sensitive"
    )
elif any(case == "conditionally_feasible" for case in case_enums):
    overall = "constant_positive_two_state_conditionally_feasible"
else:
    overall = "constant_positive_two_state_full_interval_inconsistent"
```

This ordering treats the two flow identities as alternatives: one fully compatible fixed case is enough to retain a conditional feasibility route, but it never identifies the author's flow or parameters. Evidence-contract failure bypasses this rule and produces only `evidence_contract_failure`.

## File-responsibility map

| File | Responsibility |
|---|---|
| `tests/radiator_two_state_contract.py` | Freeze source hashes, CSV schema, constants, cases, flags, and protected formal-file snapshots |
| `tests/test_radiator_two_state_contract.py` | Exercise valid and tampered evidence contracts |
| `tests/radiator_two_state_math.py` | Pure interval algebra, LS/NNLS, sign and corner bounds, per-case and overall classification |
| `tests/test_radiator_two_state_math.py` | Synthetic analytic tests for every mathematical branch |
| `tests/run_radiator_two_state_feasibility.py` | Execute exactly four offline cases and atomically write a fresh evidence bundle |
| `tests/test_run_radiator_two_state_feasibility.py` | End-to-end schema, failure, collision, false-flag, and no-SLX tests |
| `tests/verify_radiator_two_state_feasibility.py` | Independently re-derive coefficients/solutions with `Decimal` and verify all hashes |
| `tests/test_verify_radiator_two_state_feasibility.py` | Prove verification and fresh minimal publication accept genuine output and reject tampering/collisions |
| `tmp/radiator_two_state_feasibility_20260902_A/` | Fresh raw run evidence; never committed or reused |
| `data/provenance/steady53/fig5_18d/two_state_feasibility/` | Verified minimal durable evidence and manifest |

### Task 1: Freeze the evidence and protected-file contract

**Files:**
- Create: `tests/radiator_two_state_contract.py`
- Create: `tests/test_radiator_two_state_contract.py`

- [ ] **Step 1: Write the failing contract tests**

Create `tests/test_radiator_two_state_contract.py` with tests that require exact identities and structural validation:

```python
import csv
from pathlib import Path
import tempfile
import unittest

from tests import radiator_two_state_contract as contract


class RadiatorTwoStateContractTests(unittest.TestCase):
    def test_repository_evidence_contract_is_exact(self):
        evidence = contract.verify_input_contract()
        self.assertEqual(len(evidence.samples), 12)
        self.assertEqual(
            evidence.header,
            ("x_px", "wall_y_px", "outlet_y_px", "time_s", "wall_K", "outlet_K"),
        )
        self.assertEqual(evidence.samples[0].time_s, 4.62962962962963)
        self.assertEqual(evidence.samples[-1].time_s, 187.96296296296296)
        self.assertEqual(tuple(case.case_id for case in contract.CASES), (
            "project_flow__inlet_cp",
            "project_flow__integral_enthalpy",
            "energy_closure_flow__inlet_cp",
            "energy_closure_flow__integral_enthalpy",
        ))

    def test_protected_snapshot_has_exact_formal_scope(self):
        snapshot = contract.snapshot_protected_files()
        self.assertEqual(tuple(snapshot), contract.PROTECTED_RELATIVE_PATHS)
        self.assertTrue(all(len(digest) == 64 for digest in snapshot.values()))

    def test_tampered_curve_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            altered = Path(folder) / "points.csv"
            rows = contract.POINTS_CSV.read_text(encoding="utf-8")
            altered.write_text(rows.replace("2.509345794392523317e+02", "nan", 1))
            with self.assertRaisesRegex(
                contract.EvidenceContractError, "curve_sha256"
            ):
                contract.verify_input_contract(points_path=altered)

    def test_valid_hash_with_bad_shape_is_still_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            altered = Path(folder) / "points.csv"
            with contract.POINTS_CSV.open(newline="", encoding="utf-8") as handle:
                rows = list(csv.reader(handle))
            altered.write_text("\n".join(",".join(row) for row in rows[:-1]) + "\n")
            with self.assertRaises(contract.EvidenceContractError):
                contract.parse_points(altered, expected_sha256=None)


if __name__ == "__main__":
    unittest.main(verbosity=2)
```

- [ ] **Step 2: Run RED**

```bash
python3 -m unittest -v tests.test_radiator_two_state_contract
python3 -O -m unittest -v tests.test_radiator_two_state_contract
```

Expected: both commands fail because `tests.radiator_two_state_contract` does not exist.

- [ ] **Step 3: Implement the minimal immutable contract**

Create `tests/radiator_two_state_contract.py` with these public types, constants, and checks:

```python
from __future__ import annotations

import csv
from dataclasses import dataclass
import hashlib
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / "docs/superpowers/specs/2026-09-02-radiator-two-state-feasibility-design.md"
PAPER = ROOT / "空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf"
POINTS_CSV = ROOT / "data/provenance/steady53/fig5_18d/paper_curve/points.csv"
POINTS_PROVENANCE = ROOT / "data/provenance/steady53/fig5_18d/paper_curve/provenance.json"

INPUT_HASHES = {
    SPEC: "6bfab38ab3a3979b9ce1a38ef3cf162c464898c6ec1b4699a0dddb40c185898b",
    PAPER: "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a",
    POINTS_CSV: "6aed804bf1ac57832055dab34483bdcb25567a5b902e5b3c6b85cb7129e8849b",
    POINTS_PROVENANCE: "fe35a863731ff5394095f5d268a988cb45120a1382db9fd53bc0599e8f98e0cd",
}
EXPECTED_HEADER = (
    "x_px", "wall_y_px", "outlet_y_px", "time_s", "wall_K", "outlet_K"
)
PROTECTED_RELATIVE_PATHS = (
    "final_steady_24a.slx",
    "HeXe_property_simulink.m",
    "Lithium_property_simulink.m",
    "hexe_compressor_lookup.mat",
    "radiator_table.mat",
    "turbine_table1.mat",
    "turbine_table2.mat",
)
TIN_K = 609.58
TEMPERATURE_ALLOWANCE_K = 3.0
TIME_ALLOWANCE_S = 2.0
FALSE_FLAGS = {
    "paper_reproduced": False,
    "author_parameter_identified": False,
    "formal_promotion": False,
}


class EvidenceContractError(RuntimeError):
    pass


@dataclass(frozen=True)
class Sample:
    x_px: float
    wall_y_px: float
    outlet_y_px: float
    time_s: float
    wall_K: float
    outlet_K: float


@dataclass(frozen=True)
class Case:
    case_id: str
    flow_id: str
    m_dot_kg_s: float
    energy_path: str


@dataclass(frozen=True)
class Evidence:
    header: tuple[str, ...]
    samples: tuple[Sample, ...]
    source_hashes: dict[str, str]


CASES = (
    Case("project_flow__inlet_cp", "project_flow", 6.95, "inlet_cp"),
    Case("project_flow__integral_enthalpy", "project_flow", 6.95, "integral_enthalpy"),
    Case("energy_closure_flow__inlet_cp", "energy_closure_flow", 7.134146337, "inlet_cp"),
    Case("energy_closure_flow__integral_enthalpy", "energy_closure_flow", 7.134146337, "integral_enthalpy"),
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _require(condition: bool, field: str, actual: object) -> None:
    if not condition:
        raise EvidenceContractError(f"{field}: {actual!r}")


def parse_points(path: Path, expected_sha256: str | None) -> Evidence:
    _require(path.is_file(), "curve_exists", path)
    actual_hash = sha256(path)
    if expected_sha256 is not None:
        _require(actual_hash == expected_sha256, "curve_sha256", actual_hash)
    try:
        with path.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            _require(tuple(reader.fieldnames or ()) == EXPECTED_HEADER,
                     "curve_header", reader.fieldnames)
            raw_rows = list(reader)
    except EvidenceContractError:
        raise
    except (OSError, UnicodeError, csv.Error) as exc:
        raise EvidenceContractError(
            f"curve_read: {type(exc).__name__}: {exc}"
        ) from exc
    _require(len(raw_rows) == 12, "curve_row_count", len(raw_rows))
    samples = []
    for row_number, row in enumerate(raw_rows, start=2):
        try:
            values = [float(row[name]) for name in EXPECTED_HEADER]
        except (KeyError, TypeError, ValueError) as exc:
            raise EvidenceContractError(f"curve_row_{row_number}: {exc}") from exc
        _require(all(math.isfinite(value) for value in values),
                 f"curve_row_{row_number}_finite", values)
        samples.append(Sample(*values))
    _require(all(b.time_s > a.time_s for a, b in zip(samples, samples[1:])),
             "curve_time_order", [sample.time_s for sample in samples])
    return Evidence(EXPECTED_HEADER, tuple(samples), {str(path.relative_to(ROOT)): actual_hash})


def verify_input_contract(points_path: Path = POINTS_CSV) -> Evidence:
    source_hashes = {}
    for path, expected in INPUT_HASHES.items():
        actual = sha256(path) if path.is_file() else "missing"
        _require(actual == expected, f"input_sha256:{path.name}", actual)
        source_hashes[str(path.relative_to(ROOT))] = actual
    expected_curve_hash = INPUT_HASHES[POINTS_CSV] if points_path == POINTS_CSV else INPUT_HASHES[POINTS_CSV]
    parsed = parse_points(points_path, expected_curve_hash)
    return Evidence(parsed.header, parsed.samples, source_hashes)


def snapshot_protected_files() -> dict[str, str]:
    snapshot = {}
    for relative in PROTECTED_RELATIVE_PATHS:
        path = ROOT / relative
        _require(path.is_file(), f"protected_exists:{relative}", path)
        snapshot[relative] = sha256(path)
    return snapshot
```

The temporary altered-file test intentionally fails at the frozen hash before data parsing. The separate `parse_points(..., expected_sha256=None)` test exercises schema and numeric validation without weakening the production contract.

- [ ] **Step 4: Run GREEN and commit**

```bash
python3 -m unittest -v tests.test_radiator_two_state_contract
python3 -O -m unittest -v tests.test_radiator_two_state_contract
git add tests/radiator_two_state_contract.py tests/test_radiator_two_state_contract.py
git commit -m "固化散热器两状态证据合同"
```

Expected: all tests pass in normal and optimized Python; only the two test-area files are committed.

### Task 2: Implement and prove the interval mathematics

**Files:**
- Create: `tests/radiator_two_state_math.py`
- Create: `tests/test_radiator_two_state_math.py`

- [ ] **Step 1: Write failing analytic tests**

Create `tests/test_radiator_two_state_math.py`. Use only synthetic fixtures for exact solver behavior, plus fixed scalar regressions for the current NaK polynomial:

```python
import math
import unittest

from tests import radiator_two_state_contract as contract
from tests import radiator_two_state_math as model


class RadiatorTwoStateMathTests(unittest.TestCase):
    def test_nak_polynomial_and_antiderivative_are_fixed(self):
        self.assertAlmostEqual(model.cp_nak_J_kgK(609.58), 887.1506566206109, places=10)
        self.assertAlmostEqual(model.h_nak_J_kg(609.58), 586825.6073986125, places=9)
        a, b = 350.0, 609.58
        numerical = sum(
            model.cp_nak_J_kgK(a + (index + 0.5) * (b-a) / 100000)
            for index in range(100000)
        ) * (b-a) / 100000
        self.assertTrue(math.isclose(
            model.h_nak_J_kg(b) - model.h_nak_J_kg(a),
            numerical, rel_tol=2e-11, abs_tol=1e-6,
        ))

    def test_interval_coefficients_match_hand_calculation(self):
        first = contract.Sample(0, 0, 0, 0, 280, 300)
        second = contract.Sample(0, 0, 0, 10, 300, 320)
        coefficient = model.interval_coefficient(
            first, second, tin_K=600, m_dot_kg_s=2,
            q_function=lambda _tin, tout, mdot: mdot * 1000 * (_tin-tout),
        )
        self.assertEqual(coefficient.A_K, 4.0)
        self.assertEqual(coefficient.B_K_s, 2520.0)
        self.assertEqual(coefficient.D_J, 5_800_000.0)

    def test_unrestricted_and_nnls_solvers_cover_interior_and_boundary(self):
        exact = (
            model.Coefficient(0, 0, 1, 1, 0, 20),
            model.Coefficient(1, 1, 2, 0, 1, 30),
            model.Coefficient(2, 2, 3, 1, 1, 50),
        )
        self.assertEqual(model.solve_unrestricted(exact), model.Solution(20, 30, 0))
        self.assertEqual(model.solve_nnls(exact), model.Solution(20, 30, 0))
        boundary = (
            model.Coefficient(0, 0, 1, 1, 0, -1),
            model.Coefficient(1, 1, 2, 0, 1, 2),
        )
        self.assertEqual(model.solve_nnls(boundary), model.Solution(0, 2, 1))

    def test_positive_exact_candidate_is_locally_compatible(self):
        samples = (
            contract.Sample(0, 0, 0, 0, 280, 300),
            contract.Sample(0, 0, 0, 10, 300, 320),
        )
        coefficient = model.interval_coefficient(
            samples[0], samples[1], 600, 2,
            lambda _tin, tout, mdot: mdot * 1000 * (_tin-tout),
        )
        candidate = model.Solution(10, (coefficient.D_J-40) / coefficient.B_K_s, 0)
        bounds = model.corner_residual_range(
            samples[0], samples[1], candidate, 600, 2,
            lambda _tin, tout, mdot: mdot * 1000 * (_tin-tout),
            temperature_allowance_K=3, time_allowance_s=2,
        )
        self.assertLessEqual(bounds.minimum_J, 0)
        self.assertGreaterEqual(bounds.maximum_J, 0)
        self.assertTrue(bounds.contains_zero)

    def test_global_classification_order_is_fixed(self):
        self.assertEqual(model.aggregate_case_enums(["robustly_infeasible"] * 4),
                         "constant_positive_two_state_robustly_infeasible")
        self.assertEqual(model.aggregate_case_enums([
            "robustly_infeasible", "reading_sensitive",
            "robustly_infeasible", "reading_sensitive",
        ]), "constant_positive_two_state_nominally_infeasible_but_reading_sensitive")
        self.assertEqual(model.aggregate_case_enums([
            "robustly_infeasible", "full_interval_inconsistent",
            "conditionally_feasible", "full_interval_inconsistent",
        ]), "constant_positive_two_state_conditionally_feasible")
        self.assertEqual(model.aggregate_case_enums([
            "robustly_infeasible", "full_interval_inconsistent",
            "reading_sensitive", "full_interval_inconsistent",
        ]), "constant_positive_two_state_full_interval_inconsistent")


if __name__ == "__main__":
    unittest.main(verbosity=2)
```

- [ ] **Step 2: Run RED**

```bash
python3 -m unittest -v tests.test_radiator_two_state_math
python3 -O -m unittest -v tests.test_radiator_two_state_math
```

Expected: both commands fail because the math module does not exist.

- [ ] **Step 3: Implement deterministic coefficient and solver primitives**

Create `tests/radiator_two_state_math.py` with immutable records and direct two-variable algebra:

```python
from __future__ import annotations

from dataclasses import dataclass
import itertools
import math
from typing import Callable, Iterable

from tests import radiator_two_state_contract as contract

QFunction = Callable[[float, float, float], float]
ZERO_TOLERANCE = 1e-12


@dataclass(frozen=True)
class Coefficient:
    interval_index: int
    start_s: float
    end_s: float
    A_K: float
    B_K_s: float
    D_J: float


@dataclass(frozen=True)
class Solution:
    C_fluid_J_K: float
    UA_W_K: float
    sse_J2: float


@dataclass(frozen=True)
class ResidualRange:
    minimum_J: float
    maximum_J: float
    contains_zero: bool
    admissible_corner_count: int


@dataclass(frozen=True)
class IntervalAnalysis:
    coefficient: Coefficient
    residual_J: float
    relative_residual: float
    conditional_C_fluid_J_K: float | None
    corner_range: ResidualRange | None


@dataclass(frozen=True)
class CaseAnalysis:
    case: contract.Case
    case_enum: str
    nominal_sign_gate: dict[str, float | bool]
    favorable_sign_gate: dict[str, float | bool]
    unrestricted_solution: Solution
    nnls_solution: Solution
    equivalent_mass_kg: float | None
    all_intervals_locally_compatible: bool
    intervals: tuple[IntervalAnalysis, ...]


def cp_nak_J_kgK(temperature_K: float) -> float:
    return 1000 * (
        1.061 - 3.694e-4*temperature_K
        + 4.615e-8*temperature_K**2
        + 1.509e-10*temperature_K**3
    )


def h_nak_J_kg(temperature_K: float) -> float:
    return 1000 * (
        1.061*temperature_K
        - 3.694e-4*temperature_K**2/2
        + 4.615e-8*temperature_K**3/3
        + 1.509e-10*temperature_K**4/4
    )


def q_inlet_cp_W(tin_K: float, tout_K: float, m_dot_kg_s: float) -> float:
    return m_dot_kg_s * cp_nak_J_kgK(tin_K) * (tin_K-tout_K)


def q_integral_enthalpy_W(tin_K: float, tout_K: float, m_dot_kg_s: float) -> float:
    return m_dot_kg_s * (h_nak_J_kg(tin_K)-h_nak_J_kg(tout_K))


ENERGY_FUNCTIONS = {
    "inlet_cp": q_inlet_cp_W,
    "integral_enthalpy": q_integral_enthalpy_W,
}


def interval_coefficient(first, second, tin_K, m_dot_kg_s, q_function,
                         interval_index=0) -> Coefficient:
    dt = second.time_s-first.time_s
    if not math.isfinite(dt) or dt <= 0:
        raise ValueError("interval duration must be finite and positive")
    mean_first = 0.8*tin_K + 0.2*first.outlet_K
    mean_second = 0.8*tin_K + 0.2*second.outlet_K
    q_first = q_function(tin_K, first.outlet_K, m_dot_kg_s)
    q_second = q_function(tin_K, second.outlet_K, m_dot_kg_s)
    values = (
        mean_second-mean_first,
        dt*((mean_first-first.wall_K)+(mean_second-second.wall_K))/2,
        dt*(q_first+q_second)/2,
    )
    if not all(math.isfinite(value) for value in values):
        raise ValueError("interval coefficient is nonfinite")
    return Coefficient(interval_index, first.time_s, second.time_s, *values)


def residual_J(row: Coefficient, C_fluid_J_K: float, UA_W_K: float) -> float:
    return row.A_K*C_fluid_J_K + row.B_K_s*UA_W_K - row.D_J


def _solution(rows, C, UA) -> Solution:
    sse = sum(residual_J(row, C, UA)**2 for row in rows)
    return Solution(C, UA, sse)


def solve_unrestricted(rows: Iterable[Coefficient]) -> Solution:
    rows = tuple(rows)
    aa = sum(row.A_K**2 for row in rows)
    ab = sum(row.A_K*row.B_K_s for row in rows)
    bb = sum(row.B_K_s**2 for row in rows)
    ad = sum(row.A_K*row.D_J for row in rows)
    bd = sum(row.B_K_s*row.D_J for row in rows)
    determinant = aa*bb-ab*ab
    if not math.isfinite(determinant) or determinant <= 0:
        raise ValueError("rank-deficient interval system")
    C = (ad*bb-bd*ab)/determinant
    UA = (bd*aa-ad*ab)/determinant
    return _solution(rows, C, UA)


def solve_nnls(rows: Iterable[Coefficient]) -> Solution:
    rows = tuple(rows)
    candidates = [_solution(rows, 0.0, 0.0)]
    unrestricted = solve_unrestricted(rows)
    if unrestricted.C_fluid_J_K >= 0 and unrestricted.UA_W_K >= 0:
        candidates.append(unrestricted)
    aa = sum(row.A_K**2 for row in rows)
    bb = sum(row.B_K_s**2 for row in rows)
    candidates.append(_solution(rows, max(0.0, sum(row.A_K*row.D_J for row in rows)/aa), 0.0))
    candidates.append(_solution(rows, 0.0, max(0.0, sum(row.B_K_s*row.D_J for row in rows)/bb)))
    return min(candidates, key=lambda item: (
        item.sse_J2, item.C_fluid_J_K, item.UA_W_K
    ))
```

- [ ] **Step 4: Implement sign, corner, case, and aggregate classification**

Add the following behavior to the same module:

```python
def nominal_sign_gate(rows):
    rising_limits = [row.D_J/row.B_K_s for row in rows
                     if row.A_K > ZERO_TOLERANCE and row.B_K_s > 0]
    plateau_requirements = [row.D_J/row.B_K_s for row in rows
                            if abs(row.A_K) <= ZERO_TOLERANCE and row.B_K_s > 0]
    if not rising_limits or not plateau_requirements:
        raise ValueError("sign gate requires rising and plateau intervals")
    rising_upper = min(rising_limits)
    plateau_required = max(plateau_requirements)
    return {
        "rising_UA_upper_W_K": rising_upper,
        "plateau_UA_required_W_K": plateau_required,
        "conflict": plateau_required > rising_upper,
    }


def _shift(sample, outlet_delta, wall_delta, time_delta):
    return contract.Sample(
        sample.x_px, sample.wall_y_px, sample.outlet_y_px,
        sample.time_s+time_delta, sample.wall_K+wall_delta,
        sample.outlet_K+outlet_delta,
    )


def corner_residual_range(first, second, candidate, tin_K, m_dot_kg_s,
                          q_function, temperature_allowance_K,
                          time_allowance_s):
    residuals = []
    signs = (-1.0, 1.0)
    for to_a, tw_a, t_a, to_b, tw_b, t_b in itertools.product(signs, repeat=6):
        shifted_first = _shift(first, to_a*temperature_allowance_K,
                               tw_a*temperature_allowance_K,
                               t_a*time_allowance_s)
        shifted_second = _shift(second, to_b*temperature_allowance_K,
                                tw_b*temperature_allowance_K,
                                t_b*time_allowance_s)
        if shifted_second.time_s <= shifted_first.time_s:
            continue
        row = interval_coefficient(
            shifted_first, shifted_second, tin_K, m_dot_kg_s, q_function
        )
        residuals.append(residual_J(
            row, candidate.C_fluid_J_K, candidate.UA_W_K
        ))
    if not residuals:
        raise ValueError("no admissible ordered uncertainty corners")
    minimum, maximum = min(residuals), max(residuals)
    return ResidualRange(minimum, maximum,
                         minimum <= ZERO_TOLERANCE and maximum >= -ZERO_TOLERANCE,
                         len(residuals))


def favorable_sign_gate(samples, tin_K, m_dot_kg_s, q_function,
                        temperature_allowance_K):
    nominal = [interval_coefficient(a, b, tin_K, m_dot_kg_s, q_function, index)
               for index, (a, b) in enumerate(zip(samples, samples[1:]))]
    rising_indexes = [index for index, row in enumerate(nominal)
                      if row.A_K > ZERO_TOLERANCE]
    plateau_indexes = [index for index, row in enumerate(nominal)
                       if abs(row.A_K) <= ZERO_TOLERANCE]
    per_interval_ratio_ranges = {}
    for index, (first, second) in enumerate(zip(samples, samples[1:])):
        ratios = []
        for to_a, tw_a, to_b, tw_b in itertools.product((-1.0, 1.0), repeat=4):
            shifted_first = _shift(first, to_a*temperature_allowance_K,
                                   tw_a*temperature_allowance_K, 0.0)
            shifted_second = _shift(second, to_b*temperature_allowance_K,
                                    tw_b*temperature_allowance_K, 0.0)
            row = interval_coefficient(
                shifted_first, shifted_second, tin_K, m_dot_kg_s, q_function, index
            )
            if row.B_K_s > 0:
                ratios.append(row.D_J/row.B_K_s)
        if not ratios:
            raise ValueError("uncertainty sign gate has no positive B interval")
        per_interval_ratio_ranges[index] = (min(ratios), max(ratios))
    favorable_rising_upper = min(
        per_interval_ratio_ranges[index][1] for index in rising_indexes
    )
    favorable_plateau_required = max(
        per_interval_ratio_ranges[index][0] for index in plateau_indexes
    )
    return {
        "favorable_rising_UA_upper_W_K": favorable_rising_upper,
        "favorable_plateau_UA_required_W_K": favorable_plateau_required,
        "conflict": favorable_plateau_required > favorable_rising_upper,
    }


def aggregate_case_enums(case_enums):
    case_enums = tuple(case_enums)
    if len(case_enums) != 4:
        raise ValueError("exactly four fixed cases are required")
    if all(value == "robustly_infeasible" for value in case_enums):
        return "constant_positive_two_state_robustly_infeasible"
    if all(value in {"robustly_infeasible", "reading_sensitive"}
           for value in case_enums):
        return "constant_positive_two_state_nominally_infeasible_but_reading_sensitive"
    if any(value == "conditionally_feasible" for value in case_enums):
        return "constant_positive_two_state_conditionally_feasible"
    return "constant_positive_two_state_full_interval_inconsistent"
```

`analyze_case(case: contract.Case, samples: tuple[contract.Sample, ...]) -> CaseAnalysis` must compute all eleven adjacent intervals, nominal and favorable sign gates, unrestricted solution, analytic NNLS, per-interval residuals, conditional `C_fluid(UA)` for every nonzero `A`, and equivalent mass `C_fluid/cp_nak(TIN_K)` only when `C_fluid>0`. It enumerates corner residual ranges only when both unrestricted parameters are strictly positive, matching the specification's “positive candidate” condition. When either parameter is nonpositive, every `corner_range` is `None` and `all_intervals_locally_compatible` is false. It must assign:

```python
if nominal_gate["conflict"] and favorable_gate["conflict"]:
    case_enum = "robustly_infeasible"
elif nominal_gate["conflict"]:
    case_enum = "reading_sensitive"
elif (unrestricted.C_fluid_J_K > 0 and unrestricted.UA_W_K > 0
      and all(item.contains_zero for item in corner_ranges)):
    case_enum = "conditionally_feasible"
else:
    case_enum = "full_interval_inconsistent"
```

All relative residuals use `residual_J / max(abs(D_J), 1.0)` and are diagnostics only; they are not classification thresholds.

- [ ] **Step 5: Run GREEN and commit**

```bash
python3 -m unittest -v tests.test_radiator_two_state_math
python3 -O -m unittest -v tests.test_radiator_two_state_math
git add tests/radiator_two_state_math.py tests/test_radiator_two_state_math.py
git commit -m "实现散热器两状态积分可行性算法"
```

Expected: all analytic branches pass without external numerical libraries.

### Task 3: Build the one-shot atomic evidence runner

**Files:**
- Create: `tests/run_radiator_two_state_feasibility.py`
- Create: `tests/test_run_radiator_two_state_feasibility.py`
- Runtime only: `tmp/radiator_two_state_feasibility_20260902_A/**`

- [ ] **Step 1: Write failing end-to-end contract tests**

Create `tests/test_run_radiator_two_state_feasibility.py`:

```python
import csv
import json
from pathlib import Path
import tempfile
import unittest

from tests import radiator_two_state_contract as contract
from tests import run_radiator_two_state_feasibility as runner


class RadiatorTwoStateRunnerTests(unittest.TestCase):
    def test_fresh_run_writes_exact_four_case_bundle(self):
        with tempfile.TemporaryDirectory(dir=contract.ROOT / "tmp") as folder:
            run_dir = Path(folder) / "fresh"
            result = runner.run(run_dir)
            self.assertIn(result["result_enum"], runner.SCIENTIFIC_ENUMS)
            self.assertEqual(result["case_count"], 4)
            self.assertEqual(result["interval_count_per_case"], 11)
            for name in (
                "summary.json", "intervals.csv", "corner_ranges.csv",
                "source_hashes.json", "protected_before.json",
                "protected_after.json", "output_hashes.json", "report.md",
            ):
                self.assertTrue((run_dir / name).is_file(), name)
            self.assertEqual(
                json.loads((run_dir / "protected_before.json").read_text()),
                json.loads((run_dir / "protected_after.json").read_text()),
            )
            self.assertFalse(result["paper_reproduced"])
            self.assertFalse(result["author_parameter_identified"])
            self.assertFalse(result["formal_promotion"])

    def test_existing_run_directory_is_never_overwritten(self):
        with tempfile.TemporaryDirectory(dir=contract.ROOT / "tmp") as folder:
            run_dir = Path(folder) / "existing"
            run_dir.mkdir()
            marker = run_dir / "owner.txt"
            marker.write_text("preserve", encoding="utf-8")
            with self.assertRaises(FileExistsError):
                runner.run(run_dir)
            self.assertEqual(marker.read_text(encoding="utf-8"), "preserve")

    def test_contract_failure_has_no_scientific_coefficients(self):
        with tempfile.TemporaryDirectory(dir=contract.ROOT / "tmp") as folder:
            root = Path(folder)
            altered = root / "points.csv"
            altered.write_text("bad,data\n", encoding="utf-8")
            run_dir = root / "failure"
            result = runner.run(run_dir, points_path=altered)
            self.assertEqual(result["result_enum"], "evidence_contract_failure")
            self.assertFalse((run_dir / "intervals.csv").exists())
            self.assertTrue((run_dir / "contract_failure.json").is_file())

    def test_python_path_contains_no_slx_or_external_execution_api(self):
        combined = "\n".join((contract.ROOT / path).read_text(encoding="utf-8") for path in (
            "tests/radiator_two_state_contract.py",
            "tests/radiator_two_state_math.py",
            "tests/run_radiator_two_state_feasibility.py",
        ))
        for forbidden in (
            "load_system", "save_system", "sim(", "matlab.engine",
            "subprocess", "ZipFile", "writestr(", "wolfram",
        ):
            self.assertNotIn(forbidden, combined)


if __name__ == "__main__":
    unittest.main(verbosity=2)
```

- [ ] **Step 2: Run RED**

```bash
python3 -m unittest -v tests.test_run_radiator_two_state_feasibility
python3 -O -m unittest -v tests.test_run_radiator_two_state_feasibility
```

Expected: both commands fail because the runner does not exist.

- [ ] **Step 3: Implement the fresh-output and atomic-write boundary**

Create `tests/run_radiator_two_state_feasibility.py` with these write primitives and fixed enums:

```python
from __future__ import annotations

import argparse
import csv
from dataclasses import asdict
import hashlib
import json
import os
from pathlib import Path
import tempfile

from tests import radiator_two_state_contract as contract
from tests import radiator_two_state_math as model

SCIENTIFIC_ENUMS = {
    "constant_positive_two_state_robustly_infeasible",
    "constant_positive_two_state_nominally_infeasible_but_reading_sensitive",
    "constant_positive_two_state_conditionally_feasible",
    "constant_positive_two_state_full_interval_inconsistent",
}


def _atomic_text(path: Path, text: str) -> None:
    descriptor, temporary = tempfile.mkstemp(prefix=path.name+".", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise


def _atomic_json(path: Path, value) -> None:
    _atomic_text(path, json.dumps(value, indent=2, sort_keys=True)+"\n")


def _hash_outputs(run_dir: Path, names: tuple[str, ...]) -> dict[str, str]:
    return {
        name: hashlib.sha256((run_dir/name).read_bytes()).hexdigest()
        for name in names
    }
```

`run(run_dir, points_path=contract.POINTS_CSV)` must reject an existing path, create the directory once, take the protected snapshot before parsing, and catch only `EvidenceContractError` for the failure enum. For a valid contract it calls `model.analyze_case` exactly once for each member of `contract.CASES`, preserves case order, and writes:

- `summary.json`: schema `radiator_two_state_feasibility_v1`, overall enum, four case summaries, fixed constants, exact false flags, and no success boolean.
- `intervals.csv`: 44 rows, exact columns `case_id,interval_index,start_s,end_s,A_K,B_K_s,D_J,residual_J,relative_residual,conditional_C_fluid_J_K`.
- `corner_ranges.csv`: 44 rows, exact columns `case_id,interval_index,minimum_J,maximum_J,contains_zero,admissible_corner_count`; a case without a positive unrestricted candidate has blank extrema, `false`, and `0` rather than invented corner diagnostics.
- `source_hashes.json`: contract inputs plus the SHA-256 of the contract, math, and runner scripts.
- `protected_before.json` and `protected_after.json`: exact seven-file byte snapshots; inequality raises an exception and prevents a scientific report.
- `report.md`: identity table, four case enums, overall enum, evidence-grade wording, and the three false flags.
- `output_hashes.json`: hashes of every preceding output except itself.

Each `summary.json` case item has the exact keys
`case_id,flow_id,m_dot_kg_s,energy_path,case_enum,nominal_sign_gate,favorable_sign_gate,unrestricted_solution,nnls_solution,equivalent_mass_kg,all_intervals_locally_compatible`.
Both solution objects have the exact keys `C_fluid_J_K,UA_W_K,sse_J2`.
`equivalent_mass_kg` is JSON `null` unless the unrestricted heat capacity is strictly positive.

The CLI must be exactly:

```python
def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", type=Path, required=True)
    args = parser.parse_args()
    result = run(args.run_dir)
    print(json.dumps({
        "run_dir": str(args.run_dir),
        "result_enum": result["result_enum"],
        **contract.FALSE_FLAGS,
    }, sort_keys=True))
    return 0 if result["result_enum"] != "evidence_contract_failure" else 2


if __name__ == "__main__":
    raise SystemExit(main())
```

There is no loop over parameter values beyond the four immutable cases and no retry path.

- [ ] **Step 4: Run GREEN and commit**

```bash
python3 -m unittest -v tests.test_run_radiator_two_state_feasibility
python3 -O -m unittest -v tests.test_run_radiator_two_state_feasibility
git add tests/run_radiator_two_state_feasibility.py \
  tests/test_run_radiator_two_state_feasibility.py
git commit -m "构建散热器两状态离线证据输出"
```

Expected: all tests pass, temporary directories are self-contained, and protected-file hashes are equal.

### Task 4: Add an independent Decimal verifier

**Files:**
- Create: `tests/verify_radiator_two_state_feasibility.py`
- Create: `tests/test_verify_radiator_two_state_feasibility.py`

- [ ] **Step 1: Write failing verifier tests**

Create `tests/test_verify_radiator_two_state_feasibility.py`:

```python
import csv
import json
from pathlib import Path
import tempfile
import unittest

from tests import radiator_two_state_contract as contract
from tests import run_radiator_two_state_feasibility as runner
from tests import verify_radiator_two_state_feasibility as verifier


class RadiatorTwoStateVerifierTests(unittest.TestCase):
    def test_decimal_verifier_accepts_fresh_bundle(self):
        with tempfile.TemporaryDirectory(dir=contract.ROOT / "tmp") as folder:
            run_dir = Path(folder) / "run"
            runner.run(run_dir)
            result = verifier.verify(run_dir)
            self.assertEqual(result["schema"], "radiator_two_state_verification_v1")
            self.assertTrue(result["all_checks_passed"])
            self.assertEqual(result["verified_case_count"], 4)
            self.assertEqual(result["verified_interval_count"], 44)

    def test_verifier_rejects_changed_interval_arithmetic(self):
        with tempfile.TemporaryDirectory(dir=contract.ROOT / "tmp") as folder:
            run_dir = Path(folder) / "run"
            runner.run(run_dir)
            intervals = run_dir / "intervals.csv"
            with intervals.open(newline="", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
                fieldnames = tuple(rows[0])
            rows[0]["D_J"] = str(float(rows[0]["D_J"])+1.0)
            with intervals.open("w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(handle, fieldnames=fieldnames)
                writer.writeheader()
                writer.writerows(rows)
            with self.assertRaises(verifier.VerificationError):
                verifier.verify(run_dir)

    def test_verifier_rejects_changed_output_hash(self):
        with tempfile.TemporaryDirectory(dir=contract.ROOT / "tmp") as folder:
            run_dir = Path(folder) / "run"
            runner.run(run_dir)
            hashes = json.loads((run_dir / "output_hashes.json").read_text())
            first = next(iter(hashes))
            hashes[first] = "0" * 64
            (run_dir / "output_hashes.json").write_text(json.dumps(hashes)+"\n")
            with self.assertRaises(verifier.VerificationError):
                verifier.verify(run_dir)

    def test_publication_is_minimal_fresh_and_collision_safe(self):
        with tempfile.TemporaryDirectory(dir=contract.ROOT / "tmp") as folder:
            root = Path(folder)
            run_dir, publication = root / "run", root / "publication"
            runner.run(run_dir)
            verifier.verify(run_dir)
            verifier.publish(run_dir, publication)
            self.assertEqual({path.name for path in publication.iterdir()}, {
                "summary.json", "intervals.csv", "source_hashes.json",
                "verification.json", "manifest.json",
            })
            with self.assertRaises(FileExistsError):
                verifier.publish(run_dir, publication)


if __name__ == "__main__":
    unittest.main(verbosity=2)
```

- [ ] **Step 2: Run RED**

```bash
python3 -m unittest -v tests.test_verify_radiator_two_state_feasibility
python3 -O -m unittest -v tests.test_verify_radiator_two_state_feasibility
```

Expected: both commands fail because the verifier does not exist.

- [ ] **Step 3: Implement independent high-precision re-derivation**

Create `tests/verify_radiator_two_state_feasibility.py`. It must not import `radiator_two_state_math`; it independently parses the original point strings with `Decimal`, uses precision 50, and recomputes `T_bar`, `A`, `B`, `D`, the two-by-two determinant solution, and interval residuals:

```python
from __future__ import annotations

import csv
from decimal import Decimal, localcontext
import hashlib
import json
import math
from pathlib import Path

from tests import radiator_two_state_contract as contract


class VerificationError(RuntimeError):
    pass


def _require(condition, message):
    if not condition:
        raise VerificationError(message)


def _D(value) -> Decimal:
    return Decimal(str(value))


def cp_nak_D(T):
    return Decimal(1000) * (
        _D("1.061")-_D("3.694e-4")*T+_D("4.615e-8")*T*T
        +_D("1.509e-10")*T*T*T
    )


def h_nak_D(T):
    return Decimal(1000) * (
        _D("1.061")*T-_D("3.694e-4")*T*T/2
        +_D("4.615e-8")*T*T*T/3+_D("1.509e-10")*T*T*T*T/4
    )


def coefficient_D(first, second, m_dot, energy_path):
    tin = _D("609.58")
    dt = second["time_s"]-first["time_s"]
    mean_a = _D("0.8")*tin+_D("0.2")*first["outlet_K"]
    mean_b = _D("0.8")*tin+_D("0.2")*second["outlet_K"]
    if energy_path == "inlet_cp":
        qa = m_dot*cp_nak_D(tin)*(tin-first["outlet_K"])
        qb = m_dot*cp_nak_D(tin)*(tin-second["outlet_K"])
    elif energy_path == "integral_enthalpy":
        qa = m_dot*(h_nak_D(tin)-h_nak_D(first["outlet_K"]))
        qb = m_dot*(h_nak_D(tin)-h_nak_D(second["outlet_K"]))
    else:
        raise VerificationError(f"unknown energy path: {energy_path}")
    return (
        mean_b-mean_a,
        dt*((mean_a-first["wall_K"])+(mean_b-second["wall_K"]))/2,
        dt*(qa+qb)/2,
    )
```

`verify(run_dir)` must first verify `output_hashes.json`, source hashes, `protected_before == protected_after == snapshot_protected_files()`, exact CSV headers, exactly 44 rows in each table, unique `(case_id, interval_index)` keys, and the three false flags. For every fixed case it must independently recompute all eleven coefficient triples and compare each published float using:

```python
def close(decimal_value, published):
    return math.isclose(float(decimal_value), float(published),
                        rel_tol=2e-12, abs_tol=1e-7)
```

It then solves the Decimal normal equations inside `localcontext()` with `context.prec = 50`, checks the published unrestricted `C_fluid`, `UA`, SSE, every residual, and independently evaluates the analytic NNLS boundary candidates. It also re-enumerates all nominal/favorable sign ratios and, only for a strictly positive unrestricted candidate, all admissible ordered `±3 K, ±2 s` residual corners without calling the production math module. For a nonpositive candidate it verifies the published blank/false/zero corner records. From these independently derived values it recomputes each case enum and then the overall aggregation rule. On first success it atomically creates `verification.json` with schema, 4/44 counts, source/output hashes, `all_checks_passed=true`, the independently derived overall enum, and the three false flags. If that file already exists, it must require exact semantic equality with the newly recomputed object and perform no write. It must raise `VerificationError` before creating or changing evidence if any check fails.

`publish(run_dir, publication_dir)` must call `verify(run_dir)` first, reject an existing publication path, create the new directory, atomically copy only `summary.json`, `intervals.csv`, `source_hashes.json`, and `verification.json`, then atomically write `manifest.json`. The manifest records each copied relative path, recomputed SHA-256, byte count, source run-directory name, approved spec path/hash, actual overall enum, and all three false flags. If any write fails, it must leave the publication directory marked incomplete by the absence of `manifest.json`; it must never delete or overwrite user data.

The verifier CLI must be exactly:

```python
def main() -> int:
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--publish-dir", type=Path)
    args = parser.parse_args()
    result = verify(args.run_dir)
    if args.publish_dir is not None:
        publish(args.run_dir, args.publish_dir)
    print(json.dumps({
        "run_dir": str(args.run_dir),
        "result_enum": result["result_enum"],
        "all_checks_passed": result["all_checks_passed"],
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run GREEN and commit**

```bash
python3 -m unittest -v tests.test_verify_radiator_two_state_feasibility
python3 -O -m unittest -v tests.test_verify_radiator_two_state_feasibility
git add tests/verify_radiator_two_state_feasibility.py \
  tests/test_verify_radiator_two_state_feasibility.py
git commit -m "独立复核散热器两状态可行性算术"
```

Expected: genuine output passes; either arithmetic or hash tampering fails deterministically.

### Task 5: Execute once, publish verified evidence, and stop at the decision gate

**Files:**
- Create after successful verification: `data/provenance/steady53/fig5_18d/two_state_feasibility/summary.json`
- Create after successful verification: `data/provenance/steady53/fig5_18d/two_state_feasibility/intervals.csv`
- Create after successful verification: `data/provenance/steady53/fig5_18d/two_state_feasibility/source_hashes.json`
- Create after successful verification: `data/provenance/steady53/fig5_18d/two_state_feasibility/verification.json`
- Create after successful verification: `data/provenance/steady53/fig5_18d/two_state_feasibility/manifest.json`
- Runtime only: `tmp/radiator_two_state_feasibility_20260902_A/**`

- [ ] **Step 1: Run the complete pre-execution test suite**

```bash
python3 -m unittest -v \
  tests.test_radiator_two_state_contract \
  tests.test_radiator_two_state_math \
  tests.test_run_radiator_two_state_feasibility \
  tests.test_verify_radiator_two_state_feasibility
python3 -O -m unittest -v \
  tests.test_radiator_two_state_contract \
  tests.test_radiator_two_state_math \
  tests.test_run_radiator_two_state_feasibility \
  tests.test_verify_radiator_two_state_feasibility
```

Expected: every test passes twice; no run directory named `radiator_two_state_feasibility_20260902_A` is created by tests.

- [ ] **Step 2: Prove the formal-file baseline immediately before execution**

```bash
shasum -a 256 \
  final_steady_24a.slx HeXe_property_simulink.m Lithium_property_simulink.m \
  hexe_compressor_lookup.mat radiator_table.mat turbine_table1.mat turbine_table2.mat
git diff --name-only -- \
  final_steady_24a.slx '*.mat' \
  HeXe_property_simulink.m Lithium_property_simulink.m
```

Expected: hashes match the run's future `protected_before.json`; the Git diff command prints nothing.

- [ ] **Step 3: Execute the four fixed cases exactly once**

```bash
python3 tests/run_radiator_two_state_feasibility.py \
  --run-dir tmp/radiator_two_state_feasibility_20260902_A
```

Expected: exit 0, exactly one JSON status line, one of the four fixed scientific enums, four cases, 44 interval rows, 44 corner rows, and all false flags. If the directory already exists, stop and report the collision; do not delete it, choose another run ID, or execute the experiment again without a new explicit decision.

- [ ] **Step 4: Independently verify the completed bundle**

```bash
python3 tests/verify_radiator_two_state_feasibility.py \
  --run-dir tmp/radiator_two_state_feasibility_20260902_A
```

Expected: exit 0 and `verification.json` reports `all_checks_passed=true`, 4 cases, 44 intervals, matching source/output hashes, protected-file equality, and the same overall enum.

- [ ] **Step 5: Publish only the verified minimal evidence**

Use the verified publisher to create the new provenance directory and write only the five fixed artifacts:

```bash
python3 tests/verify_radiator_two_state_feasibility.py \
  --run-dir tmp/radiator_two_state_feasibility_20260902_A \
  --publish-dir data/provenance/steady53/fig5_18d/two_state_feasibility
```

Expected: publication succeeds only after a fresh full verification; `manifest.json` is the final file and names the actual enum while preserving all false flags. Parent evidence and earlier A1 records remain byte-identical.

- [ ] **Step 6: Run final verification**

```bash
python3 -m unittest -v \
  tests.test_radiator_two_state_contract \
  tests.test_radiator_two_state_math \
  tests.test_run_radiator_two_state_feasibility \
  tests.test_verify_radiator_two_state_feasibility
python3 -O -m unittest -v \
  tests.test_radiator_two_state_contract \
  tests.test_radiator_two_state_math \
  tests.test_run_radiator_two_state_feasibility \
  tests.test_verify_radiator_two_state_feasibility
python3 tests/verify_radiator_two_state_feasibility.py \
  --run-dir tmp/radiator_two_state_feasibility_20260902_A
git diff --check
git diff --name-only -- \
  final_steady_24a.slx '*.mat' \
  HeXe_property_simulink.m Lithium_property_simulink.m
```

Expected: tests and independent verification pass, whitespace check is clean, and formal-file diff is empty.

- [ ] **Step 7: Commit the truthful evidence and stop**

```bash
git add \
  tests/radiator_two_state_contract.py \
  tests/test_radiator_two_state_contract.py \
  tests/radiator_two_state_math.py \
  tests/test_radiator_two_state_math.py \
  tests/run_radiator_two_state_feasibility.py \
  tests/test_run_radiator_two_state_feasibility.py \
  tests/verify_radiator_two_state_feasibility.py \
  tests/test_verify_radiator_two_state_feasibility.py \
  data/provenance/steady53/fig5_18d/two_state_feasibility
git commit -m "完成散热器两状态离线可行性门"
```

Expected: the commit records the actual enum and evidence without committing `tmp/`. Stop here. A conditionally feasible result authorizes only a separate design discussion for a temporary two-state SLX; every other result redirects diagnosis exactly as specified and authorizes no formal model change.

## Completion checklist

- [ ] Input hashes, schema, units, point count, finite values, and increasing time pass.
- [ ] Exactly four fixed cases and eleven intervals per case are present.
- [ ] Nominal sign gate, favorable `±3 K` sign gate, unrestricted solution, analytic NNLS, interval residuals, conditional heat capacities, and corner ranges are all recorded.
- [ ] Time corners keep strict positive interval duration; no global-time-axis claim is made.
- [ ] Independent Decimal re-derivation passes normal Python and optimized Python.
- [ ] Output writes are fresh and atomic; no evidence is overwritten.
- [ ] Formal SLX/MAT/property files are byte-identical before and after.
- [ ] Exactly one fixed result enum and all three false flags are published.
- [ ] No MATLAB, SLX, 500 s simulation, 14000 s simulation, parameter scan, smoothing, fitting, or formal promotion occurs.
