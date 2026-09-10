"""Create, verify and restore a local project snapshot, including ignored evidence.

No model execution. Requires Python standard library and Git. Existing recovery
destinations and archive files are never overwritten. Linked worktrees restore
as evidence directories, not as registered Git worktrees.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import zipfile


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def target_path(root, relative):
    p = PurePosixPath(relative)
    if p.is_absolute() or '..' in p.parts or '.git' in p.parts or not p.parts:
        raise ValueError('Unsafe snapshot path: ' + relative)
    result = root.joinpath(*p.parts)
    if not result.resolve().is_relative_to(root.resolve()):
        raise ValueError('Path escapes recovery directory')
    return result


def create(root, folder):
    folder.mkdir(parents=True, exist_ok=True)
    for name in ['project.zip', 'history.bundle', 'manifest.json']:
        if (folder / name).exists():
            raise FileExistsError(folder / name)
    head = git(root, 'rev-parse', 'HEAD')
    branch = git(root, 'branch', '--show-current')
    git(root, 'bundle', 'create', str(folder / 'history.bundle'), '--all')
    git(root, 'bundle', 'verify', str(folder / 'history.bundle'))
    entries, directories = [], []
    with zipfile.ZipFile(folder / 'project.zip', 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=3) as z:
        for d, ds, fs in os.walk(root):
            ds[:] = sorted(x for x in ds if x != '.git' and not (Path(d) / x).resolve().is_relative_to(folder.resolve()))
            parent = Path(d)
            if parent != root:
                directories.append(parent.relative_to(root).as_posix())
            for name in sorted(fs):
                p = parent / name
                if name == '.git' or p.resolve().is_relative_to(folder.resolve()):
                    continue
                if p.is_symlink():
                    raise ValueError('Review symlink before packaging: ' + str(p))
                relative = p.relative_to(root).as_posix()
                target_path(root, relative)
                stat = p.stat()
                digest = sha(p)
                z.write(p, relative)
                if sha(p) != digest:
                    raise RuntimeError('File changed while packaging: ' + relative)
                entries.append(dict(path=relative, sha256=digest, size=stat.st_size,
                                    mode=stat.st_mode & 0o777, mtime_ns=stat.st_mtime_ns))
    manifest = dict(source_root=str(root), head=head, branch=branch, entries=entries,
                    directories=directories, excluded=['Git administration (.git)', str(folder.relative_to(root))],
                    external_worktrees=git(root, 'worktree', 'list', '--porcelain'),
                    project_zip_sha256=sha(folder / 'project.zip'), history_bundle_sha256=sha(folder / 'history.bundle'))
    (folder / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    return verify(folder)


def verify(folder):
    m = json.loads((folder / 'manifest.json').read_text())
    if sha(folder / 'project.zip') != m['project_zip_sha256'] or sha(folder / 'history.bundle') != m['history_bundle_sha256']:
        raise RuntimeError('Package digest mismatch')
    with zipfile.ZipFile(folder / 'project.zip') as z:
        names = [e['path'] for e in m['entries']]
        if len(set(names)) != len(names) or set(names) != set(z.namelist()) or len(names) != len(z.namelist()):
            raise RuntimeError('Archive entries mismatch')
        for e in m['entries']:
            target_path(Path('/snapshot-check'), e['path'])
            with z.open(e['path']) as stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            if digest != e['sha256'] or z.getinfo(e['path']).file_size != e['size']:
                raise RuntimeError('Entry mismatch: ' + e['path'])
    return dict(files_verified=len(m['entries']), archive_bytes=(folder / 'project.zip').stat().st_size)


def restore(folder, destination):
    if destination.exists():
        raise FileExistsError('Restore to a NEW directory: ' + str(destination))
    result = verify(folder)
    m = json.loads((folder / 'manifest.json').read_text())
    # Restore the index/history without checkout so tracked deletions remain absent.
    subprocess.run(['git', 'clone', '--no-checkout', str(folder / 'history.bundle'), str(destination)], check=True, capture_output=True)
    git(destination, 'symbolic-ref', 'HEAD', 'refs/heads/codex/recovered-workspace')
    git(destination, 'reset', '--mixed', m['head'])
    with zipfile.ZipFile(folder / 'project.zip') as z:
        for directory in m['directories']:
            target_path(destination, directory).mkdir(parents=True, exist_ok=True)
        for e in m['entries']:
            p = target_path(destination, e['path'])
            p.parent.mkdir(parents=True, exist_ok=True)
            with p.open('xb') as out, z.open(e['path']) as stream:
                while block := stream.read(1024 * 1024):
                    out.write(block)
            p.chmod(e['mode'])
            os.utime(p, ns=(e['mtime_ns'], e['mtime_ns']))
            if sha(p) != e['sha256']:
                raise RuntimeError('Restored file mismatch: ' + e['path'])
    # Keep the recovery kit reachable by the project's relative documentation links.
    kit = destination / m['excluded'][1]
    target_path(destination, m['excluded'][1])
    shutil.copytree(folder, kit)
    return dict(**result, restored_to=str(destination), restored_head=git(destination, 'rev-parse', 'HEAD'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['create', 'verify', 'restore'])
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--destination', type=Path)
    a = parser.parse_args()
    folder = a.package.resolve()
    if a.action == 'create':
        result = create(a.root.resolve(), folder)
    elif a.action == 'verify':
        result = verify(folder)
    else:
        if a.destination is None:
            parser.error('--destination is required for restore')
        result = restore(folder, a.destination.resolve())
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
