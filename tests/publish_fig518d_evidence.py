#!/usr/bin/env python3
import argparse
import csv
import hashlib
import io
import json
import os
import stat
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
DURABLE_ROOT = ROOT / "data/provenance/steady53/fig5_18d"
MANIFEST_FIELDS = (
    "source_path",
    "durable_path",
    "purpose",
    "byte_count",
    "sha256",
    "is_original_output",
    "is_regenerable",
    "evidence_grade",
)
EXPECTED_REPRESENTATIVE_IDS = (
    "T300_fd1p45_one__legacy_transfer", "T300_fd1p45_one__conservative_source",
    "T300_fd1p45_one__optimistic_source", "T300_fd1p45_two__legacy_transfer",
    "T300_fd1p45_two__conservative_source", "T300_fd1p45_two__optimistic_source",
    "P95_WG_fd1p45_two__legacy_transfer", "P95_WG_fd1p45_two__conservative_source",
    "P95_WG_fd1p45_two__optimistic_source", "APG_fd1p00_two__legacy_transfer",
    "APG_fd1p00_two__conservative_source", "APG_fd1p00_two__optimistic_source",
)
EXPECTED_INELIGIBLE_IDS = {"T300_fd1p45_one__legacy_transfer"}
REPRESENTATIVE_CANDIDATE_IDS = tuple(x for x in EXPECTED_REPRESENTATIVE_IDS if x not in EXPECTED_INELIGIBLE_IDS)



class PublicationError(RuntimeError):
    pass


def _spec(source_path, durable_path, purpose, regenerable, evidence_grade):
    return {
        "source_path": source_path,
        "durable_path": durable_path,
        "purpose": purpose,
        "is_original_output": "true",
        "is_regenerable": "true" if regenerable else "false",
        "evidence_grade": evidence_grade,
    }


SOURCE_SPECS = (
    _spec(
        "tmp/steady53_curves_20260828/radiator_scan_points.csv",
        "paper_curve/points.csv",
        "figure_5_18d_digitized_points",
        False,
        "⚠️_digitized_scan_evidence",
    ),
    _spec(
        "tmp/steady53_curves_20260828/radiator_scan_provenance.json",
        "paper_curve/provenance.json",
        "figure_5_18d_digitization_provenance",
        False,
        "✅_recorded_provenance",
    ),
    _spec(
        "tmp/steady53_curves_20260828/radiator_ic/ic_250.mat",
        "initial_condition_runs/ic_250.mat",
        "radiator_initial_condition_output",
        False,
        "✅_completed_exploration_output",
    ),
    _spec(
        "tmp/steady53_curves_20260828/radiator_ic/ic_250_wall.csv",
        "initial_condition_runs/ic_250_wall.csv",
        "radiator_wall_temperature_trace",
        False,
        "✅_completed_exploration_output",
    ),
    _spec(
        "tmp/steady53_curves_20260828/radiator_ic/ic_250_outlet.csv",
        "initial_condition_runs/ic_250_outlet.csv",
        "radiator_outlet_temperature_trace",
        False,
        "✅_completed_exploration_output",
    ),
    _spec(
        "tmp/steady53_curves_20260828/radiator_ic/ic_407.mat",
        "initial_condition_runs/ic_407.mat",
        "radiator_initial_condition_output",
        False,
        "✅_completed_exploration_output",
    ),
    _spec(
        "tmp/steady53_curves_20260828/radiator_ic/ic_407_wall.csv",
        "initial_condition_runs/ic_407_wall.csv",
        "radiator_wall_temperature_trace",
        False,
        "✅_completed_exploration_output",
    ),
    _spec(
        "tmp/steady53_curves_20260828/radiator_ic/ic_407_outlet.csv",
        "initial_condition_runs/ic_407_outlet.csv",
        "radiator_outlet_temperature_trace",
        False,
        "✅_completed_exploration_output",
    ),
    _spec(
        "tmp/steady53_curves_20260828/radiator_ic/diary.txt",
        "initial_condition_runs/diary.txt",
        "radiator_initial_condition_run_diary",
        False,
        "✅_completed_exploration_output",
    ),
    _spec(
        "tmp/radiator_A1_20260830_A2/offline_screen/offline_96.csv",
        "a1_summary/offline_96.csv",
        "a1_offline_parameter_screen",
        True,
        "✅_deterministic_exploration_output",
    ),
    _spec(
        "tmp/radiator_A1_20260830_A2/offline_screen/offline_rejection_log.csv",
        "a1_summary/offline_rejection_log.csv",
        "a1_offline_rejection_log",
        True,
        "✅_deterministic_exploration_output",
    ),
    _spec(
        "tmp/radiator_A1_20260830_A2/representatives/representative_matrix.csv",
        "a1_summary/representative_matrix.csv",
        "a1_fixed_role_representatives",
        True,
        "✅_deterministic_exploration_output",
    ),
    _spec(
        "tmp/radiator_A1_20260830_A2/representatives/selection.json",
        "a1_summary/selection.json",
        "a1_representative_eligibility_selection",
        True,
        "✅_deterministic_exploration_output",
    ),
    *tuple(
        _spec(
            f"tmp/radiator_A1_20260830_A2/representatives/{candidate_id}/parameter_manifest.json",
            f"a1_summary/representative_manifests/{candidate_id}.json",
            "a1_candidate_parameter_manifest",
            True,
            "✅_deterministic_exploration_output",
        )
        for candidate_id in REPRESENTATIVE_CANDIDATE_IDS
    ),
    _spec(
        "tmp/radiator_A1_20260830_A2/comparisons/advance_14000.json",
        "a1_summary/advance_14000.json",
        "a1_14000_stage_selection",
        True,
        "✅_completed_exploration_output",
    ),
    _spec(
        "tmp/radiator_A1_20260830_A2/source_contract/source_contract.json",
        "a1_summary/source_contract.json",
        "a1_source_contract",
        True,
        "✅_recorded_provenance",
    ),
    _spec(
        "tmp/radiator_A1_20260830_A2/source_contract/unit_contract.json",
        "a1_summary/unit_contract.json",
        "a1_unit_contract",
        True,
        "✅_recorded_provenance",
    ),
    _spec(
        "tmp/radiator_A1_20260830_A2/source_contract/output_hashes.json",
        "a1_summary/output_hashes.json",
        "a1_source_contract_output_hashes",
        True,
        "✅_recorded_provenance",
    ),
    _spec(
        "tmp/radiator_A1_20260830_A2/final_audit/preparation_summary.json",
        "a1_summary/preparation_summary.json",
        "a1_candidate_preparation_summary",
        False,
        "✅_completed_exploration_output",
    ),
    _spec(
        "tmp/radiator_A1_20260830_A2/final_audit/batch_500_summary.json",
        "a1_summary/batch_500_summary.json",
        "a1_500_second_batch_summary",
        False,
        "✅_completed_exploration_output",
    ),
    _spec(
        "tmp/radiator_A1_20260830_A2/final_audit/summary_500.json",
        "a1_summary/summary_500.json",
        "a1_500_second_analysis_summary",
        False,
        "✅_completed_exploration_output",
    ),
    _spec(
        "tmp/radiator_A1_20260830_A2/final_audit/batch_14000_summary.json",
        "a1_summary/batch_14000_summary.json",
        "a1_14000_second_batch_summary",
        False,
        "✅_completed_exploration_output",
    ),
    _spec(
        "tmp/radiator_A1_20260830_A2/final_audit/summary_14000.json",
        "a1_summary/summary_14000.json",
        "a1_14000_second_analysis_summary",
        False,
        "✅_completed_exploration_output",
    ),
    _spec(
        "tmp/radiator_A1_20260830_A2/final_audit/report.md",
        "a1_summary/report.md",
        "a1_final_audit_report",
        False,
        "✅_completed_exploration_output",
    ),
)

# Immutable contract: literal SHA256 values keyed by every durable evidence path.
EXPECTED_SHA256 = {
    'paper_curve/points.csv': '6aed804bf1ac57832055dab34483bdcb25567a5b902e5b3c6b85cb7129e8849b',
    'paper_curve/provenance.json': 'fe35a863731ff5394095f5d268a988cb45120a1382db9fd53bc0599e8f98e0cd',
    'initial_condition_runs/ic_250.mat': '2881d6d1e072bc72ee4dc9a7fce1e6f19d1fef810916627e260bb212fe26bfd4',
    'initial_condition_runs/ic_250_wall.csv': '8f720350633759836aef1b2ab39999c1a45799926aaeab2bf6eec48897b0abc0',
    'initial_condition_runs/ic_250_outlet.csv': '63ee91281c3aeabf445eacb622cb285dc4966471fba5073aef420d47e580722b',
    'initial_condition_runs/ic_407.mat': '17c89b6ad4f42a3e132d6118a88449838096a7f09946df831a67a02b2217e4c7',
    'initial_condition_runs/ic_407_wall.csv': '326193481d43a1aaceea3ea724362819dcc03dc9e057ab8d66acf24b86957748',
    'initial_condition_runs/ic_407_outlet.csv': 'bbd6676fc17bb1ff698e6a16a06cf498005b33a2b2de7c38a385095379eabec3',
    'initial_condition_runs/diary.txt': '52dc23cc5a6ef364a823637ca490352bcc8993c8723220d00b5ef2bbdfde4277',
    'a1_summary/offline_96.csv': '85a4a293fb485b056a18c9f7d1c8678da5d6b6be7fc3e90c00ba737e3568bd91',
    'a1_summary/offline_rejection_log.csv': '02192fec31a866091061fd774fd849ed809ccf904d9c7b9a5f29d48554bd2208',
    'a1_summary/representative_matrix.csv': 'e8f5483f818a775f6ba3b291677ba7665fe61e7675ba93bdab48b4e63e70e5d8',
    'a1_summary/selection.json': '67b276437d4d99e9f9ac299aa4c693371c40c1c9ca717b3c2c56afc755c54f91',
    'a1_summary/representative_manifests/T300_fd1p45_one__conservative_source.json': '831b912cc1e2e3e55e7aa4473e2d265cdf626b33cc498bcdb31553aef83ae1e9',
    'a1_summary/representative_manifests/T300_fd1p45_one__optimistic_source.json': '56751250407c0076e87228246164afa9e96d8efc03e798f2419db0533d5aaf5d',
    'a1_summary/representative_manifests/T300_fd1p45_two__legacy_transfer.json': '42dc437c772fa1c41df05aeee6825fedea75192391c7a4bac796e9c8a37713f0',
    'a1_summary/representative_manifests/T300_fd1p45_two__conservative_source.json': 'fbd49c53cd9193c290dc12834925646754dfe5452e0678ced76444d4b819c968',
    'a1_summary/representative_manifests/T300_fd1p45_two__optimistic_source.json': 'a348214506fd94a033fe691bacfdc95a4e399ef2a7733e1f1c9130fec035acd0',
    'a1_summary/representative_manifests/P95_WG_fd1p45_two__legacy_transfer.json': 'ef877873d0905627e044c6c7fa476faea3465a00741131c80eb304d926ca1b46',
    'a1_summary/representative_manifests/P95_WG_fd1p45_two__conservative_source.json': 'dd6d77d1acb72a2128ebe518ab515a02d3a33cf273a437055670875c5609df3e',
    'a1_summary/representative_manifests/P95_WG_fd1p45_two__optimistic_source.json': '704f6eeea3bdcdc562072cbca5efb55fd406832bc7795c441ba34bdefb54c5fb',
    'a1_summary/representative_manifests/APG_fd1p00_two__legacy_transfer.json': 'd53dff519cbf712d3f590d037c09d0c2c6a189c26ac6b5ded53b887a57c6bae5',
    'a1_summary/representative_manifests/APG_fd1p00_two__conservative_source.json': '3dd280cb73d11fc5ddf13d63e0b662d0bfb90156b74552f7580d8f22fcd25f8e',
    'a1_summary/representative_manifests/APG_fd1p00_two__optimistic_source.json': '03e8af11765a71e9a9cdf07c5a28c627ec7311241c0e695c40b9da90c87b2d27',
    'a1_summary/advance_14000.json': 'c94e0d9a43deb2bd42e372367d10a4ed888c676c0fb3b9d6526d8470343f7ae0',
    'a1_summary/source_contract.json': '440d71b5acb37498cd95c0b0c56d4c65c1c8a814cb9ccebb55bafe86be3de5f0',
    'a1_summary/unit_contract.json': 'e64d74514b13671294b966daae693e92672dd1986e85dd35965110d5dc832016',
    'a1_summary/output_hashes.json': 'bbf50497a31e1ab781cb34e2e649fb1e25c99bd41f57cbcf48928836fe3736cc',
    'a1_summary/preparation_summary.json': 'bdcaf29fa0eeee39b26c6717fd75a7c91fde85b692477996330ae25337c6e9f4',
    'a1_summary/batch_500_summary.json': '62354a831fedd5eefe6a7b0703cca381ac8493536e55d6920808369dd9281938',
    'a1_summary/summary_500.json': '2bd40264f1428b91b670d61ee40ba8ac00e9299188db6059767a435c66f86101',
    'a1_summary/batch_14000_summary.json': '4cd1087e8a304f8030d60ec246bf4449e4b6e58cb1c25734402913e9ae9ee987',
    'a1_summary/summary_14000.json': 'e419263d6652c64e5410cdd6b883e80cbfbc7bd0864292621f84c4754925812a',
    'a1_summary/report.md': 'cdf4cfc0c929ca9cdfcfe0c211e862010b7e710749481c63ebb3eb1e448c84bf',
}

README = """# Figure 5.18(d) and radiator A1 evidence

This directory preserves byte-identical completed Figure 5.18(d) digitization,
radiator initial-condition runs, and radiator A1 screening/audit evidence. It
does not promote an equation family, author implementation, parameter package,
SLX, MAT dependency, or property function into the formal model.

paper_reproduced = false
author_implementation_status = not_uniquely_identified
current_equation_family_status = incompatible_with_both_digitized_curves
a1_identifiability = multiple_conditionally_feasible_packages
formal_promotion = false

representative_matrix.csv has 12 fixed roles. selection.json has eligible_count=11.
exactly 11 per-candidate manifests exist. The sole ineligible role
`T300_fd1p45_one__legacy_transfer` was rejected before SLX preparation and
therefore has no per-candidate manifest. Its full parameters and rejection
reasons remain in `representative_matrix.csv`. This is evidence, not a missing-file error.

The `is_original_output` and `is_regenerable` columns in `manifest.csv` record
that publication copied the completed source artifact without reconstruction
and describe the source pipeline, respectively. These names are part of the
manifest schema; they do not grant permission to rerun it. Evidence grades classify the
preserved record; they do not change the negative scientific status above.
"""


def _lstat(path):
    try:
        return Path(path).lstat()
    except FileNotFoundError:
        return None
    except OSError as error:
        raise PublicationError(f"cannot inspect path: {path}: {error}") from error


def _require_regular_file(path, label):
    path = Path(path)
    path_stat = _lstat(path)
    if path_stat is None:
        raise PublicationError(f"{label} is missing: {path}")
    if stat.S_ISLNK(path_stat.st_mode):
        raise PublicationError(f"{label} must not be a symlink: {path}")
    if not stat.S_ISREG(path_stat.st_mode):
        raise PublicationError(f"{label} is not a regular file: {path}")
    return path_stat


def _require_directory(path, label):
    path = Path(path)
    path_stat = _lstat(path)
    if path_stat is None:
        raise PublicationError(f"{label} is missing: {path}")
    if stat.S_ISLNK(path_stat.st_mode):
        raise PublicationError(f"{label} must not be a symlink: {path}")
    if not stat.S_ISDIR(path_stat.st_mode):
        raise PublicationError(f"{label} is not a directory: {path}")
    return path_stat


def _open_regular_file(path):
    path = Path(path)
    before = _require_regular_file(path, "file")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise PublicationError(f"cannot safely open file: {path}: {error}") from error
    opened = os.fstat(descriptor)
    if not stat.S_ISREG(opened.st_mode) or (opened.st_dev, opened.st_ino) != (
        before.st_dev,
        before.st_ino,
    ):
        os.close(descriptor)
        raise PublicationError(f"file changed during safe open: {path}")
    return descriptor, opened


def _read_bytes(path):
    path = Path(path)
    descriptor, opened = _open_regular_file(path)
    chunks = []
    try:
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
    finally:
        os.close(descriptor)
    after = _require_regular_file(path, "file")
    if (after.st_dev, after.st_ino) != (opened.st_dev, opened.st_ino):
        raise PublicationError(f"file changed while reading: {path}")
    data = b"".join(chunks)
    if len(data) != opened.st_size:
        raise PublicationError(f"file size changed while reading: {path}")
    return data


def sha256(path):
    return hashlib.sha256(_read_bytes(path)).hexdigest()


def _hash_and_size(path):
    data = _read_bytes(path)
    return hashlib.sha256(data).hexdigest(), len(data)


def _assert_within(anchor, path):
    anchor = Path(os.path.abspath(os.fspath(anchor)))
    path = Path(os.path.abspath(os.fspath(path)))
    try:
        common = Path(os.path.commonpath((anchor, path)))
    except ValueError as error:
        raise PublicationError(f"destination is outside durable root: {path}") from error
    if common != anchor or path == anchor:
        raise PublicationError(f"destination is outside durable root: {path}")
    return anchor, path


def _validate_parent_chain(anchor, parent, create):
    anchor = Path(os.path.abspath(os.fspath(anchor)))
    parent = Path(os.path.abspath(os.fspath(parent)))
    try:
        relative = parent.relative_to(anchor)
    except ValueError as error:
        raise PublicationError(f"destination parent is outside durable root: {parent}") from error
    components = (anchor,) + tuple(
        anchor.joinpath(*relative.parts[:index])
        for index in range(1, len(relative.parts) + 1)
    )
    for current in components:
        current_stat = _lstat(current)
        if current_stat is None and create and current != anchor:
            try:
                os.mkdir(current)
            except FileExistsError:
                pass
            except OSError as error:
                raise PublicationError(
                    f"cannot create destination directory: {current}: {error}"
                ) from error
            current_stat = _lstat(current)
        if current_stat is None:
            raise PublicationError(f"destination directory is missing: {current}")
        if stat.S_ISLNK(current_stat.st_mode):
            raise PublicationError(f"destination directory is a symlink: {current}")
        if not stat.S_ISDIR(current_stat.st_mode):
            raise PublicationError(f"destination parent is not a directory: {current}")


def _ensure_durable_root():
    root = Path(os.path.abspath(os.fspath(DURABLE_ROOT)))
    existing = root
    missing = []
    while _lstat(existing) is None:
        missing.append(existing)
        if existing.parent == existing:
            raise PublicationError(f"cannot locate durable parent for: {root}")
        existing = existing.parent
    _require_directory(existing, "durable ancestor")
    for path in reversed(missing):
        try:
            os.mkdir(path)
        except FileExistsError:
            pass
        except OSError as error:
            raise PublicationError(f"cannot create durable directory: {path}: {error}") from error
        _require_directory(path, "durable directory")
    _require_directory(root, "durable root")


def _copy_file_contents(source_path, destination_descriptor):
    source_descriptor, _ = _open_regular_file(source_path)
    try:
        while True:
            chunk = os.read(source_descriptor, 1024 * 1024)
            if not chunk:
                break
            while chunk:
                written = os.write(destination_descriptor, chunk)
                if written <= 0:
                    raise OSError("zero-byte write while publishing")
                chunk = chunk[written:]
    finally:
        os.close(source_descriptor)


def _publish_with_writer(dst, expected, writer):
    durable_root, dst = _assert_within(DURABLE_ROOT, dst)
    temporary = dst.with_name(f"{dst.name}.publishing")
    _validate_parent_chain(durable_root, dst.parent, create=True)
    if os.path.lexists(temporary):
        raise PublicationError(f"stale publication file exists: {temporary}")
    destination_stat = _lstat(dst)
    if destination_stat is not None:
        _require_regular_file(dst, "destination file")
        if sha256(dst) != expected:
            raise PublicationError(f"refusing to overwrite nonmatching destination: {dst}")
        return
    if os.path.lexists(dst):
        raise PublicationError(f"destination appeared during publication: {dst}")

    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(temporary, flags, 0o644)
    except OSError as error:
        raise PublicationError(f"cannot create publication staging: {temporary}: {error}") from error
    opened = os.fstat(descriptor)
    identity = (opened.st_dev, opened.st_ino)
    try:
        writer(descriptor)
        os.close(descriptor)
        descriptor = None
        current = _require_regular_file(temporary, "publication file")
        if (current.st_dev, current.st_ino) != identity:
            raise PublicationError(f"publication file was replaced: {temporary}")
        actual = sha256(temporary)
        if actual != expected:
            raise PublicationError(
                f"temporary hash mismatch: {temporary}: expected {expected}, got {actual}"
            )
        _validate_parent_chain(durable_root, dst.parent, create=False)
        current = _require_regular_file(temporary, "publication file")
        if (current.st_dev, current.st_ino) != identity:
            raise PublicationError(f"publication file was replaced: {temporary}")
        if os.path.lexists(dst):
            raise PublicationError(f"destination appeared during publication: {dst}")
        os.replace(temporary, dst)
    except Exception:
        if descriptor is not None:
            os.close(descriptor)
        # Failed staging is intentionally retained for audit and blocks retry.
        raise


def publish_file(src, dst, expected):
    src = Path(src)
    _require_regular_file(src, "source file")
    actual = sha256(src)
    if actual != expected:
        raise PublicationError(
            f"source hash mismatch: {src}: expected {expected}, got {actual}"
        )
    _publish_with_writer(dst, expected, lambda descriptor: _copy_file_contents(src, descriptor))


def _publish_bytes(dst, data):
    expected = hashlib.sha256(data).hexdigest()

    def writer(descriptor):
        remaining = data
        while remaining:
            written = os.write(descriptor, remaining)
            if written <= 0:
                raise OSError("zero-byte write while publishing generated content")
            remaining = remaining[written:]

    _publish_with_writer(dst, expected, writer)


def _discover_representative_manifests():
    representatives = ROOT / "tmp/radiator_A1_20260830_A2/representatives"
    _require_directory(representatives, "representatives source directory")
    discovered = []
    try:
        entries = list(os.scandir(representatives))
    except OSError as error:
        raise PublicationError(f"cannot enumerate representative manifests: {error}") from error
    for entry in entries:
        if entry.is_symlink():
            raise PublicationError(f"representative source entry is a symlink: {entry.path}")
        if not entry.is_dir(follow_symlinks=False):
            continue
        manifest = Path(entry.path) / "parameter_manifest.json"
        if _lstat(manifest) is not None:
            _require_regular_file(manifest, "candidate parameter manifest")
            discovered.append(entry.name)
    discovered.sort()
    expected = sorted(set(EXPECTED_REPRESENTATIVE_IDS) - EXPECTED_INELIGIBLE_IDS)
    if discovered != expected:
        raise PublicationError(
            f"representative manifest source set mismatch: expected {expected}, got {discovered}"
        )


def source_entries():
    _discover_representative_manifests()
    entries = []
    for spec in SOURCE_SPECS:
        source_path = ROOT / spec["source_path"]
        digest, byte_count = _hash_and_size(source_path)
        expected_digest = EXPECTED_SHA256[spec["durable_path"]]
        expected_size = byte_count
        if (digest, byte_count) != (expected_digest, expected_size):
            raise PublicationError(f"source differs from immutable contract: {source_path}")
        entry = dict(spec)
        entry["byte_count"] = str(expected_size)
        entry["sha256"] = expected_digest
        entries.append(entry)
    if len(entries) != 34:
        raise PublicationError(f"source map must contain 34 files, got {len(entries)}")
    return entries


def _manifest_bytes(entries):
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=MANIFEST_FIELDS, lineterminator="\n")
    writer.writeheader()
    for entry in entries:
        writer.writerow({field: entry[field] for field in MANIFEST_FIELDS})
    return stream.getvalue().encode("utf-8")


def _verify_entry_files(entries):
    for entry in entries:
        path = DURABLE_ROOT / entry["durable_path"]
        anchor, path = _assert_within(DURABLE_ROOT, path)
        _validate_parent_chain(anchor, path.parent, create=False)
        _require_regular_file(path, "published evidence")
        digest, byte_count = _hash_and_size(path)
        if digest != entry["sha256"]:
            raise PublicationError(
                f"published hash mismatch: {path}: expected {entry['sha256']}, got {digest}"
            )
        if byte_count != int(entry["byte_count"]):
            raise PublicationError(
                f"published byte count mismatch: {path}: expected {entry['byte_count']}, got {byte_count}"
            )


def _read_csv(relative):
    data = _read_bytes(DURABLE_ROOT / relative)
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise PublicationError(f"durable CSV is not UTF-8: {relative}") from error
    return list(csv.DictReader(io.StringIO(text, newline="")))


def _read_json(relative):
    data = _read_bytes(DURABLE_ROOT / relative)
    try:
        return json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise PublicationError(f"invalid durable JSON: {relative}: {error}") from error


def _read_text(relative):
    data = _read_bytes(DURABLE_ROOT / relative)
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise PublicationError(f"durable text is not UTF-8: {relative}") from error


def _walk_durable_files():
    _require_directory(DURABLE_ROOT, "durable root")
    files = []

    def visit(directory):
        try:
            entries = sorted(os.scandir(directory), key=lambda entry: entry.name)
        except OSError as error:
            raise PublicationError(f"cannot inventory durable tree: {directory}: {error}") from error
        for entry in entries:
            path = Path(entry.path)
            if entry.is_symlink():
                raise PublicationError(f"durable tree contains symlink: {path}")
            if entry.is_dir(follow_symlinks=False):
                visit(path)
            elif entry.is_file(follow_symlinks=False):
                files.append(path.relative_to(DURABLE_ROOT).as_posix())
            else:
                raise PublicationError(f"durable tree contains nonregular entry: {path}")

    visit(DURABLE_ROOT)
    return files


def _parse_manifest():
    rows = _read_csv("manifest.csv")
    if len(rows) != 34:
        raise PublicationError(f"manifest must contain 34 rows, got {len(rows)}")
    if set(EXPECTED_SHA256) != {spec["durable_path"] for spec in SOURCE_SPECS}:
        raise PublicationError("immutable hash contract keys mismatch")
    expected_pairs = [
        (spec["source_path"], spec["durable_path"])
        for spec in SOURCE_SPECS
    ]
    actual_pairs = [(row["source_path"], row["durable_path"]) for row in rows]
    if actual_pairs != expected_pairs:
        raise PublicationError("manifest source-to-durable map or row order mismatch")
    for row, spec in zip(rows, SOURCE_SPECS):
        if set(row) != set(MANIFEST_FIELDS):
            raise PublicationError("manifest field set mismatch")
        for field in (
            "purpose",
            "is_original_output",
            "is_regenerable",
            "evidence_grade",
        ):
            if row[field] != spec[field]:
                raise PublicationError(f"manifest metadata mismatch for {row['durable_path']}")
        try:
            if int(row["byte_count"]) < 0:
                raise ValueError
        except ValueError as error:
            raise PublicationError(f"invalid manifest byte count: {row['byte_count']}") from error
        if len(row["sha256"]) != 64 or any(
            character not in "0123456789abcdef" for character in row["sha256"]
        ):
            raise PublicationError(f"invalid manifest SHA256: {row['sha256']}")
        expected_digest = EXPECTED_SHA256.get(row["durable_path"])
        if row["sha256"] != expected_digest:
            raise PublicationError(f"manifest immutable contract mismatch for {row['durable_path']}")
        durable = PurePosixPath(row["durable_path"])
        if durable.is_absolute() or ".." in durable.parts:
            raise PublicationError(f"invalid durable manifest path: {durable}")
    return rows


def _require_negative_status(records, label):
    def is_false(value):
        return value is False or value == "false"

    for record in records:
        if not is_false(record.get("paper_reproduced")):
            raise PublicationError(f"{label} contains nonnegative paper status")
        if not is_false(record.get("formal_promotion")):
            raise PublicationError(f"{label} contains nonnegative promotion status")


def validate_representative_semantics(representatives, selection, candidate_manifests):
    ids = [row.get("candidate_id") for row in representatives]
    if len(ids) != len(set(ids)) or set(ids) != set(EXPECTED_REPRESENTATIVE_IDS):
        raise PublicationError("representative matrix identities mismatch")
    flags = {}
    for row in representatives:
        value = row.get("eligible_for_slx")
        if value not in ("true", "false"):
            raise PublicationError("eligibility must be literal true/false")
        flags[row["candidate_id"]] = value == "true"
    if {k for k,v in flags.items() if not v} != EXPECTED_INELIGIBLE_IDS:
        raise PublicationError("ineligible identity mismatch")
    manifest_ids = [m.get("candidate_id") for m in candidate_manifests]
    if len(manifest_ids) != len(set(manifest_ids)) or set(manifest_ids) != set(EXPECTED_REPRESENTATIVE_IDS) - EXPECTED_INELIGIBLE_IDS:
        raise PublicationError("candidate manifest identities mismatch")
    if any(m.get("eligible_for_slx") is not True for m in candidate_manifests):
        raise PublicationError("candidate manifest eligibility mismatch")
    if not isinstance(selection.get("eligible_candidate_ids"), list) or set(selection.get("eligible_candidate_ids")) != set(manifest_ids):
        raise PublicationError("selection and candidate identities differ")
    if selection.get("eligible_count") != len(manifest_ids):
        raise PublicationError("selection eligible count mismatch")

def verify_published():
    manifest_rows = _parse_manifest()
    _verify_entry_files(manifest_rows)
    expected_files = sorted(
        [spec["durable_path"] for spec in SOURCE_SPECS]
        + ["README.md", "manifest.csv"]
    )
    actual_files = sorted(_walk_durable_files())
    if actual_files != expected_files:
        raise PublicationError(
            f"durable file inventory mismatch: expected {expected_files}, got {actual_files}"
        )
    ic_mat_paths = sorted(
        path for path in actual_files
        if path.startswith("initial_condition_runs/") and path.endswith(".mat")
    )
    if ic_mat_paths != ["initial_condition_runs/ic_250.mat", "initial_condition_runs/ic_407.mat"]:
        raise PublicationError(f"initial-condition MAT identity mismatch: {ic_mat_paths}")

    readme = _read_text("README.md")
    if readme.encode("utf-8") != README.encode("utf-8"):
        raise PublicationError("README content does not match deterministic publisher template")
    machine_lines = (
        "paper_reproduced = false",
        "author_implementation_status = not_uniquely_identified",
        "current_equation_family_status = incompatible_with_both_digitized_curves",
        "a1_identifiability = multiple_conditionally_feasible_packages",
        "formal_promotion = false",
    )
    readme_lines = readme.splitlines()
    if any(readme_lines.count(line) != 1 for line in machine_lines):
        raise PublicationError("README machine-readable status lines are missing or duplicated")
    schema_statement = (
        "The `is_original_output` and `is_regenerable` columns in `manifest.csv`"
    )
    if schema_statement not in readme or "`original_output`" in readme or "`regenerable`" in readme:
        raise PublicationError("README manifest schema statement mismatch")

    paper_points = _read_csv("paper_curve/points.csv")
    offline_rows = _read_csv("a1_summary/offline_96.csv")
    representatives = _read_csv("a1_summary/representative_matrix.csv")
    selection = _read_json("a1_summary/selection.json")
    manifest_paths = sorted(
        spec["durable_path"]
        for spec in SOURCE_SPECS
        if spec["durable_path"].startswith("a1_summary/representative_manifests/")
    )
    manifest_candidate_ids = []
    candidate_manifests = []
    for relative in manifest_paths:
        candidate_manifest = _read_json(relative)
        candidate_id = Path(relative).stem
        if candidate_manifest.get("candidate_id") != candidate_id:
            raise PublicationError(f"candidate manifest identity mismatch: {relative}")
        if candidate_manifest.get("eligible_for_slx") is not True:
            raise PublicationError(f"candidate manifest is not eligible: {relative}")
        manifest_candidate_ids.append(candidate_id)
        candidate_manifests.append(candidate_manifest)

    validate_representative_semantics(representatives, selection, candidate_manifests)
    ineligible_ids = [
        row["candidate_id"]
        for row in representatives
        if row.get("eligible_for_slx", "").lower() == "false"
        and row["candidate_id"] not in manifest_candidate_ids
    ]
    batch_500 = _read_json("a1_summary/batch_500_summary.json")
    batch_14000 = _read_json("a1_summary/batch_14000_summary.json")
    summary_500 = _read_json("a1_summary/summary_500.json")
    summary_14000 = _read_json("a1_summary/summary_14000.json")
    _require_negative_status(representatives, "representative matrix")
    _require_negative_status(candidate_manifests, "candidate manifests")
    _require_negative_status(summary_500.get("records", []), "500-second summary")
    _require_negative_status(summary_14000.get("records", []), "14000-second summary")
    if selection.get("paper_reproduced") is not False:
        raise PublicationError("selection paper status is not false")
    if selection.get("formal_promotion") is not False:
        raise PublicationError("selection promotion status is not false")

    report_text = _read_text("a1_summary/report.md")
    identifiability = "multiple_conditionally_feasible_packages"
    if f"可识别性：`{identifiability}`" not in report_text:
        raise PublicationError("A1 identifiability statement is missing from durable report")

    report = {
        "paper_point_count": len(paper_points),
        "ic_mat_count": sum(
            path.startswith("initial_condition_runs/") and path.endswith(".mat")
            for path in _walk_durable_files()
        ),
        "offline_row_count": len(offline_rows),
        "representative_count": len(representatives),
        "eligible_count": selection.get("eligible_count"),
        "representative_manifest_count": len(manifest_candidate_ids),
        "ineligible_without_manifest": ineligible_ids,
        "stage_500_passed": sum(record.get("success") is True for record in batch_500),
        "stage_14000_passed": sum(
            record.get("success") is True for record in batch_14000
        ),
        "a1_identifiability": identifiability,
        "paper_reproduced": False,
        "formal_promotion": False,
    }
    expected = {
        "paper_point_count": 12,
        "ic_mat_count": 2,
        "offline_row_count": 96,
        "representative_count": 12,
        "eligible_count": 11,
        "representative_manifest_count": 11,
        "ineligible_without_manifest": ["T300_fd1p45_one__legacy_transfer"],
        "stage_500_passed": 3,
        "stage_14000_passed": 3,
        "a1_identifiability": "multiple_conditionally_feasible_packages",
        "paper_reproduced": False,
        "formal_promotion": False,
    }
    if report != expected:
        raise PublicationError(f"durable evidence contract mismatch: {report}")
    return report


def publish_all():
    _ensure_durable_root()
    entries = source_entries()
    for entry in entries:
        publish_file(
            ROOT / entry["source_path"],
            DURABLE_ROOT / entry["durable_path"],
            entry["sha256"],
        )
    _verify_entry_files(entries)
    _publish_bytes(DURABLE_ROOT / "README.md", README.encode("utf-8"))
    _publish_bytes(DURABLE_ROOT / "manifest.csv", _manifest_bytes(entries))
    return verify_published()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    report = verify_published() if args.verify_only else publish_all()
    print(
        "FIG518D_EVIDENCE_PASS; "
        f"PAPER_POINTS={report['paper_point_count']}; "
        f"A1_14000_PASS={report['stage_14000_passed']}"
    )


if __name__ == "__main__":
    main()
