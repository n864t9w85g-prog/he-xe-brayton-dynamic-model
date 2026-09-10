"""Build a read-only NaK/cooler/radiator provenance audit.

The audit reads the preserved f8bcd83 snapshot, already published property
evidence, the thesis scan, and Git-visible project records.  It never loads or
simulates an SLX and it never proposes replacement model parameters.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "tmp/steady53_curves_20260828/source_f8bcd83"
MODEL = SNAPSHOT / "final_steady_24a.slx"
MODEL_SHA256 = "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391"
HEXE_AUDIT = ROOT / "tmp/tp4e183961_9624_4b9f_ac65_941d915081f3/summary.json"
HEXE_AUDIT_SHA256 = "b466da117a0a87795b7d4d6669a944e3394c8db76bf526f6e91a153b9b63257d"
PROTECTED = ROOT / "tmp/tp7d213f64_7fad_4bfa_b722_0771b21d9640/protected_after.csv"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def nak_enthalpy_J_kg(temperature_K: float) -> float:
    """Analytic integral of the active NaK cp polynomial; zero is arbitrary."""
    t = temperature_K
    return 1000.0 * (
        1.061 * t
        - 3.694e-4 * t**2 / 2.0
        + 4.615e-8 * t**3 / 3.0
        + 1.509e-10 * t**4 / 4.0
    )


def scheme_b_radiator_tac_upper_bound_kg() -> int:
    """Mass left for radiator plus TAC after thesis-direct distinct items."""
    total = 8993
    figure_410_distinct_items = (1297, 1364)
    table_51_heat_exchangers = (325, 1089, 268)
    return total - sum(figure_410_distinct_items) - sum(table_51_heat_exchangers)


def _block_properties(archive: ZipFile, member: str) -> dict[str, dict[str, str]]:
    root = ET.fromstring(archive.read(member))
    return {
        block.attrib["Name"]: {
            prop.attrib["Name"]: prop.text or "" for prop in block.findall("P")
        }
        for block in root.findall("Block")
    }


def _verify_protected_files() -> int:
    rows = list(csv.DictReader(PROTECTED.open()))
    assert len(rows) == 34
    for row in rows:
        assert sha256(Path(row["paths"])) == row["hashes"], row["paths"]
    return len(rows)


def build_audit() -> dict:
    protected_count = _verify_protected_files()
    assert sha256(MODEL) == MODEL_SHA256
    assert sha256(HEXE_AUDIT) == HEXE_AUDIT_SHA256

    with ZipFile(MODEL) as archive:
        constants = _block_properties(archive, "simulink/systems/system_3154.xml")
        core = _block_properties(archive, "simulink/systems/system_3143.xml")
    active_slx = {
        "A_exchange_and_radiation_m2": float(constants["Constant2"]["Value"]),
        "M_rad_kg": float(constants["Constant3"]["Value"]),
        "h_W_m2_K": float(constants["Constant5"]["Value"]),
        "outlet_equation": core["Tho"]["Expr"],
        "wall_equation": core["Fcn1"]["Expr"],
    }
    assert active_slx["A_exchange_and_radiation_m2"] == 1113
    assert active_slx["M_rad_kg"] == 5744
    assert active_slx["h_W_m2_K"] == 9.755

    parameter_text = (SNAPSHOT / "sys_param_rad_fixed.m").read_text()
    active_script = {}
    for name, expected in (("epsilon", 0.9), ("Cp_rad", 900.0), ("theta", 5.67e-8)):
        match = re.search(rf"^{name}\s*=\s*([0-9.eE+-]+)\s*;", parameter_text, re.M)
        assert match
        active_script[name] = float(match.group(1))
        assert active_script[name] == expected

    boundary_file = SNAPSHOT / "tests/steady53/steady53_component_boundaries.m"
    boundary_text = boundary_file.read_text()
    assert "[360.10 6.95 663.63 0.676e6 11.97]" in boundary_text
    assert "Approved project coolant mass-flow boundary; not thesis direct" in boundary_text
    assert '[609.58 6.95]' in boundary_text

    experiment_log = SNAPSHOT / "docs/steady53_experiment_log.md"
    log_text = experiment_log.read_text()
    assert "A_rad = Q/(εσ(T⁴−T₀⁴))" in log_text and "1113 m²" in log_text
    assert "h_h=9.755 W/(m²K)" in log_text and "闭合反解" in log_text
    assert "59.13%×9714 kg" in log_text and "M_rad ≈ 5744 kg" in log_text

    hexe = json.loads(HEXE_AUDIT.read_text())
    cooler_hot = next(row for row in hexe["paths"] if row["name"] == "cooler_hot")
    assert cooler_hot["cpbar_valid"] is True
    assert abs(cooler_hot["inferred_flow_kg_s"] - 12.0709399541756) < 1e-12

    delta_h = nak_enthalpy_J_kg(609.58) - nak_enthalpy_J_kg(360.10)
    nak_power = 6.95 * delta_h
    nak_required_flow = 1_622_000.0 / delta_h
    mass_upper_bound = scheme_b_radiator_tac_upper_bound_kg()
    assert abs(delta_h - 227357.265107) < 1e-6
    assert mass_upper_bound == 4650 < 5744

    thesis = ROOT / "空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf"
    rendered = ROOT / "tmp/nak_triplet_provenance_20260829_yihN9W"
    inputs = [
        Path(__file__), MODEL, SNAPSHOT / "sys_param_rad_fixed.m", boundary_file,
        experiment_log, HEXE_AUDIT, PROTECTED, thesis,
        rendered / "thesis-088.png", rendered / "thesis-097.png",
        rendered / "thesis-101.png", rendered / "thesis-104.png",
        rendered / "ch2-048.png", rendered / "hxeq-041.png",
        rendered / "cycleeq-044.png",
    ]
    assert all(path.is_file() for path in inputs)

    return {
        "date": "2026-08-29",
        "scope": "Read-only provenance and arithmetic audit; no SLX load, simulation, or parameter change.",
        "paper_direct": {
            "table_5_2_pdf_page_104": {
                "NaK_inlet_K": 360.10,
                "NaK_outlet_K": 609.58,
                "cooler_or_condenser_power_kW": 1622.00,
            },
            "equation_2_46_pdf_page_44": "Q_CHX is written on both He-Xe hot side and NaK cold side.",
            "equations_5_15_5_16_pdf_page_101": "Radiator is a separate downstream NaK-to-space component.",
            "scheme_B_table_4_9_pdf_page_88": {"total_mass_kg_display": 8993},
            "scheme_B_figure_4_10_pdf_page_89": {"distinct_visible_component_masses_kg": [1297, 1364]},
            "table_5_1_pdf_page_98": {
                "IHX_mass_kg": 325,
                "recuperator_mass_kg": 1089,
                "cooler_mass_kg": 268,
            },
        },
        "current_snapshot": {"slx": active_slx, "script": active_script},
        "derived_not_source_values": {
            "active_NaK_delta_h_J_kg": delta_h,
            "power_at_6_95_kg_s_kW": nak_power / 1000.0,
            "gap_to_table_1622_kW": 1622.0 - nak_power / 1000.0,
            "NaK_flow_required_if_active_property_and_table_endpoints_are_fixed_kg_s": nak_required_flow,
            "HeXe_flow_required_by_published_offline_property_audit_kg_s": cooler_hot["inferred_flow_kg_s"],
            "scheme_B_mass_left_for_radiator_plus_TAC_at_most_kg": mass_upper_bound,
        },
        "provenance_classification": {
            "6.95_kg_s": "❓ approved project boundary; source record explicitly says not thesis direct",
            "1622_kW": "✅ thesis Table 5.2 component duty; alone does not identify NaK mass flow",
            "1113_m2": "❓ reverse-calculated from 1622 kW, epsilon=0.9 and an approximate Fig. 5.18 wall temperature",
            "9.755_W_m2_K": "❓ reverse-calculated to close Eq. 5.15 at Table 5.2 endpoints",
            "5744_kg": "❌ imported from a different optimization case; impossible for scheme B because radiator plus TAC remainder is <=4650 kg",
            "epsilon_0.9": "❌ inherited project constant; no thesis numeric source verified",
            "Cp_rad_900_J_kg_K": "❌ inherited project constant; no thesis material/property source verified",
        },
        "root_cause_implication": (
            "The current radiator parameter group is not an independent thesis-derived set: "
            "it mixes circular endpoint inversions, a different optimization case, and unverified inherited constants."
        ),
        "limitations": [
            "The audit does not recover the author's NaK mass flow or exact radiator mass.",
            "The 4650 kg result is an upper bound for radiator plus TAC, not a replacement radiator mass.",
            "The 7.134146 and 12.070940 kg/s values are conditional inversions, never thesis-direct values.",
            "No conclusion here validates Fig. 5.18 or the coupled 14000 s trajectory.",
        ],
        "protected_count": protected_count,
        "source_hashes": {str(path.relative_to(ROOT)): sha256(path) for path in inputs},
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
    destination = output / "nak_triplet_and_radiator_provenance.json"
    destination.write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n")
    assert build_audit() == json.loads(destination.read_text())
    print(json.dumps({
        "output": str(destination),
        "derived": audit["derived_not_source_values"],
        "classification": audit["provenance_classification"],
    }, ensure_ascii=False, indent=2))
    print("NAK_TRIPLET_AND_RADIATOR_PROVENANCE_AUDIT_PASS; NO_MODEL_LOAD; PROTECTED=34")


if __name__ == "__main__":
    main()
