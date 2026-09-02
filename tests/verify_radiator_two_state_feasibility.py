#!/usr/bin/env python3
"""Independently verify one radiator two-state evidence bundle (stdlib only)."""
from __future__ import annotations

import argparse
import csv
import ctypes
from decimal import Decimal, localcontext
import errno
import hashlib
import itertools
import json
import math
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile
from typing import Any, Iterable, Mapping

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tests import radiator_two_state_contract as contract


ROOT = Path(__file__).resolve().parents[1]
SCIENTIFIC_ENUMS = {
    "constant_positive_two_state_robustly_infeasible",
    "constant_positive_two_state_nominally_infeasible_but_reading_sensitive",
    "constant_positive_two_state_conditionally_feasible",
    "constant_positive_two_state_full_interval_inconsistent",
}
CASE_ENUMS = {"robustly_infeasible", "reading_sensitive", "conditionally_feasible", "full_interval_inconsistent"}
RUN_FILES = {"summary.json", "intervals.csv", "corner_ranges.csv", "source_hashes.json", "protected_before.json", "protected_after.json", "report.md", "output_hashes.json"}
HASHED_OUTPUTS = RUN_FILES - {"output_hashes.json"}
INTERVAL_HEADERS = ("case_id", "interval_index", "start_s", "end_s", "A_K", "B_K_s", "D_J", "residual_J", "relative_residual", "conditional_C_fluid_J_K")
CORNER_HEADERS = ("case_id", "interval_index", "minimum_J", "maximum_J", "contains_zero", "admissible_corner_count")
ZERO = Decimal("1e-12")
DEC_TIN = Decimal(str(contract.TIN_K))


class VerificationError(RuntimeError):
    """Raised when a bundle is not complete, immutable, and independently reproducible."""


def _fail(message: str) -> None:
    raise VerificationError(message)


def _sha(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as exc:
        _fail(f"unreadable path: {path}: {exc}")
        raise AssertionError("unreachable")


def _hex(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(ch in "0123456789abcdef" for ch in value)


def _json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"), parse_constant=lambda x: (_fail(f"nonfinite JSON: {x}")))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        _fail(f"invalid JSON {path.name}: {exc}")


def _finite_number(value: Any, label: str) -> float:
    if isinstance(value, bool):
        _fail(f"{label} must be finite number")
    try:
        result = float(value)
    except (TypeError, ValueError):
        _fail(f"{label} must be finite number")
    if not math.isfinite(result):
        _fail(f"{label} must be finite number")
    return result


def _finite_json_number(value: Any, label: str) -> float:
    if type(value) not in (int, float) or not math.isfinite(float(value)):
        _fail(f"{label} must be a finite JSON number")
    return float(value)


def _close(observed: Any, expected: Decimal | float, label: str) -> None:
    actual = _finite_number(observed, label)
    if not math.isclose(actual, float(expected), rel_tol=2e-12, abs_tol=1e-7):
        _fail(f"arithmetic mismatch {label}: expected={float(expected)!r}; actual={actual!r}")


def _close_json(observed: Any, expected: Decimal | float, label: str) -> None:
    actual = _finite_json_number(observed, label)
    if not math.isclose(actual, float(expected), rel_tol=2e-12, abs_tol=1e-7):
        _fail(f"arithmetic mismatch {label}: expected={float(expected)!r}; actual={actual!r}")


def _d(value: str) -> Decimal:
    try:
        result = Decimal(value)
    except Exception as exc:
        _fail(f"bad Decimal field: {value!r}: {exc}")
    if not result.is_finite():
        _fail(f"nonfinite Decimal field: {value!r}")
    return result


def _cp(t: Decimal) -> Decimal:
    return Decimal(1000) * (Decimal("1.061") - Decimal("3.694e-4") * t + Decimal("4.615e-8") * t**2 + Decimal("1.509e-10") * t**3)


def _h(t: Decimal) -> Decimal:
    return Decimal(1000) * (Decimal("1.061") * t - Decimal("3.694e-4") * t**2 / 2 + Decimal("4.615e-8") * t**3 / 3 + Decimal("1.509e-10") * t**4 / 4)


def _q(path: str, tout: Decimal, flow: Decimal) -> Decimal:
    if path == "inlet_cp":
        return flow * _cp(DEC_TIN) * (DEC_TIN - tout)
    if path == "integral_enthalpy":
        return flow * (_h(DEC_TIN) - _h(tout))
    _fail(f"unknown energy path: {path}")
    raise AssertionError("unreachable")


def _coefficient(first: tuple[Decimal, Decimal, Decimal], second: tuple[Decimal, Decimal, Decimal], flow: Decimal, path: str) -> tuple[Decimal, Decimal, Decimal]:
    time1, wall1, out1 = first
    time2, wall2, out2 = second
    dt = time2 - time1
    if dt <= 0:
        _fail("nonpositive interval time")
    mean1, mean2 = Decimal("0.8") * DEC_TIN + Decimal("0.2") * out1, Decimal("0.8") * DEC_TIN + Decimal("0.2") * out2
    return mean2 - mean1, dt * ((mean1 - wall1) + (mean2 - wall2)) / 2, dt * (_q(path, out1, flow) + _q(path, out2, flow)) / 2


def _sse(rows: Iterable[tuple[Decimal, Decimal, Decimal]], c: Decimal, ua: Decimal) -> Decimal:
    return sum(((a * c + b * ua - d) ** 2 for a, b, d in rows), Decimal(0))


def _solve(rows: list[tuple[Decimal, Decimal, Decimal]]) -> tuple[Decimal, Decimal, Decimal]:
    aa = sum((a * a for a, _, _ in rows), Decimal(0)); ab = sum((a * b for a, b, _ in rows), Decimal(0)); bb = sum((b * b for _, b, _ in rows), Decimal(0))
    ad = sum((a * d for a, _, d in rows), Decimal(0)); bd = sum((b * d for _, b, d in rows), Decimal(0))
    determinant = aa * bb - ab * ab
    if determinant == 0:
        _fail("rank-deficient normal equations")
    c, ua = (ad * bb - ab * bd) / determinant, (aa * bd - ab * ad) / determinant
    return c, ua, _sse(rows, c, ua)


def _rank_ok(rows: list[tuple[Decimal, Decimal, Decimal]]) -> bool:
    first, second = [float(a) for a, _, _ in rows], [float(b) for _, b, _ in rows]
    scale1, scale2 = max(map(abs, first)), max(map(abs, second))
    if scale1 == 0 or scale2 == 0: return False
    a, b = [x / scale1 for x in first], [x / scale2 for x in second]
    r11 = math.hypot(*a); q1 = [x / r11 for x in a]; r12 = math.fsum(x*y for x, y in zip(q1,b))
    residual = [x-r12*y for x,y in zip(b,q1)]; correction = math.fsum(x*y for x,y in zip(q1,residual))
    r22 = math.hypot(*(x-correction*y for x,y in zip(residual,q1)))
    return r22 > math.ulp(1.0) * max(len(rows), 2) * max(r11, math.hypot(*b), 1.0)


def _nnls(rows: list[tuple[Decimal, Decimal, Decimal]], unrestricted: tuple[Decimal, Decimal, Decimal]) -> tuple[Decimal, Decimal, Decimal]:
    choices = [(Decimal(0), Decimal(0))]
    for column in (0, 1):
        denom = sum((r[column] * r[column] for r in rows), Decimal(0))
        if denom:
            value = max(Decimal(0), sum((r[column] * r[2] for r in rows), Decimal(0)) / denom)
            choices.append((value, Decimal(0)) if column == 0 else (Decimal(0), value))
    c, ua, _ = unrestricted
    if c >= 0 and ua >= 0: choices.append((c, ua))
    return min(((c, ua, _sse(rows, c, ua)) for c, ua in choices), key=lambda x: (x[2], x[0], x[1]))


def _gate(rows: list[tuple[Decimal, Decimal, Decimal]]) -> dict[str, Any]:
    rising = [d/b for a,b,d in rows if a > ZERO and b > 0]
    plateaus = [d/b for a,b,d in rows if abs(a) <= ZERO and b != 0]
    platform = any(abs(a) <= ZERO and b == 0 and d != 0 for a,b,d in rows)
    if not rising or not plateaus: _fail("missing rising or plateau sign-gate rows")
    upper, required = min(rising), max(plateaus)
    consistent = all(math.isclose(float(v), float(plateaus[0]), rel_tol=1e-12, abs_tol=0.0) for v in plateaus[1:])
    conflict = not consistent or upper <= 0 or required <= 0 or required >= upper
    return {"rising_UA_upper_W_K": upper, "plateau_UA_required_W_K": required, "plateau_consistent": consistent, "strict_positive_ratio_conflict": conflict, "platform_equation_inconsistent": platform, "conflict": conflict or platform}


def _favorable(samples: list[tuple[Decimal, Decimal, Decimal]], flow: Decimal, path: str) -> dict[str, Any]:
    nominal = [_coefficient(a,b,flow,path) for a,b in zip(samples, samples[1:])]
    rising = [i for i, r in enumerate(nominal) if r[0] > ZERO]; plateau = [i for i,r in enumerate(nominal) if abs(r[0]) <= ZERO]
    ranges: dict[int, tuple[Decimal, Decimal]] = {}; preserved = True
    delta = Decimal(str(contract.TEMPERATURE_ALLOWANCE_K))
    for i,(one,two) in enumerate(zip(samples,samples[1:])):
        ratios=[]
        for signs in itertools.product((-1,1), repeat=4):
            oa,wa,ob,wb=signs
            x=(one[0],one[1]+wa*delta,one[2]+oa*delta); y=(two[0],two[1]+wb*delta,two[2]+ob*delta)
            a,b,d=_coefficient(x,y,flow,path)
            if i in rising and not (a > ZERO and b > 0): preserved=False
            if i in plateau and not (abs(a)<=ZERO and b>0): preserved=False
            if b > 0: ratios.append(d/b)
        ranges[i]=(min(ratios),max(ratios))
    upper=min(ranges[i][1] for i in rising); required=max(ranges[i][0] for i in plateau)
    # Each plateau supplied to this gate is an extreme range, matching the production criterion.
    values=[ranges[i][0] for i in plateau]
    consistent=all(math.isclose(float(v),float(values[0]),rel_tol=1e-12,abs_tol=0.0) for v in values[1:])
    strict=not consistent or upper<=0 or required<=0 or required>=upper
    return {"favorable_rising_UA_upper_W_K":upper,"favorable_plateau_UA_required_W_K":required,"plateau_consistent":consistent,"strict_positive_ratio_conflict":strict,"sign_class_preserved":preserved,"conflict":preserved and strict}


def _corner(first: tuple[Decimal,Decimal,Decimal], second: tuple[Decimal,Decimal,Decimal], flow: Decimal, path: str, c: Decimal, ua: Decimal) -> tuple[Decimal,Decimal,bool,int]:
    td, dd = Decimal(str(contract.TIME_ALLOWANCE_S)), Decimal(str(contract.TEMPERATURE_ALLOWANCE_K)); values=[]
    for signs in itertools.product((-1,1), repeat=6):
        oa,wa,ta,ob,wb,tb=signs
        one=(first[0]+ta*td,first[1]+wa*dd,first[2]+oa*dd); two=(second[0]+tb*td,second[1]+wb*dd,second[2]+ob*dd)
        if two[0] > one[0]:
            a,b,d=_coefficient(one,two,flow,path); values.append(a*c+b*ua-d)
    return min(values), max(values), min(values)<=ZERO and max(values)>=-ZERO, len(values)


def _aggregate(enums: list[str]) -> str:
    if all(x == "robustly_infeasible" for x in enums): return "constant_positive_two_state_robustly_infeasible"
    if all(x in {"robustly_infeasible","reading_sensitive"} for x in enums): return "constant_positive_two_state_nominally_infeasible_but_reading_sensitive"
    if any(x == "conditionally_feasible" for x in enums): return "constant_positive_two_state_conditionally_feasible"
    return "constant_positive_two_state_full_interval_inconsistent"


def _case_enum(nominal: Mapping[str,Any], favorable: Mapping[str,Any], c: Decimal, ua: Decimal, corners: list[tuple[Decimal,Decimal,bool,int]]) -> tuple[str,bool]:
    local = c > 0 and ua > 0 and all(item[2] for item in corners)
    if nominal["conflict"] and favorable["conflict"]: return "robustly_infeasible", local
    if nominal["conflict"]: return "reading_sensitive", local
    return ("conditionally_feasible" if local else "full_interval_inconsistent"), local


def _read_points() -> list[tuple[Decimal,Decimal,Decimal]]:
    try:
        with contract.POINTS_CSV.open(newline="", encoding="utf-8") as handle: rows=list(csv.reader(handle))
    except OSError as exc: _fail(f"cannot read frozen points: {exc}")
    if tuple(rows[0]) != contract.EXPECTED_HEADER or len(rows) != 13: _fail("frozen point CSV schema mismatch")
    return [(_d(r[3]), _d(r[4]), _d(r[5])) for r in rows[1:]]


def _require_run_files(run: Path) -> None:
    if not run.is_dir(): _fail("run_dir is not a directory")
    if (run / "contract_failure.json").exists(): _fail("contract failure bundle is not scientific evidence")
    names={p.name for p in run.iterdir()}
    if names != RUN_FILES and names != RUN_FILES | {"verification.json"}: _fail(f"unexpected scientific file set: {sorted(names)}")
    for name in names:
        try:
            mode = os.stat(run / name, follow_symlinks=False).st_mode
        except OSError as exc:
            _fail(f"bundle entry unreadable: {name}: {exc}")
        if not stat.S_ISREG(mode): _fail(f"bundle entry must be a regular non-symlink file: {name}")


def _require_regular_entry(path: Path, label: str) -> None:
    try:
        mode = os.stat(path, follow_symlinks=False).st_mode
    except OSError as exc:
        _fail(f"{label} unreadable: {exc}")
    if not stat.S_ISREG(mode): _fail(f"{label} must be a regular non-symlink file")


def _load_hashes(run: Path) -> dict[str,str]:
    value=_json(run/"output_hashes.json")
    if not isinstance(value,dict) or set(value)!=HASHED_OUTPUTS or not all(_hex(x) for x in value.values()): _fail("invalid output_hashes schema")
    for name,digest in value.items():
        if _sha(run/name)!=digest: _fail(f"output hash mismatch: {name}")
    return value


def _source_hashes() -> dict[str,str]:
    paths=(contract.SPEC,contract.PAPER,contract.POINTS_CSV,contract.POINTS_PROVENANCE,ROOT/"tests/radiator_two_state_contract.py",ROOT/"tests/radiator_two_state_math.py",ROOT/"tests/run_radiator_two_state_feasibility.py")
    return {p.relative_to(ROOT).as_posix(): _sha(p) for p in paths}


def _verify_sources(run: Path) -> dict[str,str]:
    actual=_source_hashes(); supplied=_json(run/"source_hashes.json")
    if supplied != actual or set(supplied)!=set(actual) or not all(_hex(v) for v in supplied.values()): _fail("source hash mismatch")
    frozen={"spec":contract.SPEC,"paper":contract.PAPER,"points_csv":contract.POINTS_CSV,"points_provenance":contract.POINTS_PROVENANCE}
    for key,path in frozen.items():
        if actual[path.relative_to(ROOT).as_posix()] != contract.INPUT_HASHES[key]: _fail(f"frozen input hash mismatch: {key}")
    return actual


def _verify_protected(run: Path) -> dict[str,str]:
    before,after=_json(run/"protected_before.json"),_json(run/"protected_after.json")
    now=contract.snapshot_protected_files()
    if before != after or before != now or set(before)!=set(contract.PROTECTED_RELATIVE_PATHS): _fail("protected hashes changed")
    return now


def _verify_report(run: Path, sources: Mapping[str, str]) -> None:
    try:
        text = (run / "report.md").read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        _fail(f"report unreadable: {exc}")
    required = ("verified_unchanged", "受保护文件在本次运行前后字节完全一致", "不构成获批基线身份认定", *(f"`{key}=false`" for key in contract.FALSE_FLAGS))
    if any(token not in text for token in required):
        _fail("report wording/false flags mismatch")
    for relative, digest in sources.items():
        if relative not in text or digest not in text:
            _fail("report source identity mismatch")


def _csv(run: Path, name: str, headers: tuple[str,...]) -> list[dict[str,str]]:
    try:
        with (run/name).open(newline="",encoding="utf-8") as h:
            reader=csv.DictReader(h); rows=list(reader)
            if tuple(reader.fieldnames or ()) != headers: _fail(f"bad {name} headers")
    except (OSError, UnicodeError, csv.Error) as exc: _fail(f"bad {name}: {exc}")
    if len(rows)!=44 or any(set(r)!=set(headers) for r in rows): _fail(f"bad {name} row count/schema")
    return rows


def _compare_gate(observed: Any, expected: Mapping[str,Any], label: str) -> None:
    if not isinstance(observed,dict) or set(observed)!=set(expected): _fail(f"{label} schema mismatch")
    for key,value in expected.items():
        if isinstance(value,bool):
            if observed[key] is not value: _fail(f"{label}.{key} mismatch")
        else: _close_json(observed[key],value,f"{label}.{key}")


def _compare_solution(observed: Any, expected: tuple[Decimal,Decimal,Decimal], label: str) -> None:
    if not isinstance(observed,dict) or set(observed)!={"C_fluid_J_K","UA_W_K","sse_J2"}: _fail(f"{label} schema mismatch")
    for key,value in zip(("C_fluid_J_K","UA_W_K","sse_J2"), expected): _close_json(observed[key],value,f"{label}.{key}")


def _verify_science(run: Path) -> tuple[str,dict[str,Any]]:
    summary=_json(run/"summary.json")
    required={"schema","result_enum","case_count","interval_count_per_case","Tin_K","temperature_allowance_K","time_allowance_s","cases",*contract.FALSE_FLAGS}
    if not isinstance(summary,dict) or set(summary)!=required or summary["schema"]!="radiator_two_state_feasibility_v1": _fail("summary schema mismatch")
    if type(summary["case_count"]) is not int or type(summary["interval_count_per_case"]) is not int or summary["case_count"]!=4 or summary["interval_count_per_case"]!=11: _fail("summary count mismatch")
    for key,value in (("Tin_K",contract.TIN_K),("temperature_allowance_K",contract.TEMPERATURE_ALLOWANCE_K),("time_allowance_s",contract.TIME_ALLOWANCE_S)): _close_json(summary[key],value,key)
    if summary["result_enum"] not in SCIENTIFIC_ENUMS or any(summary[k] is not False for k in contract.FALSE_FLAGS): _fail("summary enum/flags mismatch")
    intervals,corners=_csv(run,"intervals.csv",INTERVAL_HEADERS),_csv(run,"corner_ranges.csv",CORNER_HEADERS)
    points=_read_points(); analyses=[]; cursor=0
    if not isinstance(summary["cases"], list): _fail("cases must be a JSON list")
    cases=list(summary["cases"])
    if len(cases)!=4: _fail("case list mismatch")
    for case,defined in zip(cases,contract.CASES):
        expected_keys={"case_id","flow_id","m_dot_kg_s","energy_path","case_enum","nominal_sign_gate","favorable_sign_gate","unrestricted_solution","nnls_solution","equivalent_mass_kg","all_intervals_locally_compatible"}
        if not isinstance(case,dict) or set(case)!=expected_keys: _fail("case schema mismatch")
        if case["case_id"]!=defined.case_id or case["flow_id"]!=defined.flow_id or case["energy_path"]!=defined.energy_path: _fail("case identity/order mismatch")
        _close_json(case["m_dot_kg_s"],defined.m_dot_kg_s,"m_dot")
        flow=Decimal(str(defined.m_dot_kg_s)); rows=[_coefficient(a,b,flow,defined.energy_path) for a,b in zip(points,points[1:])]
        if not _rank_ok(rows): _fail("normalised rank below ULP policy")
        unrestricted=_solve(rows); nnls=_nnls(rows,unrestricted); nominal=_gate(rows); favorable=_favorable(points,flow,defined.energy_path)
        _compare_gate(case["nominal_sign_gate"],nominal,"nominal gate"); _compare_gate(case["favorable_sign_gate"],favorable,"favorable gate")
        _compare_solution(case["unrestricted_solution"],unrestricted,"unrestricted solution"); _compare_solution(case["nnls_solution"],nnls,"NNLS solution")
        positive=unrestricted[0]>0 and unrestricted[1]>0; expected_corners=[] if not positive else [_corner(a,b,flow,defined.energy_path,unrestricted[0],unrestricted[1]) for a,b in zip(points,points[1:])]
        enum,local=_case_enum(nominal,favorable,unrestricted[0],unrestricted[1],expected_corners)
        if case["case_enum"]!=enum or case["all_intervals_locally_compatible"] is not local: _fail("case enum/local compatibility mismatch")
        if positive:
            _close_json(case["equivalent_mass_kg"],unrestricted[0]/_cp(DEC_TIN),"equivalent mass")
        elif case["equivalent_mass_kg"] is not None: _fail("nonpositive solution must have null equivalent mass")
        for index,(row,first,second) in enumerate(zip(rows,points,points[1:])):
            interval,corn=intervals[cursor],corners[cursor]; cursor+=1
            if interval["case_id"]!=defined.case_id or corn["case_id"]!=defined.case_id or interval["interval_index"]!=str(index) or corn["interval_index"]!=str(index): _fail("CSV case/order mismatch")
            for key,value in zip(("start_s","end_s","A_K","B_K_s","D_J"),(first[0],second[0],*row)):
                _close(interval[key],value,f"interval.{key}")
            residual=row[0]*unrestricted[0]+row[1]*unrestricted[1]-row[2]
            _close(interval["residual_J"],residual,"interval residual"); _close(interval["relative_residual"],residual/max(abs(row[2]),Decimal(1)),"interval relative residual")
            if abs(row[0])>ZERO: _close(interval["conditional_C_fluid_J_K"],(row[2]-row[1]*unrestricted[1])/row[0],"conditional capacity")
            elif interval["conditional_C_fluid_J_K"]!="": _fail("plateau conditional capacity must be blank")
            if not positive:
                if tuple(corn[k] for k in ("minimum_J","maximum_J","contains_zero","admissible_corner_count")) != ("","","false","0"): _fail("nonpositive corner blank convention")
            else:
                minimum,maximum,contains,count=expected_corners[index]
                _close(corn["minimum_J"],minimum,"corner minimum"); _close(corn["maximum_J"],maximum,"corner maximum")
                if corn["contains_zero"] != str(contains).lower() or corn["admissible_corner_count"] != str(count): _fail("corner flags mismatch")
        analyses.append(enum)
    result=_aggregate(analyses)
    if summary["result_enum"]!=result: _fail("overall result enum mismatch")
    return result,summary


def _atomic_json_exclusive(path: Path, value: Mapping[str,Any]) -> None:
    content=json.dumps(value,ensure_ascii=False,sort_keys=True,indent=2,allow_nan=False)+"\n"
    descriptor, name = tempfile.mkstemp(prefix=f".{path.name}.",dir=path.parent)
    os.close(descriptor)
    staging=Path(name)
    try:
        staging.write_text(content,encoding="utf-8")
        if path.exists() or path.is_symlink():
            if path.is_symlink() or not stat.S_ISREG(os.stat(path, follow_symlinks=False).st_mode):
                _fail("existing verification evidence must be a regular non-symlink file")
            old=_json(path)
            if old != value: _fail("existing verification evidence differs")
            return
        # A hard-link is an exclusive no-replace primitive on the same filesystem.
        try: os.link(staging,path)
        except FileExistsError:
            _require_regular_entry(path, "existing verification evidence")
            if _json(path)!=value: _fail("existing verification evidence differs")
    finally:
        try: staging.unlink()
        except FileNotFoundError: pass


def _verification_result(run: Path, result: str, outputs: dict[str,str], sources: dict[str,str], protected: dict[str,str]) -> dict[str,Any]:
    return {"schema":"radiator_two_state_verification_v1","all_checks_passed":True,"verified_case_count":4,"verified_interval_count":44,"result_enum":result,"run_output_hashes":outputs,"source_hashes":sources,"protected_hashes":protected,"verifier_sha256":_sha(Path(__file__).resolve()),**dict(contract.FALSE_FLAGS)}


def verify(run_dir: Path | str) -> dict[str,Any]:
    run=Path(run_dir).expanduser().resolve(); _require_run_files(run); outputs=_load_hashes(run); sources=_verify_sources(run); protected=_verify_protected(run); _verify_report(run, sources)
    with localcontext() as context:
        context.prec = 50
        result,_=_verify_science(run)
    # Re-check after all parsing/arithmetic to fail closed on a concurrent output change.
    if _load_hashes(run)!=outputs: _fail("run outputs changed during verification")
    if _verify_sources(run) != sources: _fail("source files changed during verification")
    if _verify_protected(run) != protected: _fail("protected files changed during verification")
    _require_run_files(run)
    result_payload=_verification_result(run,result,outputs,sources,protected)
    verification=run/"verification.json"
    before=verification.stat().st_mtime_ns if verification.exists() else None
    _atomic_json_exclusive(verification,result_payload)
    if before is not None and verification.stat().st_mtime_ns != before: _fail("existing verification evidence was modified")
    return result_payload


def _publish_exclusive(staging: Path, target: Path) -> None:
    if sys.platform != "darwin": _fail("exclusive directory publication is unsupported on this platform")
    if target.exists(): raise FileExistsError(target)
    libc=ctypes.CDLL(None,use_errno=True); func=libc.renamex_np; func.argtypes=(ctypes.c_char_p,ctypes.c_char_p,ctypes.c_uint); func.restype=ctypes.c_int
    if func(os.fsencode(staging),os.fsencode(target),0x00000004)==0: return
    number=ctypes.get_errno()
    if number in {errno.EEXIST,errno.ENOTEMPTY}: raise FileExistsError(target)
    raise OSError(number,"exclusive directory publication failed",target)


def publish(run_dir: Path | str, publication_dir: Path | str) -> dict[str,Any]:
    run=Path(run_dir).expanduser().resolve(); target=Path(publication_dir).expanduser().resolve()
    result=verify(run)
    if target.exists(): raise FileExistsError(target)
    target.parent.mkdir(parents=True,exist_ok=True); staging=Path(tempfile.mkdtemp(prefix=f".{target.name}.staging.",dir=target.parent))
    try:
        artifact_names=("summary.json","intervals.csv","source_hashes.json","verification.json")
        for name in artifact_names: shutil.copyfile(run/name,staging/name)
        if _sha(staging / "summary.json") != result["run_output_hashes"]["summary.json"] or _sha(staging / "intervals.csv") != result["run_output_hashes"]["intervals.csv"] or _sha(staging / "source_hashes.json") != result["run_output_hashes"]["source_hashes.json"] or _json(staging / "verification.json") != result:
            _fail("publication copy no longer matches verified identity")
        artifacts=[{"relative_filename":name,"sha256":_sha(staging/name),"byte_count":(staging/name).stat().st_size} for name in artifact_names]
        manifest={"schema":"radiator_two_state_publication_v1","source_run_directory_basename":run.name,"approved_spec":{"relative_path":contract.SPEC.relative_to(ROOT).as_posix(),"sha256":contract.INPUT_HASHES["spec"]},"result_enum":result["result_enum"],**dict(contract.FALSE_FLAGS),"artifacts":artifacts}
        (staging/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,sort_keys=True,indent=2,allow_nan=False)+"\n",encoding="utf-8")
        if _json(staging / "manifest.json") != manifest: _fail("publication manifest mismatch")
        if {p.name for p in staging.iterdir()} != set(artifact_names)|{"manifest.json"}: _fail("publication staging file set mismatch")
        for item in artifacts:
            if _sha(staging/item["relative_filename"]) != item["sha256"] or (staging/item["relative_filename"]).stat().st_size != item["byte_count"]: _fail("publication staging hash mismatch")
        # Identity immediately before the external durable transition.
        _require_run_files(run)
        if _load_hashes(run) != result["run_output_hashes"] or _verify_sources(run) != result["source_hashes"] or _verify_protected(run) != result["protected_hashes"] or _json(run / "verification.json") != result:
            _fail("run changed after verification before publication")
        _publish_exclusive(staging,target); staging=None
        return manifest
    except BaseException:
        if staging is not None: shutil.rmtree(staging,ignore_errors=True)
        raise


def main(argv: list[str] | None = None) -> int:
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument("--run-dir",required=True,type=Path); parser.add_argument("--publish-dir",type=Path)
    args=parser.parse_args(argv); result=verify(args.run_dir); published=False
    if args.publish_dir is not None: publish(args.run_dir,args.publish_dir); published=True
    print(json.dumps({"run_dir":str(args.run_dir.expanduser().resolve()),"result_enum":result["result_enum"],"all_checks_passed":True,"published":published},ensure_ascii=False,sort_keys=True,separators=(",",":"),allow_nan=False))
    return 0


if __name__ == "__main__": raise SystemExit(main())
