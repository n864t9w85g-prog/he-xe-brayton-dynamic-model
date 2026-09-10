"""One unchanged closure test for original and hA-consistent CSV evidence."""
import csv
from pathlib import Path
import sys


def check(path):
    rows = list(csv.DictReader(Path(path).open()))
    assert rows, "No data"
    residuals = []
    for row in rows:
        p, dt, k = (float(row[n]) for n in ("P_Rx_W", "dTf_dt_K_s", "kappa"))
        m, cp, ti, to = (float(row[n]) for n in ("mdot_kg_s", "cp_J_kgK", "Tin_K", "Tout_K"))
        residuals.append(p-dt/k-m*cp*(to-ti))
    worst = max(map(abs, residuals))
    print(f"max_abs_fuel_to_coolant_residual_W={worst:.12g}")
    assert worst < 0.001, f"Fuel-to-coolant closure fails: {worst:.12g} W"


if __name__ == "__main__":
    check(sys.argv[1])
