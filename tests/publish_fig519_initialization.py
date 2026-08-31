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
REGISTERED_TASK6_PREDECESSOR_SHA256 = {
    AUDIT_NAME: {
        "d5b000c3ac9c1c05437aeae2652712e5d69e51de40eb49b43537b76274159818",
        "753cc01e6a260c66680c0a2ba5c80217fac53e871e950b321d37b77f7c1bfef6",
    },
    "signal_contract.json": {
        "515c58ce7fc1cc349054bcf0e0f06760ff995ceef928f4056004394bed50e9f6",
        "de619fd27f0757dc88eb2c50e6da9eb282648735fab94b4015ebbcca430c5d05",
    },
    "manifest.csv": {
        "dae38c7d79eb409981624001158f5b54075f3f500b4eaa390045aa5853dc9458",
        "47a9c43278bb5be55544a8976d1b3d6c504fd0e80ec5e19d5b0541405b7e62ff",
    },
}


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
    baseline._validate_raw_reference(audit)
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
    manifest_payload = baseline.manifest_bytes_with_external(
        output, entries, baseline._roles(), audit)
    return {AUDIT_NAME: audit_payload, "signal_contract.json": contract_payload,
            "manifest.csv": manifest_payload}


def transaction_dir(output: Path) -> Path:
    return output.parent / (output.name + ".task6-transaction")


def cleanup_tombstone_path(output: Path, payloads: dict[str, bytes]) -> Path:
    identity = _hash(_record(payloads))[:20]
    return output.parent / f"{output.name}.task6-cleanup-{identity}"


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
        elif _hash(current) in REGISTERED_TASK6_PREDECESSOR_SHA256[name]:
            states[name] = "predecessor"
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
            if name == AUDIT_NAME and states[name] == "missing":
                try:
                    os.link(staged, output / name, follow_symlinks=False)
                except FileExistsError:
                    _check(output / name, payloads[name], f"concurrently committed {name}")
            else:
                os.replace(staged, output / name)
                # Keep an owned staged hard link for uniform, fault-injected
                # cleanup.  A real crash between replace and this link is
                # still recoverable because expected final targets may have
                # no remaining staged payload.
                os.link(output / name, staged, follow_symlinks=False)
            _check(output / name, payloads[name], f"committed {name}")
            _fsync_directory(output)
        _publication_boundary(f"{boundary}-commit-after")


def _validate_cleanup_tombstone(tombstone: Path, payloads: dict[str, bytes],
                                output: Path) -> Path | None:
    if tombstone != cleanup_tombstone_path(output, payloads):
        raise RuntimeError("Task 6 cleanup tombstone identity mismatch")
    if tombstone.is_symlink() or not tombstone.is_dir():
        raise RuntimeError("Task 6 cleanup tombstone is unsafe")
    mode = tombstone.stat().st_mode
    if tombstone.stat().st_uid != os.geteuid() or mode & 0o077:
        raise RuntimeError("Task 6 cleanup tombstone ownership is unsafe")
    entries = {entry.name for entry in tombstone.iterdir()}
    if not entries.issubset({"record.json", "payload"}):
        raise RuntimeError("Task 6 cleanup tombstone has unowned entries")
    if any(state != "expected" for state in _target_state(output, payloads).values()):
        raise RuntimeError("Task 6 cleanup tombstone does not follow a full commit")
    record = tombstone / "record.json"
    root = tombstone / "payload"
    if os.path.lexists(record):
        _check(record, _record(payloads), "cleanup record")
    elif os.path.lexists(root):
        raise RuntimeError("Task 6 cleanup payload has lost its ownership record")
    if not os.path.lexists(root):
        return None
    if root.is_symlink() or not root.is_dir():
        raise RuntimeError("Task 6 cleanup payload is unsafe")
    unexpected = {entry.name for entry in root.iterdir()} - set(TARGETS)
    if unexpected:
        raise RuntimeError("Task 6 cleanup payload has unowned entries")
    for name in TARGETS:
        staged = root / name
        if os.path.lexists(staged):
            _check(staged, payloads[name], f"cleanup staged {name}")
    return root


def _cleanup_tombstone(tombstone: Path, payloads: dict[str, bytes], output: Path) -> None:
    root = _validate_cleanup_tombstone(tombstone, payloads, output)
    boundary_names = {AUDIT_NAME: "audit", "signal_contract.json": "signal-contract",
                      "manifest.csv": "manifest"}
    if root is not None:
        for name in TARGETS:
            staged = root / name
            if os.path.lexists(staged):
                _check(staged, payloads[name], f"cleanup staged {name}")
                boundary = boundary_names[name]
                _publication_boundary(f"cleanup-{boundary}-unlink-before")
                os.unlink(staged)
                _publication_boundary(f"cleanup-{boundary}-unlink-after")
        _publication_boundary("cleanup-payload-rmdir-before")
        os.rmdir(root)
        _publication_boundary("cleanup-payload-rmdir-after")
    record = tombstone / "record.json"
    if os.path.lexists(record):
        _check(record, _record(payloads), "cleanup record")
        _publication_boundary("cleanup-record-unlink-before")
        os.unlink(record)
        _publication_boundary("cleanup-record-unlink-after")
    if any(tombstone.iterdir()):
        raise RuntimeError("Task 6 cleanup tombstone has unowned residual entries")
    _publication_boundary("cleanup-tombstone-rmdir-before")
    os.rmdir(tombstone)
    _fsync_directory(tombstone.parent)
    _publication_boundary("cleanup-tombstone-rmdir-after")


def _transition_to_cleanup(txn: Path, payloads: dict[str, bytes], output: Path) -> Path:
    _validate_transaction(txn, payloads, output)
    if any(state != "expected" for state in _target_state(output, payloads).values()):
        raise RuntimeError("refusing to clean an incomplete Task 6 transaction")
    tombstone = cleanup_tombstone_path(output, payloads)
    _publication_boundary("cleanup-tombstone-rename-before")
    if os.path.lexists(tombstone):
        raise RuntimeError("Task 6 cleanup tombstone appeared concurrently")
    os.rename(txn, tombstone)
    _fsync_directory(tombstone.parent)
    _publication_boundary("cleanup-tombstone-rename-after")
    return tombstone


def publish(source: Path = SOURCE, output: Path = OUTPUT) -> None:
    output = baseline._safe(Path(output))
    if output.is_symlink() or not output.is_dir():
        raise RuntimeError("Task 5 publication directory is missing or unsafe")
    payloads = _planned(Path(source), output)
    with _lock(output):
        txn = transaction_dir(output)
        tombstone = cleanup_tombstone_path(output, payloads)
        if os.path.lexists(tombstone):
            if os.path.lexists(txn):
                raise RuntimeError("Task 6 canonical transaction conflicts with cleanup tombstone")
            _cleanup_tombstone(tombstone, payloads, output)
        if not os.path.lexists(txn):
            try:
                verify_only(output)
            except RuntimeError:
                pass
            else:
                return
            _birth(txn, payloads, output)
        _commit(output, txn, payloads)
        tombstone = _transition_to_cleanup(txn, payloads, output)
        _cleanup_tombstone(tombstone, payloads, output)
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
