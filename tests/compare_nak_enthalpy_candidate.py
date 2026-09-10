#!/usr/bin/env python3
"""Compare the NaK enthalpy candidate with the unchanged 14000 s reference."""
import argparse
import csv
import json
import math
from pathlib import Path

from verify_tac_power_sources import ROOT, sha


PAPER = {
    'reactor_outlet_T': (1600.0, 'K'),
    'reactor_inlet_T': (1443.27, 'K'),
    'turbine_inlet_T': (1522.96, 'K'),
    'turbine_outlet_T': (1162.0, 'K'),
    'compressor_inlet_T': (405.16, 'K'),
    'compressor_outlet_T': (601.90, 'K'),
    'recuperator_hot_outlet_T': (663.63, 'K'),
    'cooler_cold_outlet_T': (609.58, 'K'),
    'cooler_cold_inlet_T': (360.10, 'K'),
    'turbine_power': (2252.2e3, 'W'),
    'compressor_power': (1231.6e3, 'W'),
}


def series(directory, name):
    path = directory / f'{name}.csv'
    with path.open() as stream:
        values = [(float(row['time_s']), float(row['value'])) for row in csv.DictReader(stream)]
    assert values and values[-1][0] == 14000.0
    assert all(math.isfinite(t) and math.isfinite(v) for t, v in values)
    return path, values


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('candidate_root', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    root = args.candidate_root.resolve()
    assert root.is_relative_to(ROOT / 'tmp')
    candidate = root / 'candidate_14000'
    reference = ROOT / 'tmp/pressure_closure_4FKFZS/reference_14000'
    verification = json.loads((candidate / 'nak_enthalpy_verification.json').read_text())
    assert verification['status'] == 'PASS'
    assert abs(verification['radiator_enthalpy_minus_convection_W']) < 1.0
    assert abs(verification['precooler_minus_radiator_enthalpy_W']) < 1000.0

    rows = []
    sources = []
    for name, (paper, unit) in PAPER.items():
        reference_path, reference_values = series(reference, name)
        candidate_path, candidate_values = series(candidate, name)
        reference_value = reference_values[-1][1]
        candidate_value = candidate_values[-1][1]
        window = [value for time, value in candidate_values if time >= 13000]
        assert window
        reference_error = reference_value - paper
        candidate_error = candidate_value - paper
        rows.append({
            'signal': name,
            'unit': unit,
            'paper_value': paper,
            'reference_14000': reference_value,
            'candidate_14000': candidate_value,
            'reference_minus_paper': reference_error,
            'candidate_minus_paper': candidate_error,
            'candidate_minus_reference': candidate_value - reference_value,
            'absolute_error_improved': abs(candidate_error) < abs(reference_error),
            'candidate_13000_14000_peak_to_peak': max(window) - min(window),
            'candidate_window_sample_count': len(window),
        })
        sources.extend([
            {'path': str(reference_path), 'sha256': sha(reference_path)},
            {'path': str(candidate_path), 'sha256': sha(candidate_path)},
        ])

    by_name = {row['signal']: row for row in rows}
    cold_chain = ['compressor_inlet_T', 'compressor_outlet_T',
                  'recuperator_hot_outlet_T', 'cooler_cold_outlet_T',
                  'cooler_cold_inlet_T']
    assert all(not by_name[name]['absolute_error_improved'] for name in cold_chain)
    result = {
        'status': 'PASS comparison; candidate energy closure is not paper acceptance',
        'scope': 'Unchanged warm reference versus single-variable NaK enthalpy candidate at 14000 s',
        'candidate_root': str(root),
        'candidate_model_sha256': verification['model_sha256'],
        'reference_model_sha256': verification['source_sha256'],
        'closure_verification_sha256': sha(candidate / 'nak_enthalpy_verification.json'),
        'comparison_script_sha256': sha(__file__),
        'rows': rows,
        'cold_chain_all_absolute_errors_worsened': True,
        'raw_sources': sources,
        'formal_mutations': False,
        'paper_acceptance': False,
    }
    output = root / 'comparison.json'
    if args.verify_only:
        assert json.loads(output.read_text()) == result
    else:
        with output.open('x') as stream:
            json.dump(result, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
