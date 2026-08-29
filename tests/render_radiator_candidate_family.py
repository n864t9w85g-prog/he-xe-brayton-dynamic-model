"""Render the 16-branch mass/area envelope as deterministic SVG."""
from __future__ import annotations

import argparse
import csv
from html import escape
from pathlib import Path


def render(candidate_csv: Path, output_svg: Path) -> None:
    with candidate_csv.open() as handle:
        rows = list(csv.DictReader(handle))
    ids = [row["candidate_id"] for row in rows]
    if len(rows) != 16 or len(set(ids)) != 16:
        raise ValueError("renderer requires exactly 16 unique source branches")
    width, height = 1200, 760
    left, top, chart_w, chart_h = 90, 80, 760, 600
    kmax = max(float(row["kappa_kg_m2"]) for row in rows)
    amax = max(float(row["A_rad_upper_if_TAC_zero_m2"]) for row in rows)
    palette = {"tested": "#1b9e77", "built_not_tested": "#d95f02",
               "projected": "#7570b3"}
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="white"/>',
        '<text x="600" y="28" text-anchor="middle" font-size="22">'
        'Scheme-B radiator branches</text>',
        '<text x="600" y="52" text-anchor="middle" font-size="14">'
        'mass-derived area upper bound, not design area</text>',
        f'<line x1="{left}" y1="{top+chart_h}" x2="{left+chart_w}" '
        f'y2="{top+chart_h}" stroke="black"/>',
        f'<line x1="{left}" y1="{top}" x2="{left}" y2="{top+chart_h}" stroke="black"/>',
        '<text x="470" y="735" text-anchor="middle">kappa (kg/m2)</text>',
        '<text x="22" y="380" transform="rotate(-90 22 380)" '
        'text-anchor="middle">A_rad upper bound if TAC mass=0 (m2)</text>',
    ]
    for row in rows:
        kappa = float(row["kappa_kg_m2"])
        area = float(row["A_rad_upper_if_TAC_zero_m2"])
        x = left + chart_w * kappa / kmax
        y = top + chart_h * (1.0 - area / amax)
        color = palette[row["technology_evidence_grade"]]
        label = escape(row["candidate_id"])
        parts.append(
            f'<g class="branch"><circle cx="{x:.2f}" cy="{y:.2f}" r="6" '
            f'fill="{color}"/><title>{label}</title></g>')
    for index, (label, color) in enumerate(palette.items()):
        y = 140 + index * 28
        parts.extend([
            f'<circle cx="910" cy="{y}" r="6" fill="{color}"/>',
            f'<text x="925" y="{y+5}" font-size="14">{escape(label)}</text>',
        ])
    parts.append('<g font-size="10" fill="#333">')
    for index, row in enumerate(rows):
        y = 250 + index * 24
        parts.append(f'<text x="880" y="{y}">{escape(row["candidate_id"])}</text>')
    parts.extend(['</g>', '</svg>'])
    output_svg.write_text("\n".join(parts) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate_csv", type=Path)
    parser.add_argument("output_svg", type=Path)
    args = parser.parse_args()
    render(args.candidate_csv, args.output_svg)
    print(args.output_svg)


if __name__ == "__main__":
    main()
