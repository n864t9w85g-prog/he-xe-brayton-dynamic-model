# Compressor-map provenance status

## Accepted source

- Algorithm: Michael R. Galvas, *FORTRAN Program for Predicting Off-Design
  Performance of Centrifugal Compressors*, NASA TN D-7487, 1973.
- Thesis connection: Xu Chi cites this report as reference [162] for the
  compressor off-design model.
- Workspace PDF: `sources/NASA-TN-D-7487-Galvas-1973.pdf`.
- PDF SHA-256: `c8d58a4319eb544957453180d437eb3b2c5f637280a111358c216aa5705e6b84`.
- The user-supplied `压气机程序 (Compressor Program).pdf` has the same hash.

The source program requires complete compressor geometry plus inlet fluid
properties. Its 28 NAMELIST fields are represented by the supplied Python
translation. NASA report page 35 states that no original FORTRAN listing of
`FNTGRL` is available; both supplied implementations reconstruct that routine
from the three published integration formulas. This limitation is retained and
must not be described as an original historical listing.

## Supplied implementation snapshot

`nasa_tn_d7487/original/` is an unchanged snapshot of the five files supplied
on 2026-08-17. `nasa_tn_d7487/SHA256SUMS.txt` records their hashes. The runnable
workspace implementation is kept separately at
`tools/nasa_tn_d7487/compressor_program.py`, so corrections do not alter the
evidence snapshot.

The supplied NASA example uses air, 72000 rpm, and the example compressor
geometry printed in report Figure 5. It reproduces the report's approximately
6.465 pressure-ratio point. It is not Xu Chi's He-Xe compressor geometry and
must never be used as the thesis input set.

The supplied Python implementation has 39 passing self-tests against the
published D-7487 example. That establishes the transcription against that
example only; it does not establish the 6.44-inch compressor input set.

## Target-geometry source

- Design report: AiResearch, *Design and Fabrication of the Brayton Cycle High
  Performance Compressor Research Package*, NASA CR-72533 / APS-5269-R, 1967.
- Workspace PDF: `sources/NASA-CR-72533-AiResearch-1967.pdf`.
- PDF SHA-256:
  `c2226cb71d666cac7aadde45d843b7b9cafcba7c0783ac9467b4dc498b59ef0e`.
- Relevant pages: PDF page 11 (Figure 1), pages 14-15 (Figures 2-3), page 16
  (Table I), page 17 (Figure 4), and page 23 (Table 2).

TM X-2269 explicitly states that the 6.44-inch and 4.25-inch compressors are
identical scale models of a larger compressor. The CR-72533 dimensions therefore
support dimensionless geometry checks, but do not authorize copying unrelated
D-7487 example values.

- Corroborating performance report: NASA TM X-2129, *Overall Performance in
  Argon of 4.25-inch Sweptback-Bladed Centrifugal Compressor*, 1970.
- Workspace PDF: `sources/NASA-TM-X-2129-Ball-Tysl-Weigel-1970.pdf`.
- PDF SHA-256:
  `c4ba6beffa6cb17bc637acad63d08441bd82669f95f1154e059a43c2490f1b42`.
- Completeness check: 20 pages and 11,488,759 bytes.

TM X-2129 independently gives the 4.25-inch design Reynolds number. Applying
the report's own Reynolds-number definition to its inlet state, tip speed, and
diameter gives `mu0 = 2.29811707274e-5 Pa s`. The corresponding calculation
from TM X-2269 gives `2.28638885134e-5 Pa s`; the agreement supports the latter
audit value within the source reports' printed precision.

`nasa_tn_d7487/target_input_audit.csv` inventories all 28 inputs. A populated
cell is allowed only when it has a published location and a repeatable derivation;
unresolved fields remain blank.

## Current evidence gap

The current evidence resolves 15 of the 28 D-7487 inputs. It does not yet
establish the remaining 13: `cf`, `vovcr`, `nvovcr`, `b1mfb`, `ar`, `block`,
`al3`, `adth`, `splt`, `curvh`, `curvt`, `chih`, and `chit`.

Several published diagrams provide candidates that are deliberately not entered
as values. For example, TM X-2269 Figure 1 shows a 61.6-degree mean relative-flow
direction, but does not label it as the metal blade angle `B1MFB`. Figures 2-3
provide flow angles and effective areas, but D-7487 requires geometric diffuser
setting angle and area inputs. Treating these different quantities as identical
would be an unsupported substitution.

The values in `压气机几何自洽说明_论文级.md` include a chosen work coefficient
and similarity scaling. They are engineering assumptions, not thesis literals
or recovered compressor geometry, and are therefore excluded from the formal
reproduction input.

## Active-map status

`hexe_compressor_lookup.mat` is still version `3.0-paper-shape`; its metadata
explicitly calls the off-design lines smooth surrogates, and its builder uses
Gaussian expressions. It remains diagnostic-only and fails
`tests/test_compressor_map_provenance.m`. The active map must not be called a
paper reproduction until that test passes with a complete sourced input
manifest and deterministic raw NASA output points.

## Selected bounded high-speed method

Because the 13 unresolved D-7487 target inputs cannot be filled without
assumptions, the formal candidate map uses the digitized NASA TM X-2269
measurements through 100% corrected speed. For `1 < s <= 1.10`, where
`s=N_corrected/N_design`, it predicts from the measured 100% line with no fitted
coefficient:

```text
flow_s = s * flow_100
PR_s = [1 + s^2 * (PR_100^(2/5) - 1)]^(5/2)
eta_s = eta_100
```

Points above 100% are categorized as `similarity_prediction`, not NASA
measurements. Values above `s=1.10` are rejected. The Section 5.4 speed endpoints
are excluded from calibration and remain independent acceptance observations.

A leave-one-out check predicts the measured 90% line from the measured 100%
line at points 3--5 of each sorted 90% curve. It gives pressure-ratio
`MAE=0.0228671267225498`, `max=0.0322228459018734`, and efficiency
`MAE=0.00441873824420987`, `max=0.00565366047760163`. The validation-only 90%
predictions are not written into the model map; the measured 90% lines are used
below 100% speed.
