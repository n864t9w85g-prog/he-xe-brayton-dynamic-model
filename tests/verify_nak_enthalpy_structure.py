#!/usr/bin/env python3
"""Independent read-only structural and protected-file audit of the candidate."""
import argparse
import csv
import json
from pathlib import Path

from verify_precooler_boundary_diagnostic import semantic_inventory
from verify_tac_power_sources import ROOT, sha


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('candidate_root', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    root = args.candidate_root.resolve()
    assert root.is_relative_to(ROOT / 'tmp')
    source = ROOT / 'tmp/steady53_curves_20260828/source_f8bcd83/final_steady_24a.slx'
    candidate = root / 'nak_enthalpy_candidate.slx'
    audit_path = root / 'patch_audit.json'
    audit = json.loads(audit_path.read_text())
    assert sha(source) == '0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391'
    assert sha(candidate) == audit['candidate_sha256']
    assert audit['before']['settings'] == audit['after']['settings']

    before = semantic_inventory(source, 'rediator')
    after = semantic_inventory(candidate, 'rediator')
    before_other_blocks = {key: value for key, value in before['blocks'].items()
                           if key != 'Tho' and not key.startswith('Tho/')}
    after_other_blocks = {key: value for key, value in after['blocks'].items()
                          if key != 'Tho' and not key.startswith('Tho/')}
    assert before_other_blocks == after_other_blocks
    assert before['blocks']['Tho'][0] == 'Fcn'
    assert after['blocks']['Tho'][0] == 'SubSystem'
    assert after['blocks']['Tho'][1]['SFBlockType'] == 'MATLAB Function'

    before_external_edges = [edge for edge in before['edges']
                             if not edge[0].startswith('Tho/') and not edge[1].startswith('Tho/')]
    after_external_edges = [edge for edge in after['edges']
                            if not edge[0].startswith('Tho/') and not edge[1].startswith('Tho/')]
    assert before_external_edges == after_external_edges
    before_other_scripts = {key: value for key, value in before['scripts'].items() if key != 'Tho'}
    after_other_scripts = {key: value for key, value in after['scripts'].items() if key != 'Tho'}
    assert before_other_scripts == after_other_scripts
    candidate_script = after['scripts']['Tho']
    assert 'nak_enthalpy_outlet' in candidate_script
    assert 'for k = 1:60' in candidate_script
    assert '1.509e-10*Tin^4/4' in candidate_script

    manifest_path = ROOT / 'tmp/tp7d213f64_7fad_4bfa_b722_0771b21d9640/protected_after.csv'
    protected = list(csv.DictReader(manifest_path.open()))
    assert len(protected) == 34
    for row in protected:
        assert sha(row['paths']) == row['hashes'], row['paths']

    result = {
        'status': 'PASS',
        'scope': 'Read-only structural and protected-file audit; no paper acceptance',
        'source_model': str(source),
        'source_sha256': sha(source),
        'candidate_model': str(candidate),
        'candidate_sha256': sha(candidate),
        'patch_audit_sha256': sha(audit_path),
        'unchanged_radiator_blocks_excluding_Tho_subtree': len(before_other_blocks),
        'unchanged_external_radiator_edges': len(before_external_edges),
        'unchanged_existing_radiator_chart_scripts': len(before_other_scripts),
        'replaced_block': 'rediator/Tho',
        'before_block_type': before['blocks']['Tho'][0],
        'after_block_type': after['blocks']['Tho'][0],
        'solver_settings_unchanged': True,
        'protected_file_count': len(protected),
        'protected_manifest_sha256': sha(manifest_path),
        'verifier_sha256': sha(__file__),
        'formal_mutations': False,
    }
    output = root / 'independent_structure_verification.json'
    if args.verify_only:
        assert json.loads(output.read_text()) == result
    else:
        with output.open('x') as stream:
            json.dump(result, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
