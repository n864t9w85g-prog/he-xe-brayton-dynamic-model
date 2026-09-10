"""Independent arithmetic, saved-source identity, and protected-file audit."""
import csv
import hashlib
import json
import math
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
import zipfile


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main(path):
    repo = Path(__file__).resolve().parents[1]
    evidence = Path(path).resolve()
    data = json.loads(evidence.read_text())
    src = repo / "tmp/steady53_curves_20260828/source_f8bcd83"
    slx = src / "final_steady_24a.slx"
    assert sha(slx) == data["model_sha256"]
    assert sha(data["source_record"]) == data["source_record_sha256"]
    assert sha(src / "Lithium_property_simulink.m") == data["li_sha256"]
    assert sha(src / "HeXe_property_simulink.m") == data["hexe_sha256"]
    with zipfile.ZipFile(slx) as z:
        root = ET.fromstring(z.read("simulink/systems/system_1.xml"))
        top = ET.fromstring(z.read("simulink/systems/system_root.xml"))
    reactor = top.find("Block[@Name='reactor']")
    assert reactor.find("System").get("Ref") == "system_1"
    blocks = {b.get("SID"): b for b in root.findall("Block")}
    edges = set()
    for line in root.findall("Line"):
        origin = line.find("P[@Name='Src']").text
        edges.update((origin, p.text) for p in line.iter("P") if p.get("Name") == "Dst")
    # The algebraic outlet branch and fuel loss branch used in the audit.
    expected_edges = {
        ("207#out:1", "220#in:2"), ("206#out:1", "219#in:1"),
        ("219#out:1", "220#in:1"), ("220#out:1", "221#in:1"),
        ("222#out:1", "221#in:2"), ("221#out:1", "227#in:2"),
        ("217#out:1", "218#in:1"), ("218#out:1", "226#in:2"),
        ("223#out:1", "224#in:1"), ("225#out:1", "224#in:2"),
        ("224#out:1", "226#in:1"), ("226#out:1", "227#in:1"),
        ("227#out:1", "216#in:2"), ("214#out:1", "216#in:1"),
        ("216#out:1", "228#in:1"), ("175#out:1", "176#in:1"),
        ("177#out:1", "176#in:2"), ("176#out:1", "179#in:1"),
        ("178#out:1", "187#in:2"), ("180#out:1", "187#in:1"),
        ("187#out:1", "179#in:2"), ("179#out:1", "189#in:1"),
    }
    assert expected_edges <= edges
    for sid, field, value in [("218", "Gain", "2"), ("219", "Gain", "2"),
                              ("227", "Inputs", "*/"), ("224", "Inputs", "|+-"),
                              ("216", "Inputs", "|++"), ("179", "Inputs", "|+-")]:
        assert blocks[sid].find(f"P[@Name='{field}']").text == value
    c, s = data["constants"], data["saved_loop"]
    for sid, key in [("175", "inverse_C_fuel"), ("178", "gamma_f"), ("217", "hA1_W_K"),
                     ("222", "hA2_W_K"), ("207", "reactor_cp_J_kgK"), ("251", "Li_flow_kg_s")]:
        assert float(blocks[sid].find("P[@Name='Value']").text) == c[key]
    ti, to, tf = s["T_in_K"], s["T_out_K"], s["T_fuel_K"]
    m, cp, h = c["Li_flow_kg_s"], c["reactor_cp_J_kgK"], c["hA1_W_K"]
    outlet = ti + 2*h*(tf-ti)/(2*m*cp+h)
    h_fuel = c["gamma_f"] / c["inverse_C_fuel"]
    q_fuel = h_fuel * (tf-(ti+to)/2)
    q_outlet = m*cp*(to-ti)
    primitive = lambda t: 1000*(-104400/t-135.1*math.log(t)+4.180*t)
    q_ihx = m*.9615*(primitive(to)-primitive(ti))
    assert abs(outlet-to) < 1e-9
    for actual, key in [(q_fuel, "fuel_loss_W"), (q_outlet, "reactor_outlet_heat_W"),
                        (q_ihx, "IHX_property_enthalpy_W")]:
        assert abs(actual-s[key]) < 1e-6, key
    assert abs((q_outlet-q_fuel)+(q_ihx-q_outlet)-(q_ihx-q_fuel)) < 1e-8
    paths = data["table5_2_inferred_flows"]
    assert [p["valid"] for p in paths] == [True, False, False, True]
    for p in paths:
        if not p["valid"]:
            assert p["inferred_flow_kg_s"] is None and p["warning_id"]
    protected = list(csv.DictReader((repo / "tmp/tp80484fa0_602f_4386_89ed_ae9ca96b3359/protected_after.csv").open()))
    for item in protected:
        assert sha(item["paths"]) == item["hashes"], item["paths"]
    papers = [repo / name for name in [
        "空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf",
        "An Evaluation of Some Thermodynamic and Transport Properties of Solid and Liquid Lithium over the Temperature Range 200-1700 K.pdf",
        "Compilation of Thermophysical Properties of Liquid Lithium.pdf"]]
    report = {
        "audit_arithmetic_verified": True, "model_acceptance_passed": False,
        "protected_file_count": len(protected), "reactor_edges_checked": len(expected_edges),
        "valid_property_paths": 2, "invalid_property_paths_excluded": 2,
        "inputs_sha256": {str(p): sha(p) for p in [evidence, *papers, Path(__file__), repo / "tests/audit_steady53_energy_sources.m"]},
        "scope": "No new simulation. Independent audit verification is not a model pass."
    }
    out = evidence.parent / "independent_verification.json"
    assert not out.exists(), "Refuse to overwrite verification evidence"
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False)+"\n")
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main(sys.argv[1])
