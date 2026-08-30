"""Immutable source and parameter contract for radiator A1 exploration."""
from __future__ import annotations

import csv
from dataclasses import dataclass
import hashlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASELINE = (
    ROOT
    / "tmp/steady53_curves_20260828/source_f8bcd83/final_steady_24a.slx"
)
BASELINE_SHA256 = (
    "0532e9ddf2deb7ef5e40cc1b8e619c44"
    "ea7afd36b00d807d118f4cd812a5a391"
)
PROTECTED = (
    ROOT
    / "tmp/tp7d213f64_7fad_4bfa_b722_0771b21d9640/protected_after.csv"
)
PROTECTED_SHA256 = (
    "496e4bbbbe5786bbb21b63d3c320dcfd"
    "f3c741935736624ed2912ab81afc9a0a"
)

SOURCE_HASHES = {
    "sources/NASA-TM-2007-215003-Juhasz-2007.pdf": (
        "2f1a8b19be7deea95a43e6d30468e234"
        "e48e9955eed1dc5005b0efa3119fd732"
    ),
    "sources/NASA-TM-2008-215420-Juhasz-2008.pdf": (
        "eb332a4e13d75406c47f72d698f11e10"
        "708d1f230041aecdda591a86fae7e10f"
    ),
    "空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf": (
        "983bfc23712221f30202a47875cbe34c"
        "9559edf79b9c332aa20931b6075e4e7a"
    ),
}

CURVE_EVIDENCE_HASHES = {
    "tmp/steady53_curves_20260828/radiator_scan_points.csv": (
        "6aed804bf1ac57832055dab34483bdcb2"
        "5567a5b902e5b3c6b85cb7129e8849b"
    ),
    "tmp/steady53_curves_20260828/radiator_scan_provenance.json": (
        "fe35a863731ff5394095f5d268a988cb"
        "45120a1382db9fd53bc0599e8f98e0cd"
    ),
}


def sha256(path: Path) -> str:
    """Return the hexadecimal SHA256 digest of *path*."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


class A1ContractError(RuntimeError):
    """Raised when an immutable A1 source or parameter gate is violated."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise A1ContractError(message)


@dataclass(frozen=True)
class Branch:
    branch_id: str
    kappa_kg_m2: float
    maturity: str


@dataclass(frozen=True)
class NamedValue:
    case_id: str
    value: float
    unit: str
    evidence: str


@dataclass(frozen=True)
class Role:
    role_id: str
    flow_kg_s: float
    epsilon: float
    sink_K: float
    h_W_m2K: float
    cp_proxy_J_kgK: float

    def as_tuple(self) -> tuple[float, float, float, float, float]:
        return (
            self.flow_kg_s,
            self.epsilon,
            self.sink_K,
            self.h_W_m2K,
            self.cp_proxy_J_kgK,
        )


BRANCHES = (
    Branch("T300_fd1p45_one", 4.22, "tested"),
    Branch("T300_fd1p45_two", 2.11, "tested"),
    Branch("P95_WG_fd1p45_two", 1.57, "built_not_tested"),
    Branch("APG_fd1p00_two", 0.92, "projected"),
)

FLOWS = (
    NamedValue("project_flow", 6.95, "kg/s", "project_boundary"),
    NamedValue(
        "energy_closure_flow", 7.134146337, "kg/s", "conditional"
    ),
)

EMISSIVITIES = (
    NamedValue(
        "NASA_surface_0p85", 0.85, "1", "other_system_anchor"
    ),
    NamedValue(
        "NASA_surface_0p90", 0.90, "1", "other_system_anchor"
    ),
)

SINKS = (
    NamedValue("NASA_120_example", 200.0, "K", "other_system_anchor"),
    NamedValue("legacy_project", 225.0, "K", "project_boundary"),
)

H_ANCHORS = (
    NamedValue(
        "legacy_inverse", 9.755, "W/(m^2*K)", "conditional_inverse"
    ),
    NamedValue(
        "NASA_120_low", 200.0, "W/(m^2*K)", "other_system_anchor"
    ),
    NamedValue(
        "NASA_120_high", 600.0, "W/(m^2*K)", "other_system_anchor"
    ),
)

ROLES = (
    Role("legacy_transfer", 6.95, 0.90, 225.0, 9.755, 900.0),
    Role(
        "conservative_source",
        7.134146337,
        0.85,
        225.0,
        200.0,
        1000.0,
    ),
    Role("optimistic_source", 6.95, 0.90, 200.0, 600.0, 777.0),
)

PATCH_BLOCKS = {
    "Constant": "Value",
    "rediator/Tho": "replace_with_integral_enthalpy_function",
    "rediator/T_env": "Value",
    "rediator/Subsystem/Constant": "Value",
    "rediator/Subsystem/Constant2": "Value",
    "rediator/Subsystem/Constant3": "Value",
    "rediator/Subsystem/Constant4": "Value",
    "rediator/Subsystem/Constant5": "Value",
}


def _verify_hashes(
    expected_hashes: dict[str, str],
    category: str = "source",
) -> dict[str, str]:
    actual_hashes = {}
    for relative_path, expected_hash in expected_hashes.items():
        path = Path(relative_path)
        if not path.is_absolute():
            path = ROOT / path
        _require(
            path.is_file(),
            f"category={category}; path={path}; "
            "expected=file_exists; actual=missing",
        )
        actual_hash = sha256(path)
        _require(
            actual_hash == expected_hash,
            f"category={category}; path={path}; "
            f"expected={expected_hash}; actual={actual_hash}",
        )
        actual_hashes[relative_path] = actual_hash
    return actual_hashes


def verify_source_contract() -> dict[str, object]:
    """Verify every immutable A1 input and return its provenance summary."""
    _require(
        BASELINE.is_file(),
        f"category=baseline; path={BASELINE}; "
        "expected=file_exists; actual=missing",
    )
    baseline_sha256 = sha256(BASELINE)
    _require(
        baseline_sha256 == BASELINE_SHA256,
        f"category=baseline; path={BASELINE}; "
        f"expected={BASELINE_SHA256}; actual={baseline_sha256}",
    )

    source_hashes = _verify_hashes(SOURCE_HASHES, "source")
    curve_evidence_hashes = _verify_hashes(
        CURVE_EVIDENCE_HASHES,
        "curve_evidence",
    )

    _require(
        PROTECTED.is_file(),
        f"category=protected_manifest; path={PROTECTED}; "
        "expected=file_exists; actual=missing",
    )
    protected_manifest_sha256 = sha256(PROTECTED)
    _require(
        protected_manifest_sha256 == PROTECTED_SHA256,
        f"category=protected_manifest; path={PROTECTED}; "
        f"expected={PROTECTED_SHA256}; actual={protected_manifest_sha256}",
    )
    try:
        with PROTECTED.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            fieldnames = reader.fieldnames
            protected_rows = list(reader)
    except (OSError, UnicodeError, csv.Error) as exc:
        raise A1ContractError(
            f"category=protected_manifest_csv; path={PROTECTED}; "
            f"expected=readable_csv; actual={type(exc).__name__}: {exc}"
        ) from exc
    _require(
        fieldnames == ["paths", "hashes"],
        f"category=protected_manifest_header; path={PROTECTED}; "
        f"expected=['paths', 'hashes']; actual={fieldnames}",
    )
    _require(
        len(protected_rows) == 34,
        f"category=protected_manifest_rows; path={PROTECTED}; "
        f"expected=34; actual={len(protected_rows)}",
    )

    protected_paths = []
    for row_number, row in enumerate(protected_rows, start=2):
        path_text = row["paths"]
        expected_hash = row["hashes"]
        _require(
            isinstance(path_text, str) and bool(path_text),
            f"category=protected_manifest_path; path={PROTECTED}; "
            f"row={row_number}; expected=nonempty_string; actual={path_text!r}",
        )
        _require(
            isinstance(expected_hash, str)
            and len(expected_hash) == 64
            and all(character in "0123456789abcdef" for character in expected_hash),
            f"category=protected_manifest_hash_format; path={path_text}; "
            "expected=64_lowercase_hex; "
            f"actual={expected_hash!r}",
        )
        protected_paths.append(path_text)
    unique_path_count = len(set(protected_paths))
    _require(
        unique_path_count == 34,
        f"category=protected_manifest_paths; path={PROTECTED}; "
        f"expected=34_unique; actual={unique_path_count}_unique",
    )

    for row in protected_rows:
        protected_path = Path(row["paths"])
        _require(
            protected_path.is_absolute(),
            f"category=protected_path; path={protected_path}; "
            "expected=absolute; actual=relative",
        )
        _require(
            protected_path.is_file(),
            f"category=protected_file; path={protected_path}; "
            "expected=file_exists; actual=missing",
        )
        protected_actual_hash = sha256(protected_path)
        _require(
            protected_actual_hash == row["hashes"],
            f"category=protected_file; path={protected_path}; "
            f"expected={row['hashes']}; actual={protected_actual_hash}",
        )

    return {
        "baseline_path": str(BASELINE.relative_to(ROOT)),
        "baseline_sha256": baseline_sha256,
        "source_hashes": source_hashes,
        "curve_evidence_hashes": curve_evidence_hashes,
        "protected_manifest": str(PROTECTED.relative_to(ROOT)),
        "protected_count": len(protected_rows),
        "paper_reproduced": False,
        "formal_promotion": False,
    }
