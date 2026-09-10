#!/usr/bin/env python3
"""Independent NaK enthalpy-closure gate for a completed whole-system run."""
import argparse
import csv
import json
import math
from pathlib import Path

from verify_precooler_boundary_diagnostic import nak_h, semantic_inventory
from verify_tac_power_sources import ROOT, sha


def last(path):
    with path.open() as stream:
        rows = list(csv.DictReader(stream))
    assert rows, path
    values = [(float(row['time_s']), float(row['value'])) for row in rows]
    assert all(math.isfinite(t) and math.isfinite(v) for t, v in values), path
    assert all(a[0] <= b[0] for a, b in zip(values, values[1:])), path
    return values[-1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('run_directory', type=Path)
    parser.add_argument('model_file', type=Path)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()

    run_dir = args.run_directory.resolve()
    model_file = args.model_file.resolve()
    assert run_dir.is_relative_to(ROOT / 'tmp')
    assert model_file.is_relative_to(ROOT / 'tmp')
    status = json.loads((run_dir / 'status.json').read_text())
    assert status['success'] and status['final_time_s'] == status['requested_stop_time_s']
    stop_time = float(status['requested_stop_time_s'])

    raw_names = ['cooler_cold_outlet_T', 'cooler_cold_inlet_T', 'state_040']
    raw = {}
    sources = []
    for name in raw_names:
        path = run_dir / f'{name}.csv'
        time, value = last(path)
        assert time == stop_time, (name, time, stop_time)
        raw[name] = value
        sources.append({'path': str(path), 'sha256': sha(path)})

    source = ROOT / 'tmp/steady53_curves_20260828/source_f8bcd83/final_steady_24a.slx'
    assert sha(source) == '0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391'
    precooler = semantic_inventory(source, 'precooler')
    radiator = semantic_inventory(model_file, 'rediator')

    mc = 6.95
    tin = raw['cooler_cold_outlet_T']
    tout = raw['cooler_cold_inlet_T']
    wall = raw['state_040']
    q_enthalpy = mc * (nak_h(tin) - nak_h(tout))
    q_convection = 1113.0 * 9.755 * (0.8 * tin + 0.2 * tout - wall)

    q_precooler = 0.0
    for region in range(2):
        state_path = run_dir / f'state_{12 + 5 * region:03d}.csv'
        wall_path = run_dir / f'state_{16 + 5 * region:03d}.csv'
        t_state, cold_mean = last(state_path)
        t_wall, region_wall = last(wall_path)
        assert t_state == stop_time and t_wall == stop_time
        sources.extend([
            {'path': str(state_path), 'sha256': sha(state_path)},
            {'path': str(wall_path), 'sha256': sha(wall_path)},
        ])
        prefix = f'precooler_{region + 1}/'
        h_c = float(precooler['blocks'][prefix + 'h_c'][1]['Value'])
        area = float(precooler['blocks'][prefix + 'A_region2'][1]['Value'])
        q_precooler += h_c * area * (region_wall - cold_mean)

    enthalpy_convection_residual = q_enthalpy - q_convection
    loop_residual = q_precooler - q_enthalpy
    result = {
        'status': 'PASS',
        'scope': 'Exploration-only whole-system NaK enthalpy candidate; not paper acceptance',
        'run_directory': str(run_dir),
        'model_file': str(model_file),
        'model_sha256': sha(model_file),
        'source_sha256': sha(source),
        'verifier_sha256': sha(__file__),
        'final_time_s': stop_time,
        'NaK_radiator_inlet_K': tin,
        'NaK_radiator_outlet_K': tout,
        'radiator_wall_K': wall,
        'radiator_enthalpy_heat_W': q_enthalpy,
        'radiator_convection_heat_W': q_convection,
        'radiator_enthalpy_minus_convection_W': enthalpy_convection_residual,
        'precooler_cold_heat_W': q_precooler,
        'precooler_minus_radiator_enthalpy_W': loop_residual,
        'raw_sources': sources,
        'formal_mutations': False,
        'paper_acceptance': False,
    }
    assert abs(enthalpy_convection_residual) < 1.0, result
    assert abs(loop_residual) < 1000.0, result
    candidate_scripts = [
        script for path, script in radiator['scripts'].items()
        if path == 'Tho' and 'nak_enthalpy_outlet' in script
    ]
    assert len(candidate_scripts) == 1, 'candidate enthalpy outlet solver is absent'

    output = run_dir / 'nak_enthalpy_verification.json'
    if args.write:
        with output.open('x') as stream:
            json.dump(result, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
    elif output.exists():
        assert json.loads(output.read_text()) == result
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
