"""Read-only project navigation and saved-evidence identity checks; no simulation."""
from pathlib import Path
import csv
import hashlib
import json
import re


def sha(p):
    with p.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def audit(root):
    links = 0
    for document in [root / 'README.md', *(root / 'docs').rglob('*.md'), root / 'sources/README.md']:
        text = document.read_text()
        for target in re.findall(r'\[[^\]]*\]\((<[^>]*>|[^\n]*?)\)', text):
            target = target.strip('<>')
            if '://' in target or target.startswith('#'):
                continue
            target = re.sub(r':\d+(?:-\d+)?$', '', target.split('#')[0])
            if Path(target).is_absolute():
                raise AssertionError('Absolute navigation link: ' + str(document))
            if not (document.parent / target).exists():
                raise AssertionError('Missing navigation target: ' + str(document) + ': ' + target)
            links += 1
    models = list(csv.DictReader((root / 'docs/model_inventory.tsv').open(), delimiter='\t'))
    for e in models:
        if sha(root / e['relative_path']) != e['sha256']:
            raise AssertionError('Model identity changed: ' + e['relative_path'])
    identities = ['tmp/reactor_shared_heat_20260906/input_identity.json',
                  'tmp/fixed_protocol_prefix_20260906/input_identity.json',
                  'tmp/reactor_thermal_constraints_20260906/protected_before.json']
    checked = 0
    for source in identities:
        records = json.loads((root / source).read_text())
        roots = [str(Path(k).parent) for k in records if k.endswith('/final_steady_24a.slx')]
        old_root = Path(min(roots, key=len))
        for absolute, digest in records.items():
            relative = Path(absolute).relative_to(old_root)
            if sha(root / relative) != digest:
                raise AssertionError('Saved input identity changed: ' + str(relative))
            checked += 1
    baseline = root / '.worktrees/rotating-map-candidate-a/tmp/final_steady_speed55090_formal_20260902'
    status = json.loads((baseline / 'run_status.json').read_text())
    if status['success'] is not True or status['tFinal_s'] != 14000:
        raise AssertionError('Saved 14000-second status differs')
    if status['modelHashBefore'] != sha(root / 'final_steady_24a.slx') or status['modelHashAfter'] != status['modelHashBefore']:
        raise AssertionError('Baseline model identity mismatch')
    for name in ['result.mat', 'signals.csv']:
        if not (baseline / name).is_file():
            raise AssertionError('Baseline result missing')
    for path in ['tmp/reactor_shared_heat_20260906/run_500/status.json',
                 'tmp/fixed_protocol_prefix_20260906/run_500/status.json',
                 'tmp/fixed_protocol_prefix_20260906/run_1000/status.json']:
        if json.loads((root / path).read_text())['success'] is not True:
            raise AssertionError('Saved short-run status differs: ' + path)
    return dict(valid_navigation_links=links, model_hashes_verified=len(models),
                saved_input_hashes_verified=checked, saved_run_statuses_checked=4,
                historical_absolute_paths='resolved relative to the explicitly recorded source root; original JSON unchanged',
                new_simulations=0, paper_acceptance=False)


if __name__ == '__main__':
    print(json.dumps(audit(Path(__file__).resolve().parents[2]), ensure_ascii=False))
