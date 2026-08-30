"""Recover exact pre-cleanup SLX blobs without loading or editing them."""
from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
import hashlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


class RecoveryError(RuntimeError):
    """Raised when a recovery identity or publication gate fails."""


@dataclass(frozen=True)
class ExpectedBlob:
    sha256: str
    size_bytes: int
    role: str


EXPECTED_COMMIT = "f8bcd833e816eb681982b7dd04364e4b856948e3"
EXPECTED_BLOBS = {
    "final_steady_24a.slx": ExpectedBlob(
        "0532e9ddf2deb7ef5e40cc1b8e619c44"
        "ea7afd36b00d807d118f4cd812a5a391",
        617390,
        "a1_steady_authority",
    ),
    "final_dynamic_24a.slx": ExpectedBlob(
        "2bed798bcd3d32c15b7771907e8cd545"
        "2aa4171a0b87335af7c8769ed6987790",
        660489,
        "historical_dynamic_only",
    ),
}


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _git(source: Path, *arguments: str, text: bool = False):
    try:
        return subprocess.run(
            ["git", "-C", str(source), *arguments],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=text,
        ).stdout
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr if isinstance(exc.stderr, str) else exc.stderr.decode(
            "utf-8", errors="replace"
        )
        raise RecoveryError(
            f"git command failed: arguments={arguments!r}; stderr={stderr.strip()}"
        ) from exc


def _validate_name(name: str) -> None:
    path = Path(name)
    if not name or path.name != name or path.is_absolute():
        raise RecoveryError(f"unsafe Git path: {name!r}")


def _manifest_bytes(
    expected: dict[str, ExpectedBlob], commit: str, recovery_date: str
) -> bytes:
    buffer = io.StringIO(newline="")
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(
        (
            "git_path",
            "source_commit",
            "size_bytes",
            "sha256",
            "role",
            "recovery_date",
        )
    )
    for name in sorted(expected):
        identity = expected[name]
        writer.writerow(
            (
                name,
                commit,
                identity.size_bytes,
                identity.sha256,
                identity.role,
                recovery_date,
            )
        )
    return buffer.getvalue().encode("utf-8")


def _readme_bytes(commit: str) -> bytes:
    return (
        "# f8bcd83 immutable model baselines\n\n"
        f"Source commit: `{commit}`.\n\n"
        "`final_steady_24a.slx` is the byte-identical authority for the "
        "radiator A1 exploration contract. `final_dynamic_24a.slx` is retained "
        "only as historical recovery evidence; its presence does not reinstate "
        "any conclusion obtained from the superseded dynamic-model state.\n\n"
        "These SLX files are recovered as opaque Git blobs. They were not loaded, "
        "unpacked, simulated, or edited during recovery.\n\n"
        "`paper_reproduced = false`  \n"
        "`formal_promotion = false`\n"
    ).encode("utf-8")


def recover(
    source: Path,
    commit: str,
    output: Path,
    expected: dict[str, ExpectedBlob],
    recovery_date: str,
) -> None:
    """Export verified blobs and publish one immutable provenance directory."""
    source = source.resolve()
    output = output.resolve()
    if output.exists() or output.is_symlink():
        raise FileExistsError(output)
    if not expected:
        raise RecoveryError("expected blob contract must not be empty")

    resolved_commit = _git(
        source, "rev-parse", "--verify", f"{commit}^{{commit}}", text=True
    ).strip()
    if resolved_commit != commit:
        raise RecoveryError(
            f"source commit mismatch: expected={commit}; actual={resolved_commit}"
        )

    planned: dict[str, bytes] = {}
    for name in sorted(expected):
        _validate_name(name)
        identity = expected[name]
        payload = _git(source, "cat-file", "blob", f"{commit}:{name}")
        actual_hash = _sha256(payload)
        if len(payload) != identity.size_bytes:
            raise RecoveryError(
                f"blob size mismatch: path={name}; expected={identity.size_bytes}; "
                f"actual={len(payload)}"
            )
        if actual_hash != identity.sha256:
            raise RecoveryError(
                f"blob hash mismatch: path={name}; expected={identity.sha256}; "
                f"actual={actual_hash}"
            )
        planned[name] = payload

    planned["baseline_manifest.csv"] = _manifest_bytes(
        expected, commit, recovery_date
    )
    planned["README.md"] = _readme_bytes(commit)

    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(prefix=f".{output.name}.recover-", dir=output.parent)
    )
    try:
        for name, payload in planned.items():
            destination = staging / name
            with destination.open("xb") as handle:
                handle.write(payload)
        for name, payload in planned.items():
            actual = (staging / name).read_bytes()
            if _sha256(actual) != _sha256(payload):
                raise RecoveryError(f"staged payload hash mismatch: path={name}")
        os.replace(staging, output)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise


def materialize_exact_file(
    source: Path,
    destination: Path,
    expected_sha256: str,
) -> None:
    """Create an optional compatibility copy without overwriting any path."""
    payload = source.read_bytes()
    actual = _sha256(payload)
    if actual != expected_sha256:
        raise RecoveryError(
            f"source hash mismatch: expected={expected_sha256}; actual={actual}"
        )
    if destination.exists() or destination.is_symlink():
        if destination.is_file() and not destination.is_symlink():
            existing = _sha256(destination.read_bytes())
            if existing == expected_sha256:
                return
        raise FileExistsError(destination)

    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        dir=destination.parent,
        prefix=f".{destination.name}.",
        delete=False,
    ) as handle:
        temporary = Path(handle.name)
        handle.write(payload)
    try:
        if _sha256(temporary.read_bytes()) != expected_sha256:
            raise RecoveryError("temporary materialization hash mismatch")
        try:
            os.link(temporary, destination)
        except FileExistsError:
            raise FileExistsError(destination) from None
        if _sha256(destination.read_bytes()) != expected_sha256:
            destination.unlink(missing_ok=True)
            raise RecoveryError("published compatibility hash mismatch")
    finally:
        temporary.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_repository", type=Path)
    parser.add_argument("output_directory", type=Path)
    arguments = parser.parse_args()
    recover(
        arguments.source_repository,
        EXPECTED_COMMIT,
        arguments.output_directory,
        EXPECTED_BLOBS,
        "2026-08-31",
    )
    print("CLEANUP_BASELINE_RECOVERY_PASS; FILES=2; SLX_NOT_LOADED")


if __name__ == "__main__":
    main()
