"""Resolve a historical protected-file manifest by exact SHA256 identity."""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
from pathlib import Path
from typing import Iterable


class AuditError(RuntimeError):
    """Raised when the historical manifest cannot be audited unambiguously."""


FIELDS = (
    "original_path",
    "expected_sha256",
    "original_state",
    "resolution",
    "resolved_path",
    "resolved_sha256",
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _valid_hash(value: str) -> bool:
    return (
        len(value) == 64
        and value == value.lower()
        and all(character in "0123456789abcdef" for character in value)
    )


def _read_manifest(path: Path) -> list[tuple[Path, str]]:
    try:
        with path.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            if reader.fieldnames != ["paths", "hashes"]:
                raise AuditError(
                    "manifest header must be exactly paths,hashes"
                )
            raw_rows = list(reader)
    except (OSError, UnicodeError, csv.Error) as exc:
        raise AuditError(f"cannot read manifest: path={path}; error={exc}") from exc
    if not raw_rows:
        raise AuditError("manifest must contain at least one row")

    rows: list[tuple[Path, str]] = []
    seen: set[str] = set()
    for number, row in enumerate(raw_rows, start=2):
        path_text = row.get("paths", "")
        expected_hash = row.get("hashes", "")
        original = Path(path_text)
        if not path_text or not original.is_absolute():
            raise AuditError(
                f"manifest path must be nonempty and absolute: row={number}"
            )
        if path_text in seen:
            raise AuditError(f"duplicate manifest path: {path_text}")
        if not _valid_hash(expected_hash):
            raise AuditError(
                f"invalid manifest SHA256: row={number}; value={expected_hash!r}"
            )
        seen.add(path_text)
        rows.append((original, expected_hash))
    return rows


def _durable_index(paths: Iterable[Path]) -> dict[str, Path]:
    index: dict[str, Path] = {}
    for path in paths:
        resolved = path.resolve()
        if not resolved.is_file():
            raise AuditError(f"durable file is missing: {resolved}")
        digest = sha256(resolved)
        if digest in index:
            raise AuditError(
                "durable SHA256 is ambiguous: "
                f"hash={digest}; paths={index[digest]},{resolved}"
            )
        index[digest] = resolved
    return index


def resolve_manifest(
    manifest: Path, durable_files: Iterable[Path]
) -> tuple[list[dict[str, str]], dict[str, int]]:
    """Return per-row resolution and counts without changing source paths."""
    durable = _durable_index(durable_files)
    results: list[dict[str, str]] = []
    for original, expected_hash in _read_manifest(manifest):
        if original.exists() or original.is_symlink():
            if original.is_file() and not original.is_symlink():
                actual_hash = sha256(original)
                if actual_hash == expected_hash:
                    original_state = "hash_match"
                    resolution = "original_path_hash_match"
                    resolved_path = str(original)
                    resolved_hash = actual_hash
                else:
                    original_state = "hash_mismatch"
                    resolution = "unresolved"
                    resolved_path = ""
                    resolved_hash = actual_hash
            else:
                original_state = "not_regular_file"
                resolution = "unresolved"
                resolved_path = ""
                resolved_hash = ""
        elif expected_hash in durable:
            original_state = "missing"
            resolution = "durable_hash_equivalent"
            resolved_path = str(durable[expected_hash])
            resolved_hash = expected_hash
        else:
            original_state = "missing"
            resolution = "unresolved"
            resolved_path = ""
            resolved_hash = ""
        results.append(
            {
                "original_path": str(original),
                "expected_sha256": expected_hash,
                "original_state": original_state,
                "resolution": resolution,
                "resolved_path": resolved_path,
                "resolved_sha256": resolved_hash,
            }
        )

    original_count = sum(
        row["resolution"] == "original_path_hash_match" for row in results
    )
    durable_count = sum(
        row["resolution"] == "durable_hash_equivalent" for row in results
    )
    unresolved_count = sum(
        row["resolution"] == "unresolved" for row in results
    )
    return results, {
        "row_count": len(results),
        "resolved_count": original_count + durable_count,
        "original_present_count": original_count,
        "durable_equivalent_count": durable_count,
        "unresolved_count": unresolved_count,
    }


def render_csv(rows: list[dict[str, str]]) -> bytes:
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=FIELDS, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return buffer.getvalue().encode("utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("durable_files", type=Path, nargs="+")
    arguments = parser.parse_args()

    rows, summary = resolve_manifest(
        arguments.manifest, arguments.durable_files
    )
    payload = render_csv(rows)
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    with arguments.output.open("xb") as handle:
        handle.write(payload)
    if summary["unresolved_count"]:
        raise AuditError(
            f"protected manifest has unresolved rows: {summary['unresolved_count']}"
        )
    print(
        "PROTECTED_MANIFEST_RECOVERY_PASS; "
        f"ROWS={summary['row_count']}; "
        f"RESOLVED={summary['resolved_count']}; "
        f"ORIGINAL_PRESENT={summary['original_present_count']}; "
        f"DURABLE_EQUIVALENT={summary['durable_equivalent_count']}"
    )


if __name__ == "__main__":
    main()
