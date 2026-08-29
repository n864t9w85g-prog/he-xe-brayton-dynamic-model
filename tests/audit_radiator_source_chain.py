"""Verify the published/missing radiator source chain without loading an SLX."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROVENANCE = ROOT / "data/provenance/radiator_source/juhasz"
PROTECTED = ROOT / "tmp/tp7d213f64_7fad_4bfa_b722_0771b21d9640/protected_after.csv"
EXPECTED_HASHES = {
    ROOT / "sources/NASA-TM-2007-215003-Juhasz-2007.pdf":
        "2f1a8b19be7deea95a43e6d30468e234e48e9955eed1dc5005b0efa3119fd732",
    ROOT / "sources/NASA-TM-2008-215420-Juhasz-2008.pdf":
        "eb332a4e13d75406c47f72d698f11e10708d1f230041aecdda591a86fae7e10f",
    ROOT / "空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf":
        "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def table_i_specific_mass() -> dict[str, dict[str, list[float]]]:
    return {
        "one_sided": {
            "fin_density_1.45_g_cc": [4.22, 3.14, 2.65, 2.38],
            "fin_density_1.00_g_cc": [3.46, 2.50, 2.07, 1.83],
        },
        "two_sided": {
            "fin_density_1.45_g_cc": [2.11, 1.57, 1.32, 1.19],
            "fin_density_1.00_g_cc": [1.73, 1.25, 1.04, 0.92],
        },
    }


def verify_protected() -> int:
    with PROTECTED.open() as handle:
        rows = list(csv.DictReader(handle))
    assert len(rows) == 34
    for row in rows:
        assert sha256(Path(row["paths"])) == row["hashes"], row["paths"]
    return len(rows)


def build_audit() -> dict:
    for path, expected in EXPECTED_HASHES.items():
        assert path.is_file()
        assert sha256(path) == expected

    checksum_lines = (PROVENANCE / "SHA256SUMS.txt").read_text().splitlines()
    for expected in EXPECTED_HASHES.values():
        assert any(line.startswith(expected + "  ") for line in checksum_lines)

    source = (PROVENANCE / "source.md").read_text()
    for required in (
        "NASA/TM-2007-215003", "NASA/TM-2008-215420",
        "M_rad=kappa*A_rad", "m_dot_NaK", "T300", "P95 WG", "K1100", "APG",
        "NaK 流量仍不可识别", "不修改正式 SLX",
    ):
        assert required in source

    with (PROVENANCE / "published_missing_matrix.csv").open() as handle:
        matrix = list(csv.DictReader(handle))
    direct = {row["quantity"] for row in matrix if row["status"] == "thesis_direct"}
    missing = {row["quantity"] for row in matrix if row["status"] == "author_implementation_missing"}
    assert {"NaK_composition", "NaK_loop_pressure", "cooler_duty"} <= direct
    assert {
        "NaK_mass_flow", "radiator_emissivity", "radiator_specific_mass_branch",
        "radiator_radiating_area", "radiator_internal_exchange_area",
        "radiator_heat_transfer_coefficient", "radiator_wall_heat_capacity",
        "pump_flow_pressure_drop_design", "optimization_source_code",
    } <= missing

    branches = table_i_specific_mass()
    assert branches["one_sided"]["fin_density_1.45_g_cc"][0] == 4.22
    assert branches["two_sided"]["fin_density_1.45_g_cc"][0] == 2.11
    assert branches["two_sided"]["fin_density_1.00_g_cc"][-1] == 0.92

    return {
        "date": "2026-08-29",
        "scope": "Read-only document/hash audit; no SLX load, simulation, or model change.",
        "source_hashes": {str(path.relative_to(ROOT)): sha256(path) for path in EXPECTED_HASHES},
        "nasa_2008_table_I_material_order": ["T300", "P95 WG", "K1100", "APG"],
        "nasa_2008_table_I_specific_mass_kg_m2": branches,
        "published_quantity_count": len(direct),
        "author_implementation_missing_count": len(missing),
        "missing_quantities": sorted(missing),
        "protected_count": verify_protected(),
        "conclusion": (
            "The thesis and cited sources define equations and candidate technology branches, "
            "but do not uniquely identify the scheme-B radiator/NaK numerical implementation."
        ),
        "no_model_load_or_simulation": True,
        "no_formal_model_change": True,
        "model_acceptance_passed": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    assert output.is_relative_to(ROOT / "tmp")
    output.mkdir(parents=True, exist_ok=False)
    audit = build_audit()
    destination = output / "radiator_source_chain.json"
    destination.write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n")
    assert json.loads(destination.read_text()) == build_audit()
    print(json.dumps({"output": str(destination), "missing": audit["missing_quantities"]},
                     ensure_ascii=False, indent=2))
    print("RADIATOR_SOURCE_CHAIN_AUDIT_PASS; NO_MODEL_LOAD; PROTECTED=34")


if __name__ == "__main__":
    main()
