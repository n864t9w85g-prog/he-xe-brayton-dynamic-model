#!/usr/bin/env python3
"""Publish the byte-identical Figure 5.18(a) 1200 K visual-proxy evidence."""
from __future__ import annotations

import argparse
import csv
import ctypes
import errno
import fcntl
import hashlib
import io
import json
import os
import stat
import sys
from contextlib import contextmanager
from pathlib import Path


class PublicationError(RuntimeError):
    """Raised when source or durable publication state is unsafe or inconsistent."""


ROOT = Path(__file__).resolve().parents[1]
PDF_RELATIVE_PATH = (
    "空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf"
)
SOURCE_PAGE_RELATIVE_PATH = "tmp/steady53_recheck_20260827/paper-105.png"
PDF_PATH = ROOT / PDF_RELATIVE_PATH
SOURCE_PAGE = ROOT / SOURCE_PAGE_RELATIVE_PATH
DURABLE_ROOT = ROOT / "data/provenance/steady53/fig5_18a"

PDF_SHA256 = "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a"
PAGE_SHA256 = "da9e9a536d0dda98152fa694d942b393ca2f5f5d10b720dbd79692ac694cc95c"
ANCHOR_K = "1200.0000000000000"
ANCHOR_IDENTITY = "figure_5_18a_t0_visual_proxy_not_author_initial_state"

ARTIFACT_NAMES = (
    "README.md",
    "source_page_105.png",
    "provenance.json",
    "manifest.csv",
)
MANIFEST_FIELDS = ("path", "bytes", "sha256", "purpose")

README = """# Figure 5.18(a) 1200 K visual-proxy anchor

This directory preserves the existing PDF page image byte-identically and
records the 1200.0000000000000 K value visible in Figure 5.18(a).

The 1200 K value is a visual proxy only. It is not the author's t0.
It is not a reproduced paper result. It cannot authorize formal promotion.

anchor_identity = figure_5_18a_t0_visual_proxy_not_author_initial_state
paper_reproduced = false
author_initial_state_identified = false
formal_promotion = false
"""


def staging_path(durable_root: Path = DURABLE_ROOT) -> Path:
    durable_root = Path(durable_root)
    return durable_root.parent / f".{durable_root.name}.publishing"


def _absolute(path: Path) -> Path:
    path = Path(path)
    if not path.is_absolute() or ".." in path.parts:
        raise PublicationError(f"path must be absolute and lexical: {path}")
    return path


def _lstat(path: Path):
    try:
        return os.lstat(path)
    except FileNotFoundError:
        return None
    except OSError as error:
        raise PublicationError(f"cannot inspect path: {path}: {error}") from error


def _reject_symlink_components(path: Path) -> None:
    path = _absolute(path)
    probe = Path(path.anchor)
    for part in path.parts[1:]:
        probe /= part
        entry_stat = _lstat(probe)
        if entry_stat is not None and stat.S_ISLNK(entry_stat.st_mode):
            raise PublicationError(f"symlinked path component is forbidden: {probe}")


def _require_directory(path: Path, label: str):
    path = _absolute(path)
    _reject_symlink_components(path)
    entry_stat = _lstat(path)
    if entry_stat is None:
        raise PublicationError(f"{label} is missing: {path}")
    if not stat.S_ISDIR(entry_stat.st_mode):
        raise PublicationError(f"{label} is not a directory: {path}")
    return entry_stat


def _require_regular(path: Path, label: str):
    path = _absolute(path)
    _reject_symlink_components(path)
    entry_stat = _lstat(path)
    if entry_stat is None:
        raise PublicationError(f"{label} is missing: {path}")
    if not stat.S_ISREG(entry_stat.st_mode):
        raise PublicationError(f"{label} is not a regular file: {path}")
    return entry_stat


def _read_regular(path: Path, label: str) -> bytes:
    path = _absolute(path)
    before = _require_regular(path, label)
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise PublicationError(f"cannot safely open {label}: {path}: {error}") from error
    opened = os.fstat(descriptor)
    if not stat.S_ISREG(opened.st_mode) or (opened.st_dev, opened.st_ino) != (
        before.st_dev,
        before.st_ino,
    ):
        os.close(descriptor)
        raise PublicationError(f"{label} changed during safe open: {path}")
    chunks = []
    try:
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
    finally:
        os.close(descriptor)
    after = _require_regular(path, label)
    if (after.st_dev, after.st_ino, after.st_size) != (
        opened.st_dev,
        opened.st_ino,
        opened.st_size,
    ):
        raise PublicationError(f"{label} changed while reading: {path}")
    payload = b"".join(chunks)
    if len(payload) != opened.st_size:
        raise PublicationError(f"{label} size changed while reading: {path}")
    return payload


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _validated_pdf() -> bytes:
    pdf = _read_regular(PDF_PATH, "source PDF")
    if _sha256(pdf) != PDF_SHA256:
        raise PublicationError("source PDF hash differs from the immutable contract")
    return pdf


def _validated_initial_page() -> bytes:
    page = _read_regular(SOURCE_PAGE, "source page")
    if _sha256(page) != PAGE_SHA256:
        raise PublicationError("source page hash differs from the immutable contract")
    return page


def _json_bytes(value: dict[str, object]) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8")


def _provenance_bytes() -> bytes:
    return _json_bytes(
        {
            "anchor_K": ANCHOR_K,
            "anchor_identity": ANCHOR_IDENTITY,
            "author_initial_state_identified": False,
            "figure": "Figure 5.18(a)",
            "formal_promotion": False,
            "paper_reproduced": False,
            "pdf_page": 105,
            "pdf_sha256": PDF_SHA256,
            "printed_page": 90,
            "source_page_path": SOURCE_PAGE_RELATIVE_PATH,
            "source_page_sha256": PAGE_SHA256,
            "source_pdf_path": PDF_RELATIVE_PATH,
        }
    )


def manifest_bytes(rows: list[dict[str, str]]) -> bytes:
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=MANIFEST_FIELDS, lineterminator="\n")
    writer.writeheader()
    for row in rows:
        writer.writerow({field: row[field] for field in MANIFEST_FIELDS})
    return stream.getvalue().encode("utf-8")


def _artifact_payloads(page: bytes) -> dict[str, bytes]:
    payloads = {
        "README.md": README.encode("utf-8"),
        "source_page_105.png": page,
        "provenance.json": _provenance_bytes(),
    }
    purposes = {
        "README.md": "visual_proxy_limitations_and_negative_promotion_status",
        "source_page_105.png": "byte_identical_pdf_page_105_figure_5_18a_source",
        "provenance.json": "figure_5_18a_anchor_identity_and_source_hashes",
    }
    rows = [
        {
            "path": name,
            "bytes": str(len(payload)),
            "sha256": _sha256(payload),
            "purpose": purposes[name],
        }
        for name, payload in payloads.items()
    ]
    payloads["manifest.csv"] = manifest_bytes(rows)
    return payloads


def _fsync_directory_fd(descriptor: int) -> None:
    opened = os.fstat(descriptor)
    if not stat.S_ISDIR(opened.st_mode):
        raise PublicationError("fsync target descriptor is not a directory")
    os.fsync(descriptor)


def _entry_stat(directory_descriptor: int, name: str):
    try:
        return os.stat(name, dir_fd=directory_descriptor, follow_symlinks=False)
    except FileNotFoundError:
        return None


def _open_directory_at(directory_descriptor: int, name: str, label: str) -> int:
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(name, flags, dir_fd=directory_descriptor)
    opened = os.fstat(descriptor)
    if not stat.S_ISDIR(opened.st_mode):
        os.close(descriptor)
        raise PublicationError(f"{label} is not a directory")
    return descriptor


def _read_regular_at(directory_descriptor: int, name: str, label: str) -> bytes:
    before = _entry_stat(directory_descriptor, name)
    if before is None or not stat.S_ISREG(before.st_mode):
        raise PublicationError(f"{label} is missing or not a regular file")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(name, flags, dir_fd=directory_descriptor)
    opened = os.fstat(descriptor)
    if not stat.S_ISREG(opened.st_mode) or (opened.st_dev, opened.st_ino) != (
        before.st_dev,
        before.st_ino,
    ):
        os.close(descriptor)
        raise PublicationError(f"{label} changed during safe open")
    chunks = []
    try:
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
    finally:
        os.close(descriptor)
    after = _entry_stat(directory_descriptor, name)
    if after is None or (after.st_dev, after.st_ino, after.st_size) != (
        opened.st_dev,
        opened.st_ino,
        opened.st_size,
    ):
        raise PublicationError(f"{label} changed while reading")
    payload = b"".join(chunks)
    if len(payload) != opened.st_size:
        raise PublicationError(f"{label} size changed while reading")
    return payload


def _write_exclusive(target: tuple[int, str], payload: bytes) -> None:
    directory_descriptor, name = target
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(name, flags, 0o600, dir_fd=directory_descriptor)
    try:
        offset = 0
        while offset < len(payload):
            written = os.write(descriptor, payload[offset:])
            if written <= 0:
                raise OSError("zero-byte write while staging publication")
            offset += written
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _inventory(directory: Path) -> set[str]:
    _require_directory(directory, "publication directory")
    try:
        entries = list(os.scandir(directory))
    except OSError as error:
        raise PublicationError(f"cannot enumerate publication directory: {error}") from error
    names = set()
    for entry in entries:
        if entry.is_symlink() or not entry.is_file(follow_symlinks=False):
            raise PublicationError(f"unexpected non-regular publication entry: {entry.name}")
        names.add(entry.name)
    return names


def _inventory_fd(directory_descriptor: int) -> set[str]:
    names = set(os.listdir(directory_descriptor))
    for name in names:
        entry_stat = _entry_stat(directory_descriptor, name)
        if entry_stat is None or not stat.S_ISREG(entry_stat.st_mode):
            raise PublicationError(f"unexpected non-regular publication entry: {name}")
    return names


def _verify_directory(directory: Path, payloads: dict[str, bytes]) -> None:
    expected_names = set(ARTIFACT_NAMES)
    actual_names = _inventory(directory)
    if actual_names != expected_names:
        raise PublicationError(
            f"publication inventory mismatch: expected {sorted(expected_names)}, "
            f"got {sorted(actual_names)}"
        )
    for name in ARTIFACT_NAMES:
        actual = _read_regular(directory / name, f"published {name}")
        if actual != payloads[name]:
            raise PublicationError(f"published artifact differs from contract: {name}")


def _verify_directory_fd(directory_descriptor: int, payloads: dict[str, bytes]) -> None:
    expected_names = set(ARTIFACT_NAMES)
    actual_names = _inventory_fd(directory_descriptor)
    if actual_names != expected_names:
        raise PublicationError(
            f"publication inventory mismatch: expected {sorted(expected_names)}, "
            f"got {sorted(actual_names)}"
        )
    for name in ARTIFACT_NAMES:
        actual = _read_regular_at(directory_descriptor, name, f"published {name}")
        if actual != payloads[name]:
            raise PublicationError(f"published artifact differs from contract: {name}")


def _exclusive_rename(
    source_parent_descriptor: int,
    source_name: str,
    destination_parent_descriptor: int,
    destination_name: str,
) -> None:
    """Rename relative to held parents without replacing an existing entry."""
    library = ctypes.CDLL(None, use_errno=True)
    source_bytes = os.fsencode(source_name)
    destination_bytes = os.fsencode(destination_name)
    result = None
    if sys.platform == "darwin" and hasattr(library, "renameatx_np"):
        function = library.renameatx_np
        function.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        function.restype = ctypes.c_int
        result = function(
            source_parent_descriptor,
            source_bytes,
            destination_parent_descriptor,
            destination_bytes,
            0x00000004,
        )
    elif hasattr(library, "renameat2"):
        function = library.renameat2
        function.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        function.restype = ctypes.c_int
        result = function(
            source_parent_descriptor,
            source_bytes,
            destination_parent_descriptor,
            destination_bytes,
            0x00000001,
        )
    else:
        raise PublicationError("platform lacks an exclusive directory-rename primitive")
    if result != 0:
        error_number = ctypes.get_errno()
        if error_number in (errno.EEXIST, errno.ENOTEMPTY):
            raise PublicationError(
                f"destination appeared during publication: {destination_name}"
            )
        raise PublicationError(
            f"exclusive publication rename failed: {os.strerror(error_number)}"
        )


@contextmanager
def _parent_lock(parent: Path):
    parent_stat = _require_directory(parent, "durable parent")
    descriptor = os.open(parent, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    opened = os.fstat(descriptor)
    if (opened.st_dev, opened.st_ino) != (parent_stat.st_dev, parent_stat.st_ino):
        os.close(descriptor)
        raise PublicationError("durable parent changed during safe open")
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield descriptor, opened
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def _require_parent_identity(parent: Path, opened_parent) -> None:
    current = _require_directory(parent, "durable parent")
    if (current.st_dev, current.st_ino) != (opened_parent.st_dev, opened_parent.st_ino):
        raise PublicationError("durable parent was replaced during publication")


def _quarantine_unbound_destination(
    parent_descriptor: int, destination_name: str
) -> None:
    """Preserve, rather than unlink, any destination not bound to owned staging.

    POSIX has no portable rename-by-source-inode operation.  The transaction
    therefore holds directory descriptors, checks the destination inode after
    the exclusive rename, and exclusively moves any unbound destination aside.
    A continuously mutating same-UID process can deny service, but no cleanup
    here unlinks or overwrites its replacement.
    """
    for counter in range(32):
        current = _entry_stat(parent_descriptor, destination_name)
        if current is None:
            return
        quarantine_name = (
            f".{destination_name}.rejected-{current.st_dev:x}-{current.st_ino:x}-{counter}"
        )
        if _entry_stat(parent_descriptor, quarantine_name) is not None:
            continue
        try:
            _exclusive_rename(
                parent_descriptor,
                destination_name,
                parent_descriptor,
                quarantine_name,
            )
        except PublicationError:
            if _entry_stat(parent_descriptor, destination_name) is None:
                return
            continue
        _fsync_directory_fd(parent_descriptor)
        if _entry_stat(parent_descriptor, destination_name) is None:
            return
    raise PublicationError(
        "could not quarantine a concurrently replaced durable destination"
    )


def _payloads_from_durable_fd(durable_descriptor: int) -> dict[str, bytes]:
    page = _read_regular_at(
        durable_descriptor, "source_page_105.png", "durable source page"
    )
    if _sha256(page) != PAGE_SHA256:
        raise PublicationError("durable source page hash differs from the contract")
    return _artifact_payloads(page)


def _publish() -> dict[str, object]:
    _validated_pdf()
    durable = _absolute(DURABLE_ROOT)
    staging = staging_path(durable)
    _reject_symlink_components(durable)
    _reject_symlink_components(staging)
    _require_directory(durable.parent, "durable parent")

    with _parent_lock(durable.parent) as (parent_descriptor, opened_parent):
        stage_name = staging.name
        destination_name = durable.name
        if _entry_stat(parent_descriptor, stage_name) is not None:
            raise PublicationError(f"stale or unsafe staging path exists: {staging}")
        if _entry_stat(parent_descriptor, destination_name) is not None:
            durable_descriptor = _open_directory_at(
                parent_descriptor, destination_name, "durable publication"
            )
            try:
                payloads = _payloads_from_durable_fd(durable_descriptor)
                _verify_directory_fd(durable_descriptor, payloads)
                _require_parent_identity(durable.parent, opened_parent)
            finally:
                os.close(durable_descriptor)
            return _report()

        page = _validated_initial_page()
        payloads = _artifact_payloads(page)
        os.mkdir(stage_name, 0o700, dir_fd=parent_descriptor)
        staging_descriptor = _open_directory_at(
            parent_descriptor, stage_name, "publication staging"
        )
        opened_staging = os.fstat(staging_descriptor)
        _fsync_directory_fd(parent_descriptor)
        try:
            for name in ARTIFACT_NAMES[:-1]:
                _write_exclusive((staging_descriptor, name), payloads[name])
            _write_exclusive(
                (staging_descriptor, "manifest.csv"), payloads["manifest.csv"]
            )
            _fsync_directory_fd(staging_descriptor)
            _verify_directory_fd(staging_descriptor, payloads)
            _require_parent_identity(durable.parent, opened_parent)
            current = _entry_stat(parent_descriptor, stage_name)
            if current is None or (current.st_dev, current.st_ino) != (
                opened_staging.st_dev,
                opened_staging.st_ino,
            ):
                raise PublicationError("publication staging was replaced")
            if _entry_stat(parent_descriptor, destination_name) is not None:
                raise PublicationError(
                    f"destination appeared during publication: {durable}"
                )
            _exclusive_rename(
                parent_descriptor,
                stage_name,
                parent_descriptor,
                destination_name,
            )
            _fsync_directory_fd(parent_descriptor)
            committed = _entry_stat(parent_descriptor, destination_name)
            if committed is None or (committed.st_dev, committed.st_ino) != (
                opened_staging.st_dev,
                opened_staging.st_ino,
            ):
                _quarantine_unbound_destination(
                    parent_descriptor, destination_name
                )
                raise PublicationError(
                    "exclusive commit did not bind the owned staging directory"
                )
            _verify_directory_fd(staging_descriptor, payloads)
            _require_parent_identity(durable.parent, opened_parent)
        finally:
            os.close(staging_descriptor)
    return _verify_only()


def publish() -> dict[str, object]:
    """Publish once, or validate an already matching immutable publication."""
    try:
        return _publish()
    except PublicationError:
        raise
    except OSError as error:
        raise PublicationError(f"publication filesystem failure: {error}") from error


def _report() -> dict[str, object]:
    return {
        "anchor_K": ANCHOR_K,
        "anchor_identity": ANCHOR_IDENTITY,
        "paper_reproduced": False,
        "author_initial_state_identified": False,
        "formal_promotion": False,
    }


def _verify_only() -> dict[str, object]:
    _validated_pdf()
    durable = _absolute(DURABLE_ROOT)
    staging = staging_path(durable)
    _reject_symlink_components(durable)
    _reject_symlink_components(staging)
    if os.path.lexists(staging):
        raise PublicationError(f"stale or unsafe staging path exists: {staging}")
    page = _read_regular(durable / "source_page_105.png", "durable source page")
    if _sha256(page) != PAGE_SHA256:
        raise PublicationError("durable source page hash differs from the contract")
    payloads = _artifact_payloads(page)
    _verify_directory(durable, payloads)
    return _report()


def verify_only() -> dict[str, object]:
    """Recompute tracked PDF and durable hashes without filesystem writes."""
    try:
        return _verify_only()
    except PublicationError:
        raise
    except OSError as error:
        raise PublicationError(f"verification filesystem failure: {error}") from error


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-only", action="store_true")
    arguments = parser.parse_args(argv)
    if arguments.verify_only:
        verify_only()
        print("FIG518A_ANCHOR_VERIFY_PASS")
    else:
        publish()
        print("FIG518A_ANCHOR_PUBLISH_PASS")


if __name__ == "__main__":
    main()
