#!/usr/bin/env python3
"""Record model, git and primary-report evidence for the current NaK inputs."""
import argparse
import json
import subprocess
from pathlib import Path

from verify_precooler_boundary_diagnostic import nak_cp, semantic_inventory
from verify_tac_power_sources import ROOT, sha


def iaea_cp_na(t):
    return 1000 * (38.12 - 0.069e6/t**2 - 19.493e-3*t + 10.24e-6*t**2) / 22.99


def iaea_cp_k(t):
    return 1000 * (39.288 - 0.086e6/t**2 - 24.334e-3*t + 15.863e-6*t**2) / 39.098


def iaea_cp_nak(t):
    return 0.22 * iaea_cp_na(t) + 0.78 * iaea_cp_k(t)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('output_directory', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    output_directory = args.output_directory.resolve()
    assert output_directory.is_relative_to(ROOT / 'tmp') and output_directory.is_dir()

    source = ROOT / 'tmp/steady53_curves_20260828/source_f8bcd83/final_steady_24a.slx'
    radiator = semantic_inventory(source, 'rediator')
    active_script = radiator['scripts']['MATLAB Function']
    assert '1.061 - 3.694e-4.*T + 4.615e-8.*T.^2 + 1.509e-10.*T.^3' in active_script

    sibling = ROOT.parent / '不接入转子稳态模型_副本'
    commit = '294b1c1b88cae2ac5acd6064432f316c3be7abf5'
    git_text = subprocess.run(
        ['git', '-C', str(sibling), 'show', commit, '--',
         'tests/steady53/steady53_component_boundaries.m'],
        check=True, capture_output=True, text=True).stdout
    assert '[360.10 6.95 663.63 0.676e6 11.97]' in git_text
    assert 'Approved project coolant mass-flow boundary; not thesis direct' in git_text
    assert '❓ project boundary' in git_text

    iaea_pdf = ROOT / 'tmp/nak_provenance_20260829/IAEA-THPH_web.pdf'
    tang_pdf = ROOT / 'Design of closed Brayton cycle power generation system for megawatt-scale space nuclear reactor.pdf'
    screenshots = [
        ROOT / 'tmp/nak_provenance_20260829/iaea-093.png',
        ROOT / 'tmp/nak_provenance_20260829/iaea-096.png',
        ROOT / 'tmp/nak_provenance_20260829/iaea-097.png',
        ROOT / 'tmp/nak_provenance_20260829/tang-23.png',
    ]
    for path in [iaea_pdf, tang_pdf, *screenshots]:
        assert path.is_file(), path

    points = [300 + 700*i/10000 for i in range(10001)]
    errors = [nak_cp(t) - iaea_cp_nak(t) for t in points]
    index = max(range(len(errors)), key=lambda i: abs(errors[i]))
    endpoint_rows = []
    for t in [360.10, 609.58, 723.15]:
        endpoint_rows.append({
            'temperature_K': t,
            'active_cp_J_kgK': nak_cp(t),
            'IAEA_weight_fraction_mix_cp_J_kgK': iaea_cp_nak(t),
            'active_minus_IAEA_J_kgK': nak_cp(t) - iaea_cp_nak(t),
        })
    result = {
        'status': 'PASS provenance audit; exact cubic fit-generation provenance remains untraced',
        'active_model_file': str(source),
        'active_model_sha256': sha(source),
        'active_NaK_cp_script': active_script,
        'project_flow_kg_s': 6.95,
        'project_flow_git_introduction_commit': commit,
        'project_flow_evidence': 'Project boundary explicitly marked not thesis direct',
        'IAEA_report_file': str(iaea_pdf),
        'IAEA_report_sha256': sha(iaea_pdf),
        'IAEA_equations': {
            'sodium_cp': 'Eq. 3.9 with physically necessary 10.24e-6*T^2 reading',
            'potassium_cp': 'Eq. 3.16',
            'NaK_cp': 'Eq. 3.51: 0.22*Cp_Na + 0.78*Cp_K',
        },
        'current_cubic_interpretation': (
            'Numerically close approximation to the IAEA 22Na-78K weight-fraction mixture '
            'over 300-1000 K; fit method and fit interval not located in project history'),
        'comparison_range_K': [300.0, 1000.0],
        'dense_grid_count': len(points),
        'max_absolute_cp_difference_J_kgK': abs(errors[index]),
        'max_absolute_difference_temperature_K': points[index],
        'endpoint_rows': endpoint_rows,
        'supplemental_2025_paper_file': str(tang_pdf),
        'supplemental_2025_paper_sha256': sha(tang_pdf),
        'supplemental_role': (
            'Confirms 22Na-78K weight-fraction mixture equations A.4.5-A.4.6; '
            'its approximately 7.408 kg/s startup flow belongs to a different 2025 system'),
        'visual_evidence': [{'path': str(path), 'sha256': sha(path)} for path in screenshots],
        'formal_mutations': False,
    }
    output = output_directory / 'nak_property_provenance.json'
    if args.verify_only:
        assert json.loads(output.read_text()) == result
    else:
        with output.open('x') as stream:
            json.dump(result, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
