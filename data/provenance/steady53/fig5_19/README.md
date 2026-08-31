# Figure 5.19 paper-only digitization

This directory is observation evidence from the scanned thesis page only, not a model result or a reproduction claim. It contains 60 points (15 fixed times for each of four panels). The digitizer reads no model file, SLX, MAT file, baseline, or model output.

At each fixed time it uses the literal pixel calibrations in `provenance.json`, thresholds the three image columns x-1:x+1 at grayscale <120, groups contiguous dark y pixels, and traces backwards from 495 s by nearest image-continuous group center. Ties use the uppermost group center. Axis-border ink, empty columns, and jumps over 80 pixels are rejected.

Limitations: the early trace is nearly vertical and scan-limited; t=10 s is a proxy for the authors' t0, not an asserted original sampling instant. There is no smoothing, time shifting, model-guided choice, fitted correction, or formal promotion. `paper_reproduced = false`; `formal_promotion = false`.

`manifest.csv` is nonrecursive and intentionally excludes itself; it records hashes for every other durable artifact in this directory.
