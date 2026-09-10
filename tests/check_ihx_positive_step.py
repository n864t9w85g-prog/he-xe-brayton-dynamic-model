"""Physical-domain regression for the prescribed 1200 -> 1204 K experiment."""
import argparse
from pathlib import Path
import numpy as np

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("case_directory", type=Path)
args = parser.parse_args()
for k in range(1, 11):
    a = np.loadtxt(args.case_directory / f"state_{k:02}.csv", delimiter=",", ndmin=2)
    assert a.shape[1] == 2 and np.isfinite(a).all()
    assert a[0, 0] == 0 and a[-1, 0] == 2
    assert np.all(np.diff(a[:, 0]) >= 0)
    assert abs(a[0, 1] - 1200) < 1e-6
    assert a[:, 1].min() >= 1200 - 1e-6, (
        f"state_{k:02}: minimum {a[:, 1].min():.9f} K below uniform initial 1200 K"
    )
    assert a[:, 1].max() <= 1204 + 1e-6, f"state_{k:02}: exceeds the hottest boundary"
print("PASS: all ten recorded states stay within [1200,1204] K (numerical allowance 1e-6 K).")
print("This is a local physical-domain check, NOT thesis acceptance.")
