#!/usr/bin/env python3
import argparse
import hashlib
import os
import stat
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HISTORICAL = ROOT / "tmp/steady53_curves_20260828/source_f8bcd83"
BASELINE = ROOT / "data/provenance/baselines/f8bcd83"
STATUS = {
    "source_commit": "f8bcd833e816eb681982b7dd04364e4b856948e3",
    "paper_reproduced": False,
    "formal_promotion": False,
}
EXPECTED_SHA256 = {
    "runtime/HeXe_property_simulink.m": "2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2",
    "runtime/Lithium_property_simulink.m": "666a3a9d7bcb45e0e80afca4bd30e02bd19098ce72cc56bfe9a5f528c67b4c4f",
    "runtime/hexe_compressor_lookup.mat": "f9c85bc1ae831333fac5f868f15a6f82ea1c1716ee17f23dfb301f4618c9f579",
    "runtime/radiator_table.mat": "3f6e8a08f6ec9253b84d07f8eff11d2b093f785bafcfde515f2c6af4ec263304",
    "runtime/turbine_table1.mat": "10e72638374c530e2032d9bfe39b060d4181b0467bf69e03196efa0b90c4971d",
    "runtime/turbine_table2.mat": "6ff94cce373b67a143e9a992ec693ef17a910440eb4218cdf796543ba48c8a38",
    "runtime/start.m": "0de14c8d7e56e22871800f0c84f6eccd5b00e34ae7c20a3501752f45a09effec",
    "runtime/sys_param_rad_fixed.m": "bbdcf30dcd2fd7859092af0d85a79ed5dabc6da6c298f1d064ed11d612f30d5b",
    "runtime/paper54_constants.m": "545e9b7653b4a47759e746e33a52a184e69c1455911929ce096d1a6eb6558345",
    "runtime/tests/steady53/create_component_harness.m": "0f536ffaff9345e5cc85af37bdfa6a385db0e54bd7f0adcedbd81b95fdcd2dd0",
    "runtime/tests/steady53/steady53_component_boundaries.m": "8e2092ef2a9a183a7e4b3cd04fc05949d3648de873833391f262eed13f72ed26",
    "runtime/tests/steady53/steady53_signal_manifest.m": "7807290de1b02cf4c2e513976a8c95e5780201ce5fdae0bdd97679b0f2e835bd",
    "runtime/tests/steady53/reset_steady53_property_warning_state.m": "04f1be8b20c3b48f17e468c1dd15a282e15ea08f14f255f5a6f3d269f2d44ff0",
    "runtime/tests/steady53/run_steady53_case.m": "6ec6f09c9d6ef32520b28248588d5ba0b31f3cf99acd0f6b0bc5bdff7f45e79a",
}


class PublicationError(RuntimeError):
    pass


def _lstat(path):
    path = Path(path)
    try:
        return path.lstat()
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


def _open_regular_file(path):
    path = Path(path)
    before = _require_regular_file(path, "file")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise PublicationError(f"cannot safely open regular file: {path}: {error}") from error
    opened = os.fstat(descriptor)
    if not stat.S_ISREG(opened.st_mode) or (opened.st_dev, opened.st_ino) != (
        before.st_dev,
        before.st_ino,
    ):
        os.close(descriptor)
        raise PublicationError(f"file changed during safe open: {path}")
    return descriptor, opened


def sha256(path):
    digest = hashlib.sha256()
    path = Path(path)
    descriptor, opened = _open_regular_file(path)
    try:
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    finally:
        os.close(descriptor)
    after = _require_regular_file(path, "file")
    if (after.st_dev, after.st_ino) != (opened.st_dev, opened.st_ino):
        raise PublicationError(f"file changed while hashing: {path}")
    return digest.hexdigest()


def destination(relative):
    path = BASELINE / relative
    _assert_within(BASELINE, path)
    return path


def source(relative):
    relative = str(relative)
    prefix = "runtime/"
    if not relative.startswith(prefix):
        raise PublicationError(f"runtime path must start with {prefix!r}: {relative}")
    return HISTORICAL / relative[len(prefix) :]


def _assert_within(anchor, path):
    anchor = Path(os.path.abspath(os.fspath(anchor)))
    path = Path(os.path.abspath(os.fspath(path)))
    try:
        common = Path(os.path.commonpath((anchor, path)))
    except ValueError as error:
        raise PublicationError(f"destination is outside baseline: {path}") from error
    if common != anchor or path == anchor:
        raise PublicationError(f"destination is outside baseline: {path}")
    return anchor, path


def _validate_parent_chain(anchor, parent, create):
    anchor = Path(os.path.abspath(os.fspath(anchor)))
    parent = Path(os.path.abspath(os.fspath(parent)))
    try:
        relative_parent = parent.relative_to(anchor)
    except ValueError as error:
        raise PublicationError(f"destination parent is outside baseline: {parent}") from error

    current = anchor
    components = (current,) + tuple(
        anchor.joinpath(*relative_parent.parts[:index])
        for index in range(1, len(relative_parent.parts) + 1)
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
            raise PublicationError(
                f"destination directory must not be a symlink: {current}"
            )
        if not stat.S_ISDIR(current_stat.st_mode):
            raise PublicationError(f"destination parent is not a directory: {current}")


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


def _same_file_identity(path_stat, identity):
    return path_stat is not None and stat.S_ISREG(path_stat.st_mode) and (
        path_stat.st_dev,
        path_stat.st_ino,
    ) == identity


def _cleanup_owned_temporary(path, identity):
    path_stat = _lstat(path)
    if not _same_file_identity(path_stat, identity):
        return
    try:
        os.unlink(path)
    except OSError:
        pass


def publish_file(src, dst, expected):
    src = Path(src)
    baseline, dst = _assert_within(BASELINE, dst)
    temporary = dst.with_name(f"{dst.name}.publishing")

    _require_regular_file(src, "source file")
    actual_source = sha256(src)
    if actual_source != expected:
        raise PublicationError(
            f"source hash mismatch: {src}: expected {expected}, got {actual_source}"
        )
    _validate_parent_chain(baseline, dst.parent, create=True)
    if os.path.lexists(temporary):
        raise PublicationError(f"stale publication file exists: {temporary}")
    destination_stat = _lstat(dst)
    if destination_stat is not None:
        _require_regular_file(dst, "destination file")
        if sha256(dst) != expected:
            raise PublicationError(f"refusing to overwrite nonmatching destination: {dst}")
        return

    if os.path.lexists(temporary):
        raise PublicationError(f"stale publication file exists: {temporary}")
    if os.path.lexists(dst):
        raise PublicationError(f"destination appeared during publication: {dst}")

    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    try:
        temporary_descriptor = os.open(temporary, flags, 0o644)
    except OSError as error:
        raise PublicationError(
            f"cannot exclusively create publication file: {temporary}: {error}"
        ) from error
    temporary_stat = os.fstat(temporary_descriptor)
    temporary_identity = (temporary_stat.st_dev, temporary_stat.st_ino)

    try:
        _copy_file_contents(src, temporary_descriptor)
        os.close(temporary_descriptor)
        temporary_descriptor = None
        current_temporary = _require_regular_file(temporary, "publication file")
        if not _same_file_identity(current_temporary, temporary_identity):
            raise PublicationError(f"publication file was replaced: {temporary}")
        actual_temporary = sha256(temporary)
        if actual_temporary != expected:
            raise PublicationError(
                f"temporary hash mismatch: {temporary}: expected {expected}, got {actual_temporary}"
            )
        _validate_parent_chain(baseline, dst.parent, create=False)
        current_temporary = _require_regular_file(temporary, "publication file")
        if not _same_file_identity(current_temporary, temporary_identity):
            raise PublicationError(f"publication file was replaced: {temporary}")
        if os.path.lexists(dst):
            raise PublicationError(f"destination appeared during publication: {dst}")
        os.replace(temporary, dst)
    except Exception:
        if temporary_descriptor is not None:
            os.close(temporary_descriptor)
        _cleanup_owned_temporary(temporary, temporary_identity)
        raise


def verify_tree(root=ROOT):
    root = Path(root)
    anchor = BASELINE if root == ROOT else root
    for relative, expected in EXPECTED_SHA256.items():
        path = destination(relative) if root == ROOT else root / relative
        anchor_path, path = _assert_within(anchor, path)
        _validate_parent_chain(anchor_path, path.parent, create=False)
        _require_regular_file(path, "published file")
        actual = sha256(path)
        if actual != expected:
            raise PublicationError(
                f"published hash mismatch: {path}: expected {expected}, got {actual}"
            )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()

    if not args.verify_only:
        for relative, expected in EXPECTED_SHA256.items():
            publish_file(source(relative), destination(relative), expected)
    verify_tree()
    print("F8BCD83_RUNTIME_PASS; FILES=14; PAPER_REPRODUCED=false")


if __name__ == "__main__":
    main()
