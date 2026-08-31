#!/usr/bin/env python3
"""Atomically add the compact Task 6 initialization audit to Figure 5.19."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import stat
import tempfile
from contextlib import contextmanager
from pathlib import Path

try:
    from tests import analyze_fig519_baseline as baseline
    from tests import digitize_fig519 as paper
except ModuleNotFoundError:  # pragma: no cover - CLI path
    import analyze_fig519_baseline as baseline
    import digitize_fig519 as paper


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data/provenance/steady53/fig5_19"
SOURCE = ROOT / "tmp/fig519_initialization_20260831_A1/initialization_audit.json"
AUDIT_NAME = baseline.INITIALIZATION_AUDIT_NAME
TARGETS = (AUDIT_NAME, "signal_contract.json", "manifest.csv")
TRANSACTION_VERSION = 1


def _hash(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _safe_existing_file(path: Path) -> Path:
    raw = Path(path)
    if not raw.is_absolute() or ".." in raw.parts:
        raise RuntimeError("source path must be absolute and lexically contained")
    tmp = (ROOT / "tmp").resolve()
    probe = Path(raw.anchor)
    for part in raw.parts[1:]:
        probe /= part
        if os.path.lexists(probe):
            mode = os.lstat(probe).st_mode
            if stat.S_ISLNK(mode):
                raise RuntimeError("symlinked source paths are forbidden")
    resolved = raw.resolve(strict=True)
    if tmp not in resolved.parents or resolved.is_symlink() or not resolved.is_file():
        raise RuntimeError("source audit must be a regular file below repository tmp/")
    return resolved


def _load_source(source: Path) -> tuple[bytes, dict[str, object]]:
    source = _safe_existing_file(source)
    payload = source.read_bytes()
    try:
        audit = json.loads(payload)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("source initialization audit is not valid JSON") from exc
    baseline._validate_initialization_audit(audit)
    raw = audit.get("raw_reference")
    if not isinstance(raw, dict):
        raise RuntimeError("initialization audit raw reference is missing")
    relative = raw.get("repository_relative_path")
    absolute = raw.get("absolute_path")
    if not isinstance(relative, str) or not isinstance(absolute, str):
        raise RuntimeError("initialization audit raw reference paths are missing")
    if Path(relative).is_absolute() or ".." in Path(relative).parts:
        raise RuntimeError("raw reference relative path escapes the repository")
    relative_path = _safe_existing_file(ROOT / relative)
    absolute_path = _safe_existing_file(Path(absolute))
    if relative_path != absolute_path or absolute_path.parent != source.parent:
        raise RuntimeError("raw reference paths do not identify the source audit directory")
    raw_payload = absolute_path.read_bytes()
    if raw.get("bytes") != len(raw_payload) or raw.get("sha256") != _hash(raw_payload):
        raise RuntimeError("raw reference hash or byte count mismatch")
    return payload, audit


def _json_bytes(value: dict[str, object]) -> bytes:
    return baseline._json_bytes(value)


def _planned(source: Path, output: Path) -> dict[str, bytes]:
    audit_payload, audit = _load_source(source)
    paper.verify_paper_layer(output)
    baseline_bytes = {name: (output / paper.BASELINE_LAYER_DIR / name).read_bytes()
                      for name in paper.BASELINE_LAYER_NAMES}
    if {name: _hash(payload) for name, payload in baseline_bytes.items()} != baseline.SOURCE_HASHES:
        raise RuntimeError("durable Task 5 baseline layer is not hash-contracted")
    metrics, _ = baseline.analyze(output / paper.BASELINE_LAYER_DIR, output / "paper_points.csv")
    contract_payload = _json_bytes(baseline.contract_from_initialization(audit))
    entries = {name: (output / name).read_bytes() for name in paper.ARTIFACT_NAMES}
    entries.update({f"{paper.BASELINE_LAYER_DIR}/{name}": payload
                    for name, payload in baseline_bytes.items()})
    entries["baseline_metrics.json"] = _json_bytes(metrics)
    entries["signal_contract.json"] = contract_payload
    entries[AUDIT_NAME] = audit_payload
    manifest_payload = paper.manifest_bytes(entries, baseline._roles())
    return {AUDIT_NAME: audit_payload, "signal_contract.json": contract_payload,
            "manifest.csv": manifest_payload}


def transaction_dir(output: Path) -> Path:
    return output.parent / (output.name + ".task6-transaction")


def _publication_boundary(point: str) -> None:
    del point


def _write_exclusive(path: Path, payload: bytes) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        offset = 0
        while offset < len(payload):
            offset += os.write(fd, payload[offset:])
        os.fsync(fd)
    finally:
        os.close(fd)


def _fsync_directory(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _check(path: Path, payload: bytes, label: str) -> None:
    if path.is_symlink() or not path.is_file() or path.read_bytes() != payload:
        raise RuntimeError(f"Task 6 publication conflict: {label}")


def _record(payloads: dict[str, bytes]) -> bytes:
    return _json_bytes({"version": TRANSACTION_VERSION, "state": "prepared", "targets": [
        {"path": name, "bytes": len(payloads[name]), "sha256": _hash(payloads[name])}
        for name in TARGETS]})


def _task5_predecessors(output: Path) -> tuple[bytes, bytes]:
    metrics, contract = baseline.analyze(output / paper.BASELINE_LAYER_DIR, output / "paper_points.csv")
    old_contract = _json_bytes(contract)
    baseline_bytes = {name: (output / paper.BASELINE_LAYER_DIR / name).read_bytes()
                      for name in paper.BASELINE_LAYER_NAMES}
    entries = {name: (output / name).read_bytes() for name in paper.ARTIFACT_NAMES}
    entries.update({f"{paper.BASELINE_LAYER_DIR}/{name}": payload
                    for name, payload in baseline_bytes.items()})
    entries["baseline_metrics.json"] = _json_bytes(metrics)
    entries["signal_contract.json"] = old_contract
    return old_contract, paper.manifest_bytes(entries, baseline._roles())


def _target_state(output: Path, payloads: dict[str, bytes]) -> dict[str, str]:
    old_contract, old_manifest = _task5_predecessors(output)
    states: dict[str, str] = {}
    for name in TARGETS:
        target = output / name
        if not os.path.lexists(target):
            if name != AUDIT_NAME:
                raise RuntimeError(f"Task 6 predecessor is missing: {name}")
            states[name] = "missing"
            continue
        if target.is_symlink() or not target.is_file():
            raise RuntimeError(f"Task 6 target is unsafe: {name}")
        current = target.read_bytes()
        if current == payloads[name]:
            states[name] = "expected"
        elif name == "signal_contract.json" and current == old_contract:
            states[name] = "predecessor"
        elif name == "manifest.csv" and current == old_manifest:
            states[name] = "predecessor"
        else:
            raise RuntimeError(f"Task 6 target has an unregistered predecessor: {name}")
    return states


def _validate_transaction(txn: Path, payloads: dict[str, bytes], output: Path) -> Path:
    if txn.is_symlink() or not txn.is_dir():
        raise RuntimeError("Task 6 transaction directory is unsafe")
    mode = txn.stat().st_mode
    if txn.stat().st_uid != os.geteuid() or mode & 0o077:
        raise RuntimeError("Task 6 transaction ownership is unsafe")
    if {entry.name for entry in txn.iterdir()} != {"record.json", "payload"}:
        raise RuntimeError("Task 6 transaction has unexpected entries")
    _check(txn / "record.json", _record(payloads), "transaction record")
    root = txn / "payload"
    if root.is_symlink() or not root.is_dir():
        raise RuntimeError("Task 6 transaction payload is unsafe")
    unexpected = {entry.name for entry in root.iterdir()} - set(TARGETS)
    if unexpected:
        raise RuntimeError("Task 6 transaction has unexpected payloads")
    states = _target_state(output, payloads)
    for name in TARGETS:
        staged = root / name
        if os.path.lexists(staged):
            _check(staged, payloads[name], f"staged {name}")
        elif states[name] != "expected":
            raise RuntimeError(f"Task 6 transaction lost pending payload: {name}")
    return root


def _birth(txn: Path, payloads: dict[str, bytes], output: Path) -> None:
    init = Path(tempfile.mkdtemp(prefix=txn.name.replace("transaction", "init") + "-", dir=txn.parent))
    os.chmod(init, 0o700)
    _write_exclusive(init / "record.json", _record(payloads))
    payload_root = init / "payload"
    os.mkdir(payload_root, 0o700)
    for name in TARGETS:
        _publication_boundary(f"{name}-stage-before")
        _write_exclusive(payload_root / name, payloads[name])
        _publication_boundary(f"{name}-stage-after")
    _validate_transaction(init, payloads, output)
    _fsync_directory(payload_root); _fsync_directory(init)
    _publication_boundary("canonical-rename-before")
    if os.path.lexists(txn):
        raise RuntimeError("Task 6 canonical transaction appeared concurrently")
    os.rename(init, txn)
    _fsync_directory(txn.parent)
    _publication_boundary("canonical-rename-after")


@contextmanager
def _lock(output: Path):
    fd = os.open(output, os.O_RDONLY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def _commit(output: Path, txn: Path, payloads: dict[str, bytes]) -> None:
    root = _validate_transaction(txn, payloads, output)
    states = _target_state(output, payloads)
    boundary_names = {AUDIT_NAME: "audit", "signal_contract.json": "signal-contract", "manifest.csv": "manifest"}
    for name in TARGETS:
        boundary = boundary_names[name]
        _publication_boundary(f"{boundary}-commit-before")
        if states[name] != "expected":
            staged = root / name
            if name == AUDIT_NAME:
                try:
                    os.link(staged, output / name, follow_symlinks=False)
                except FileExistsError:
                    _check(output / name, payloads[name], f"concurrently committed {name}")
            else:
                os.replace(staged, output / name)
            _check(output / name, payloads[name], f"committed {name}")
            _fsync_directory(output)
        _publication_boundary(f"{boundary}-commit-after")


def _cleanup(txn: Path, payloads: dict[str, bytes], output: Path) -> None:
    root = _validate_transaction(txn, payloads, output)
    if any(state != "expected" for state in _target_state(output, payloads).values()):
        raise RuntimeError("refusing to clean an incomplete Task 6 transaction")
    for name in TARGETS:
        staged = root / name
        if os.path.lexists(staged):
            _check(staged, payloads[name], f"cleanup staged {name}")
            os.unlink(staged)
    os.rmdir(root)
    os.unlink(txn / "record.json")
    os.rmdir(txn)
    _fsync_directory(txn.parent)


def publish(source: Path = SOURCE, output: Path = OUTPUT) -> None:
    output = baseline._safe(Path(output))
    if output.is_symlink() or not output.is_dir():
        raise RuntimeError("Task 5 publication directory is missing or unsafe")
    payloads = _planned(Path(source), output)
    with _lock(output):
        txn = transaction_dir(output)
        if not os.path.lexists(txn):
            try:
                verify_only(output)
            except RuntimeError:
                pass
            else:
                return
            _birth(txn, payloads, output)
        _commit(output, txn, payloads)
        _cleanup(txn, payloads, output)
    verify_only(output)


def verify_only(output: Path = OUTPUT) -> None:
    output = baseline._safe(Path(output))
    paper._validate_registered_shape(output)
    paper.verify_paper_layer(output)
    audit, _ = baseline._audit_from_output(output)
    if audit is None:
        raise RuntimeError("Task 6 initialization audit is missing")
    baseline.verify_only(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    (verify_only if args.verify_only else lambda: publish(args.source, OUTPUT))()
    print("FIG519_INITIALIZATION_AUDIT_PASS; STATES=40; TFINAL=500; DIRECT_GENERATOR=0")


if __name__ == "__main__":
    main()
