"""Frozen, read-only evidence contract for the radiator two-state gate."""
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
POINTS_PROVENANCE = POINTS_CSV.with_name("provenance.json")

INPUT_HASHES = {
    "spec": "6bfab38ab3a3979b9ce1a38ef3cf162c464898c6ec1b4699a0dddb40c185898b",
    "paper": "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a",
    "points_csv": "6aed804bf1ac57832055dab34483bdcb25567a5b902e5b3c6b85cb7129e8849b",
    "points_provenance": "fe35a863731ff5394095f5d268a988cb45120a1382db9fd53bc0599e8f98e0cd",
}
_INPUT_PATHS = {
    "spec": SPEC, "paper": PAPER, "points_csv": POINTS_CSV,
    "points_provenance": POINTS_PROVENANCE,
}

EXPECTED_HEADER = ("x_px", "wall_y_px", "outlet_y_px", "time_s", "wall_K", "outlet_K")
TIN_K = 609.58
TEMPERATURE_ALLOWANCE_K = 3.0
TIME_ALLOWANCE_S = 2.0
FALSE_FLAGS = {
    "paper_reproduced": False,
    "author_parameter_identified": False,
    "formal_promotion": False,
}
PROTECTED_RELATIVE_PATHS = (
    "final_steady_24a.slx", "HeXe_property_simulink.m", "Lithium_property_simulink.m",
    "hexe_compressor_lookup.mat", "radiator_table.mat", "turbine_table1.mat", "turbine_table2.mat",
)


@dataclass(frozen=True)
class Sample:
    x_px: float; wall_y_px: float; outlet_y_px: float; time_s: float; wall_K: float; outlet_K: float


@dataclass(frozen=True)
class Case:
    case_id: str; flow_id: str; m_dot_kg_s: float; energy_path: str


@dataclass(frozen=True)
class Evidence:
    header: tuple[str, ...]; samples: tuple[Sample, ...]; source_hashes: dict[str, str]


class EvidenceContractError(RuntimeError):
    """Raised when frozen evidence or protected-file identity is violated."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise EvidenceContractError(message)


def sha256(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except (OSError, UnicodeError) as exc:
        raise EvidenceContractError(f"path={path}; unreadable: {exc}") from exc


def parse_points(path: Path, expected_sha256: str | None) -> tuple[Sample, ...]:
    path = Path(path)
    if expected_sha256 is not None:
        actual = sha256(path)
        _require(actual == expected_sha256, f"curve_sha256 expected={expected_sha256}; actual={actual}")
    try:
        with path.open(newline="", encoding="utf-8") as handle:
            reader = csv.reader(handle)
            header = tuple(next(reader))
            rows = list(reader)
    except (OSError, UnicodeError, csv.Error, StopIteration) as exc:
        raise EvidenceContractError(f"path={path}; csv unreadable: {exc}") from exc
    _require(header == EXPECTED_HEADER, f"header expected={EXPECTED_HEADER}; actual={header}")
    _require(len(rows) == 12, f"rows expected=12; actual={len(rows)}")
    samples = []
    try:
        for row_number, row in enumerate(rows, start=2):
            _require(len(row) == len(EXPECTED_HEADER), f"row={row_number}; columns malformed")
            values = tuple(float(value) for value in row)
            _require(all(math.isfinite(value) for value in values), f"row={row_number}; nonfinite value")
            samples.append(Sample(*values))
    except (TypeError, ValueError) as exc:
        raise EvidenceContractError(f"row numeric value malformed: {exc}") from exc
    _require(all(a.time_s < b.time_s for a, b in zip(samples, samples[1:])), "times must be strictly increasing")
    return tuple(samples)


def verify_input_contract(points_path: Path = POINTS_CSV) -> Evidence:
    source_hashes = {}
    for key, expected in INPUT_HASHES.items():
        path = POINTS_CSV if key == "points_csv" else _INPUT_PATHS[key]
        if key == "points_csv":
            path = Path(points_path)
        _require(path.is_file(), f"input path missing: {path}")
        actual = sha256(path)
        _require(actual == expected, f"input_sha256 key={key}; expected={expected}; actual={actual}")
        source_hashes[key] = actual
    samples = parse_points(points_path, INPUT_HASHES["points_csv"])
    return Evidence(EXPECTED_HEADER, samples, source_hashes)


CASES = (
    Case("project_flow__inlet_cp", "project_flow", 6.95, "inlet_cp"),
    Case("project_flow__integral_enthalpy", "project_flow", 6.95, "integral_enthalpy"),
    Case("energy_closure_flow__inlet_cp", "energy_closure_flow", 7.134146337, "inlet_cp"),
    Case("energy_closure_flow__integral_enthalpy", "energy_closure_flow", 7.134146337, "integral_enthalpy"),
)


def snapshot_protected_files() -> dict[str, str]:
    snapshot = {}
    for relative in PROTECTED_RELATIVE_PATHS:
        path = ROOT / relative
        _require(path.is_file(), f"protected path missing: {relative}")
        snapshot[relative] = sha256(path)
    return snapshot
