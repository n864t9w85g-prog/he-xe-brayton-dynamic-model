# Figure 5.18(d) Native V2 Digitization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a source-bound, two-method native-resolution digitization of thesis Figure 5.18(d), derive per-point image uncertainty, and rerun the fixed four-case constant-positive two-state feasibility gate without touching any formal model file.

**Architecture:** A frozen contract extracts PDF image object 267 byte-for-byte and creates a pixel-exact vertical-flip working image. Separate calibration, trace-A, trace-B, and consensus modules generate an image-only evidence bundle; a new feasibility module consumes only the consensus data and pointwise bounds. A one-shot runner, explicit overlay-review record, and independent verifier publish a fresh manifest-last directory while preserving all old evidence.

**Tech Stack:** Python 3 stdlib, `pypdf 6.10.0`, `Pillow 12.3.0`, `NumPy 2.3.5`, `unittest`, SHA-256, Decimal precision 50; optional Wolfram plugin only if the written trigger gate fires.

---

## 0. Frozen scope and file map

Implementation must happen on branch `codex/fig518d-native-v2-digitization`. Before Task 1 execution, use the `using-git-worktrees` skill; if the user declines a linked worktree, continue on the already dedicated branch without touching unrelated untracked files.

The approved design is:

`docs/superpowers/specs/2026-09-02-fig518d-native-v2-digitization-design.md`

### Files to create

| File | Single responsibility |
|---|---|
| `tests/fig518d_native_contract.py` | Frozen input identities, schemas, fixed samples, protected snapshots |
| `tests/test_fig518d_native_contract.py` | Contract, PDF object extraction, orientation, fail-closed tests |
| `tests/fig518d_native_calibration.py` | Tick-center detection and affine pixel/axis transforms |
| `tests/test_fig518d_native_calibration.py` | Synthetic and real-image calibration tests |
| `tests/fig518d_trace_a.py` | Dark-ink connected-band tracing only |
| `tests/test_fig518d_trace_a.py` | Method-A synthetic/real trace tests |
| `tests/fig518d_trace_b.py` | Independent local-contrast dynamic path tracing only |
| `tests/test_fig518d_trace_b.py` | Method-B synthetic/real trace and independence tests |
| `tests/fig518d_native_consensus.py` | Method agreement, pointwise uncertainty, CSV and overlay generation |
| `tests/test_fig518d_native_consensus.py` | Agreement/inconclusive/overlay contract tests |
| `tests/fig518d_native_feasibility.py` | Four-case nominal and pointwise-bound two-state gate |
| `tests/test_fig518d_native_feasibility.py` | Equation, LS/NNLS, corner, classification tests |
| `tests/run_fig518d_native_v2.py` | One-shot staging run; no durable publication |
| `tests/test_run_fig518d_native_v2.py` | Freshness, atomicity, protected-file, no-model-read tests |
| `tests/review_fig518d_native_overlay.py` | Record an explicit source-only visual review against the overlay hash |
| `tests/test_review_fig518d_native_overlay.py` | Review schema, no-overwrite, rejection tests |
| `tests/verify_fig518d_native_v2.py` | Independent Decimal/pixel verifier and exclusive publisher |
| `tests/test_verify_fig518d_native_v2.py` | Tamper, collision, fault, optimized-mode, publication tests |

### Runtime and durable outputs

- Runtime only: `tmp/fig518d_native_v2_20260902_A/**`
- Publish only after all gates pass: `data/provenance/steady53/fig5_18d/paper_curve_native_v2/**`

Never modify:

- `data/provenance/steady53/fig5_18d/paper_curve/**`
- `data/provenance/steady53/fig5_18d/two_state_feasibility/**`
- any `.slx`, top-level `.mat`, property function, or acceptance document

---

### Task 1: Freeze the native-image evidence contract

**Files:**
- Create: `tests/fig518d_native_contract.py`
- Create: `tests/test_fig518d_native_contract.py`

- [ ] **Step 1: Write failing contract tests**

Create tests that require the exact PDF identity, page/object identity, source dimensions, raw JPEG hash, fixed sample times, false flags, and protected paths:

```python
class NativeContractTests(unittest.TestCase):
    def test_frozen_source_identity(self):
        self.assertEqual(subject.PDF_SHA256,
            "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a")
        self.assertEqual((subject.PDF_PAGE, subject.PRINTED_PAGE), (105, 90))
        self.assertEqual(subject.IMAGE_OBJECT_ID, 267)
        self.assertEqual(subject.RAW_IMAGE_SIZE, (1684, 1534))
        self.assertEqual(subject.RAW_JPEG_SHA256,
            "b0c5887c8dcc8941270d2b2a359ec38601fb7dbbcb21b59dd24aa5ca3a38cffd")

    def test_fixed_samples_and_false_flags(self):
        self.assertEqual(subject.SAMPLE_TIMES_S,
            (5, 10, 15, 20, 30, 40, 60, 80, 100, 125, 150, 200))
        self.assertEqual(dict(subject.FALSE_FLAGS), {
            "paper_reproduced": False,
            "author_parameter_identified": False,
            "formal_promotion": False,
        })
```

Also require exactly these protected relative paths:

```python
(
 "final_steady_24a.slx", "HeXe_property_simulink.m",
 "Lithium_property_simulink.m", "hexe_compressor_lookup.mat",
 "radiator_table.mat", "turbine_table1.mat", "turbine_table2.mat",
 "data/provenance/steady53/fig5_18d/paper_curve",
 "data/provenance/steady53/fig5_18d/two_state_feasibility",
)
```

Directory snapshots must hash every regular file recursively in stable relative-path order and reject symlinks/non-regular files.

- [ ] **Step 2: Run RED in normal and optimized mode**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest -v tests.test_fig518d_native_contract
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -O -m unittest -v tests.test_fig518d_native_contract
```

Expected: both fail because `tests.fig518d_native_contract` does not exist.

- [ ] **Step 3: Implement the frozen contract and extraction API**

Implement immutable dataclasses and mapping proxies:

```python
@dataclass(frozen=True)
class SourceImage:
    raw_jpeg: bytes
    oriented_png: bytes
    width: int
    height: int

@dataclass(frozen=True)
class TraceBand:
    trace_id: str
    target_time_s: float
    x_px: int
    actual_time_s: float
    y_low_px: float
    y_center_px: float
    y_high_px: float

def verify_pdf_identity(path: Path = PDF_PATH) -> bytes:
    data = path.read_bytes()
    if sha256(data).hexdigest() != PDF_SHA256:
        raise EvidenceContractError("thesis PDF hash mismatch")
    return data

def extract_source_image(path: Path = PDF_PATH) -> SourceImage:
    verify_pdf_identity(path)
    reader = PdfReader(path)
    page = reader.pages[PDF_PAGE - 1]
    images = page["/Resources"]["/XObject"].get_object()
    matches = []
    for _, reference in images.items():
        obj = reference.get_object()
        if getattr(reference, "idnum", None) == IMAGE_OBJECT_ID:
            matches.append(obj)
    if len(matches) != 1:
        raise EvidenceContractError("PDF image object 267 is not unique")
    obj = matches[0]
    if (obj.get("/Subtype"), obj.get("/Filter"), obj.get("/Width"),
        obj.get("/Height")) != ("/Image", "/DCTDecode", 1684, 1534):
        raise EvidenceContractError("PDF image object metadata mismatch")
    raw = bytes(obj._data)
    if sha256(raw).hexdigest() != RAW_JPEG_SHA256:
        raise EvidenceContractError("raw JPEG hash mismatch")
    with Image.open(io.BytesIO(raw)) as image:
        rgb = image.convert("RGB")
        oriented = rgb.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        stream = io.BytesIO()
        oriented.save(stream, format="PNG", optimize=False, compress_level=9)
    return SourceImage(raw, stream.getvalue(), 1684, 1534)
```

Use the bundled runtime paths discovered by `load_workspace_dependencies`; do not install SciPy/OpenCV.

- [ ] **Step 4: Add pixel-exact orientation and failure tests**

Test representative corners and 100 deterministic interior pixels:

```python
raw = Image.open(io.BytesIO(source.raw_jpeg)).convert("RGB")
oriented = Image.open(io.BytesIO(source.oriented_png)).convert("RGB")
for x, y in deterministic_coordinates:
    self.assertEqual(oriented.getpixel((x, 1533-y)), raw.getpixel((x, y)))
```

Tests must also reject a changed PDF hash, wrong object id/filter/dimensions, duplicate object match, symlinked PDF, and non-finite/duplicate sample definitions.

- [ ] **Step 5: Run GREEN and commit**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest -v tests.test_fig518d_native_contract
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -O -m unittest -v tests.test_fig518d_native_contract
git add tests/fig518d_native_contract.py tests/test_fig518d_native_contract.py
git commit -m "固化图5.18d原生图像证据合同"
```

Expected: both suites pass; commit contains only the two Task 1 files.

---

### Task 2: Calibrate Figure 5.18(d) from visible ticks

**Files:**
- Create: `tests/fig518d_native_calibration.py`
- Create: `tests/test_fig518d_native_calibration.py`

- [ ] **Step 1: Write failing synthetic and real calibration tests**

Freeze image-only search windows around the visible ticks:

```python
TIME_TICK_WINDOWS = {
    0.0: (916, 925), 100.0: (1154, 1164),
    200.0: (1392, 1402), 300.0: (1630, 1640),
}
TEMP_TICK_WINDOWS = {
    450.0: (812, 821), 400.0: (950, 961), 350.0: (1089, 1099),
    300.0: (1228, 1238), 250.0: (1367, 1377),
}
```

Tests must require:

- exactly four time and five temperature anchors;
- strictly monotone pixel/value mappings;
- affine-fit maximum residual `<= 1.0 px`;
- panel interior approximately bounded by left/right `920.5/1635.0 px` and top/bottom `816.5/1372.0 px`, with a tolerance of `1.5 px` used only as a test sanity check;
- fixed target times map to 12 unique, increasing image columns inside the panel;
- round-trip pixel/value error is below `1e-9` apart from nearest-column quantization.

- [ ] **Step 2: Run RED**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest -v tests.test_fig518d_native_calibration
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -O -m unittest -v tests.test_fig518d_native_calibration
```

Expected: import failure.

- [ ] **Step 3: Implement calibration without OCR or model data**

Create:

```python
@dataclass(frozen=True)
class AxisFit:
    pixel_slope: float
    pixel_intercept: float
    max_residual_px: float
    tick_centers_px: Mapping[float, float]
    tick_half_widths_px: Mapping[float, float]

@dataclass(frozen=True)
class Calibration:
    time: AxisFit
    temperature: AxisFit

    def time_for_x(self, x_px: float) -> float: ...
    def temperature_for_y(self, y_px: float) -> float: ...
    def x_for_time(self, time_s: float) -> float: ...
```

For time ticks, measure dark vertical tick pixels only inside rows `1366:1392`; for temperature ticks, measure dark horizontal tick pixels only inside columns `910:938`. Within each frozen window, form an ink-weighted center from grayscale `<120`, record the first/last occupied coordinate as line-width bounds, fit the affine map with `numpy.linalg.lstsq`, and fail if residual exceeds one pixel.

This is a numerical implementation choice that does not alter a physical equation.

- [ ] **Step 4: Test tamper and ambiguity rejection**

Synthetic images must prove rejection when a tick is absent, doubled into two separated groups, non-monotone, or moved enough to exceed the residual gate. The real image test must serialize all nine anchors and the realized 12 sample columns.

- [ ] **Step 5: Run GREEN and commit**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest -v tests.test_fig518d_native_contract tests.test_fig518d_native_calibration
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -O -m unittest -v tests.test_fig518d_native_contract tests.test_fig518d_native_calibration
git add tests/fig518d_native_calibration.py tests/test_fig518d_native_calibration.py
git commit -m "建立图5.18d原生像素坐标标定"
```

---

### Task 3: Implement trace method A

**Files:**
- Create: `tests/fig518d_trace_a.py`
- Create: `tests/test_fig518d_trace_a.py`

- [ ] **Step 1: Write failing trace-A tests**

Tests must create small synthetic images with two rising dark curves, axis ink, a legend segment, and label-like blobs. Require method A to return exactly two traces × 12 samples, each band ordered as:

```python
band.y_low_px <= band.y_center_px <= band.y_high_px
```

Require reverse continuity from plateau to startup, axis/legend rejection, deterministic uppermost tie-breaking, maximum adjacent-column jump rejection, and identical output in normal/optimized mode.

- [ ] **Step 2: Run RED**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest -v tests.test_fig518d_trace_a
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -O -m unittest -v tests.test_fig518d_trace_a
```

- [ ] **Step 3: Implement connected dark-band tracing**

Use fixed image-only constants:

```python
GRAY_THRESHOLD = 120
X_NEIGHBORHOOD = 2
MAX_STEP_PER_COLUMN_PX = 7
PLATEAU_SEEDS = {
    "wall": (895, 945),
    "outlet": (1035, 1080),
}
TRACE_X_RANGE_S = (5.0, 200.0)
```

Implement `_dark_groups`, `_select_connected_group`, `trace_dense`, and `sample_bands`. Trace every integer x-column from the realized 200 s column back to the realized 5 s column; do not jump directly between the 12 samples. Exclude a four-pixel border and fixed source-visible text/legend masks. A group is valid only if its thickness is `1..8 px` and its center is within `MAX_STEP_PER_COLUMN_PX` of the later accepted center.

For each fixed sample column, combine the accepted group from `x-2:x+2`; the band is the union of occupied y pixels and the center is their arithmetic pixel center.

- [ ] **Step 4: Validate on the frozen real source**

Real-source tests may assert only image-derived invariants:

- 24 rows total;
- two trace ids and 12 rows each;
- x strictly increases with time;
- wall y is above outlet y at every sampled column;
- both plateau bands are continuous across 150–200 s;
- every reported band contains at least one pixel with grayscale `<120`.

Do not assert expected paper temperatures in the tracing test.

- [ ] **Step 5: Run GREEN and commit**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest -v tests.test_fig518d_native_contract tests.test_fig518d_native_calibration tests.test_fig518d_trace_a
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -O -m unittest -v tests.test_fig518d_native_contract tests.test_fig518d_native_calibration tests.test_fig518d_trace_a
git add tests/fig518d_trace_a.py tests/test_fig518d_trace_a.py
git commit -m "实现图5.18d暗像素连通带追踪"
```

---

### Task 4: Implement independent trace method B

**Files:**
- Create: `tests/fig518d_trace_b.py`
- Create: `tests/test_fig518d_trace_b.py`

- [ ] **Step 1: Write failing local-contrast path tests**

Use the same synthetic images but alter absolute brightness so a fixed `<120` threshold no longer sees the curves. Method B must still trace them from local contrast. Tests must also parse the production AST and reject all of:

```python
import tests.fig518d_trace_a
from tests import fig518d_trace_a
from tests.fig518d_trace_a import trace_dense
```

- [ ] **Step 2: Run RED**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest -v tests.test_fig518d_trace_b
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -O -m unittest -v tests.test_fig518d_trace_b
```

- [ ] **Step 3: Implement a NumPy-only local-contrast dynamic path**

Use no SciPy/OpenCV and do not import method A. For every panel-interior pixel define:

```python
line_mean = mean(gray[y-1:y+2, x-2:x+3])
background = mean((gray[y-8:y-5, x-2:x+3], gray[y+5:y+8, x-2:x+3]))
contrast = max(0.0, background - line_mean)
```

Starting from the same image-only plateau seed ranges, run a right-to-left dynamic program over every column. The transition set is `dy=-7..7`; cost is `-contrast + 0.20*abs(dy)`, with lower y as deterministic tie-break. Reject paths whose selected contrast is below 10 grayscale levels or whose local contrast peak has no finite `1..10 px` full-width band.

The method-B band is the contiguous set around the selected center where contrast is at least 50% of that column's selected peak.

- [ ] **Step 4: Validate independence and real-image invariants**

Require the same 24-row structural invariants as Task 3, but do not compare to method A in this module. Monkeypatching every public method-A function to raise must not affect method B.

- [ ] **Step 5: Run GREEN and commit**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest -v tests.test_fig518d_trace_b
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -O -m unittest -v tests.test_fig518d_trace_b
git add tests/fig518d_trace_b.py tests/test_fig518d_trace_b.py
git commit -m "实现图5.18d独立局部对比路径追踪"
```

---

### Task 5: Build the consensus and pointwise uncertainty

**Files:**
- Create: `tests/fig518d_native_consensus.py`
- Create: `tests/test_fig518d_native_consensus.py`

- [ ] **Step 1: Write failing agreement and overlay tests**

Define a `ConsensusPoint` containing target/actual time, time lower/upper bounds, both method bands, center temperature, and temperature lower/upper bounds. Tests must prove:

- disjoint expanded bands return `digitization_inconclusive`;
- overlapping bands use the mean of method centers only after the overlap test;
- consensus bounds are the union of both expanded bands;
- axis fit residual, tick half-width, and half-pixel quantization expand bounds outward;
- no point deletion or averaging occurs on disagreement;
- overlay marker positions exactly match serialized method/consensus pixel coordinates.

- [ ] **Step 2: Run RED**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest -v tests.test_fig518d_native_consensus
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -O -m unittest -v tests.test_fig518d_native_consensus
```

- [ ] **Step 3: Implement consensus math**

Implement:

```python
def expanded_temperature_interval(band, calibration):
    raw = sorted((calibration.temperature_for_y(band.y_low_px),
                  calibration.temperature_for_y(band.y_high_px)))
    expansion_K = calibration.temperature_uncertainty_K(band.x_px)
    return raw[0] - expansion_K, raw[1] + expansion_K

def combine(a, b, calibration):
    ia = expanded_temperature_interval(a, calibration)
    ib = expanded_temperature_interval(b, calibration)
    if max(ia[0], ib[0]) > min(ia[1], ib[1]):
        raise DigitizationInconclusive("method bands do not overlap")
    center = (calibration.temperature_for_y(a.y_center_px)
              + calibration.temperature_for_y(b.y_center_px)) / 2
    return center, min(ia[0], ib[0]), max(ia[1], ib[1])
```

Generate deterministic `method_a_points.csv`, `method_b_points.csv`, `consensus_points.csv`, `axis_calibration.json`, and `digitization_overlay.png`. PNG markers must use different fixed colors and include a legend outside the panel crop so it cannot obscure source ink.

- [ ] **Step 4: Run the real-image consensus gate in tests**

The test may yield either a valid 24-row consensus or the exact `digitization_inconclusive` enum. It must never loosen the overlap rule to force a valid result. If valid, all centers/bounds must be finite, ordered, and time-increasing for each trace.

- [ ] **Step 5: Run GREEN and commit**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest -v \
  tests.test_fig518d_native_contract tests.test_fig518d_native_calibration \
  tests.test_fig518d_trace_a tests.test_fig518d_trace_b \
  tests.test_fig518d_native_consensus
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -O -m unittest -v \
  tests.test_fig518d_native_contract tests.test_fig518d_native_calibration \
  tests.test_fig518d_trace_a tests.test_fig518d_trace_b \
  tests.test_fig518d_native_consensus
git add tests/fig518d_native_consensus.py tests/test_fig518d_native_consensus.py
git commit -m "建立图5.18d双方法共识与逐点不确定度"
```

---

### Task 6: Implement the v2 pointwise-bound feasibility gate

**Files:**
- Create: `tests/fig518d_native_feasibility.py`
- Create: `tests/test_fig518d_native_feasibility.py`

- [ ] **Step 1: Write failing equation and classification tests**

Reproduce the frozen NaK functions and four cases in the new module without changing the old contract. Test exact analytic values, interval coefficients, stable scaled QR LS, analytic two-variable NNLS, strict-positive gates, asymmetric point bounds, ordered time corners, and all six output enums.

Use a synthetic dataset for each classification. A reading-sensitive fixture must show a nominal conflict whose sign class changes inside pointwise bounds; a robust fixture must preserve every sign class and conflict at every favorable corner.

- [ ] **Step 2: Run RED**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest -v tests.test_fig518d_native_feasibility
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -O -m unittest -v tests.test_fig518d_native_feasibility
```

- [ ] **Step 3: Implement the four fixed cases**

Freeze:

```python
CASES = (
  Case("project_flow__inlet_cp", 6.95, "inlet_cp"),
  Case("project_flow__integral_enthalpy", 6.95, "integral_enthalpy"),
  Case("energy_closure_flow__inlet_cp", 7.134146337, "inlet_cp"),
  Case("energy_closure_flow__integral_enthalpy", 7.134146337, "integral_enthalpy"),
)
TIN_K = 609.58
ZERO_TOLERANCE = 1e-12
```

Nominal coefficients use consensus centers. The favorable sign gate enumerates the low/high wall and outlet temperatures at both interval endpoints; it declares robust conflict only when all nominal rising/plateau sign classes are preserved and the most favorable positive-UA bound still conflicts. Time cancels in the ratio gate but remains explicit in full residual corners.

For a strictly positive unrestricted candidate, enumerate six binary endpoint choices per interval: first/second time, wall temperature, and outlet temperature. Reject non-increasing time pairs. For a nonpositive candidate, publish blank/false/zero corner records exactly as the old evidence convention.

- [ ] **Step 4: Add Wolfram trigger logic without calling the plugin**

The local module returns a deterministic trigger record:

```python
{
 "triggered": False,
 "reasons": [],
 "qr_rank_margin": value,
 "precision_classification_stable": True,
 "finite_corner_enumeration_complete": True,
}
```

Set `triggered=true` only for an approved-design condition: Decimal/QR disagreement that changes classification, near-rank-deficiency at the stated ULP policy, precision-dependent classification, or a non-enumerable optimization. Tests must prove ordinary fixed two-parameter/finitely enumerated data do not trigger Wolfram and that each synthetic exceptional condition does.

- [ ] **Step 5: Run GREEN and commit**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest -v tests.test_fig518d_native_feasibility
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -O -m unittest -v tests.test_fig518d_native_feasibility
git add tests/fig518d_native_feasibility.py tests/test_fig518d_native_feasibility.py
git commit -m "实现图5.18d逐点边界两状态复核门"
```

---

### Task 7: Build the one-shot run bundle and overlay review record

**Files:**
- Create: `tests/run_fig518d_native_v2.py`
- Create: `tests/test_run_fig518d_native_v2.py`
- Create: `tests/review_fig518d_native_overlay.py`
- Create: `tests/test_review_fig518d_native_overlay.py`

- [ ] **Step 1: Write failing runner tests**

Require `run(run_dir)` to:

- accept only a missing destination below repository `tmp/`;
- snapshot protected files and old evidence before all reads;
- hash-gate the PDF before extracting;
- build the whole bundle in a private sibling staging directory;
- write manifest last inside staging;
- perform an exclusive no-replace directory rename on Darwin;
- clean staging on `Exception`, `KeyboardInterrupt`, and collision;
- leave formal files and old evidence byte-identical;
- produce no `overlay_review.json` automatically;
- read no `.slx`, `.mat`, property function, model output, or old digitized point data.

Expected run files before review:

```python
{
 "source_object_267_raw.jpg", "source_figure_oriented.png",
 "axis_calibration.json", "method_a_points.csv", "method_b_points.csv",
 "consensus_points.csv", "digitization_overlay.png", "provenance.json",
 "feasibility_summary.json", "intervals.csv", "corner_ranges.csv",
 "wolfram_trigger.json", "protected_before.json", "protected_after.json",
 "source_hashes.json", "output_hashes.json", "report.md",
}
```

If digitization is inconclusive, `feasibility_summary.json`, `intervals.csv`, and `corner_ranges.csv` are replaced by one `digitization_failure.json`; no physical classification is emitted.

- [ ] **Step 2: Run runner RED**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest -v tests.test_run_fig518d_native_v2
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -O -m unittest -v tests.test_run_fig518d_native_v2
```

- [ ] **Step 3: Implement runner and minimal CLI**

CLI:

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tests/run_fig518d_native_v2.py \
  --run-dir tmp/fig518d_native_v2_contract_smoke
```

It prints one compact JSON line containing run path, digitization enum, optional feasibility enum, point count, and the three false flags. It must never publish durable evidence.

- [ ] **Step 4: Write failing overlay-review tests**

`record_review(run_dir, decision, checks)` accepts only:

```python
decision == "pass"
checks == {
 "method_a_on_wall_trace": True,
 "method_a_on_outlet_trace": True,
 "method_b_on_wall_trace": True,
 "method_b_on_outlet_trace": True,
 "consensus_markers_match_csv": True,
 "no_model_curve_consulted": True,
}
```

It must bind the review to `digitization_overlay.png` SHA-256 and source-image SHA-256, create `overlay_review.json` exclusively, accept an exactly equal existing review without rewriting, and reject a differing review, failed checkbox, symlink, or changed overlay.

- [ ] **Step 5: Implement the review CLI**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tests/review_fig518d_native_overlay.py \
  --run-dir tmp/fig518d_native_v2_20260902_A --decision pass \
  --confirm method-a-wall --confirm method-a-outlet \
  --confirm method-b-wall --confirm method-b-outlet \
  --confirm consensus-csv --confirm source-only
```

The CLI does not inspect or change scientific CSV/JSON files.

- [ ] **Step 6: Run GREEN and commit**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest -v tests.test_run_fig518d_native_v2 tests.test_review_fig518d_native_overlay
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -O -m unittest -v tests.test_run_fig518d_native_v2 tests.test_review_fig518d_native_overlay
git add tests/run_fig518d_native_v2.py tests/test_run_fig518d_native_v2.py \
  tests/review_fig518d_native_overlay.py tests/test_review_fig518d_native_overlay.py
git commit -m "构建图5.18d原生数字化一次性证据包"
```

---

### Task 8: Add an independent verifier and exclusive publisher

**Files:**
- Create: `tests/verify_fig518d_native_v2.py`
- Create: `tests/test_verify_fig518d_native_v2.py`

- [ ] **Step 1: Write failing verifier tests**

Tests must reject:

- any input/source/protected/output hash drift;
- unexpected, missing, symlinked, or non-regular run files;
- changed PDF object bytes or incorrect vertical orientation;
- calibration-anchor, method-point, consensus-bound, overlay-coordinate, interval, gate, solution, corner, enum, review, and manifest tampering even if `output_hashes.json` is updated;
- a conflicting pre-existing `verification.json`;
- an existing publication destination;
- copy, manifest, exclusive-rename, `KeyboardInterrupt`, and collision failures.

Run the suite in normal and `-O` modes.

- [ ] **Step 2: Run RED**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest -v tests.test_verify_fig518d_native_v2
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -O -m unittest -v tests.test_verify_fig518d_native_v2
```

- [ ] **Step 3: Implement independent source/pixel verification**

The verifier may import only `fig518d_native_contract`; it must not import calibration, trace A/B, consensus, feasibility, runner, or review production modules. It independently:

- reopens the frozen PDF and extracts object 267 bytes;
- verifies raw and oriented pixel identity;
- recomputes tick centers and affine calibration;
- confirms each method band contains its required source evidence and is inside the valid panel;
- recomputes method-band overlap, consensus centers/bounds, and time bounds;
- confirms every overlay marker coordinate against CSV;
- validates the source-only review and overlay hash.

Set Decimal precision to 50 inside a private `localcontext()` and independently recompute A/B/D, normal-equation LS, analytic NNLS, sign gates, pointwise corners, four case enums, and aggregate enum. Compare published floats with fixed `rel_tol=2e-12, abs_tol=1e-7`.

- [ ] **Step 4: Enforce the Wolfram decision gate**

If `wolfram_trigger.json` says `triggered=false`, the verifier must independently confirm every trigger condition is false. If it says true, publication must stop unless a separately captured `wolfram_verification.json` contains the exact Wolfram input, working precision, raw output, tool identity, local comparison, and a matching conclusion. Do not fabricate that file in Python tests; mock only the verifier schema. A real trigger requires returning to the user before external calculation/publication.

- [ ] **Step 5: Implement verification evidence and publisher**

`verify(run_dir)` exclusively creates an idempotent `verification.json` with:

```python
{
 "schema": "fig518d_native_v2_verification_v1",
 "all_checks_passed": True,
 "digitization_result_enum": result,
 "feasibility_result_enum": feasibility_or_null,
 "verified_trace_count": 2,
 "verified_point_count": 24,
 "source_hashes": {...},
 "run_output_hashes": {...},
 "protected_hashes": {...},
 "verifier_sha256": "...",
 "paper_reproduced": False,
 "author_parameter_identified": False,
 "formal_promotion": False,
}
```

`publish(run_dir, publication_dir)` first performs a fresh verification, copies the exact approved artifact set into a private sibling staging directory, writes `manifest.json` last, verifies every byte/hash/count, rechecks the original run/source/protected identities, and uses Darwin `renamex_np(..., RENAME_EXCL)` for the final no-replace transition. Non-Darwin publication fails closed.

For a valid digitization, the durable directory is exactly:

```python
{
 "source_object_267_raw.jpg", "source_figure_oriented.png",
 "axis_calibration.json", "method_a_points.csv", "method_b_points.csv",
 "consensus_points.csv", "digitization_overlay.png", "provenance.json",
 "feasibility_summary.json", "intervals.csv", "corner_ranges.csv",
 "wolfram_trigger.json", "overlay_review.json", "source_hashes.json",
 "verification.json", "manifest.json",
}
```

For `digitization_inconclusive`, replace the feasibility summary, intervals, and corners with `digitization_failure.json`; retain both method tables and a consensus table whose rejected rows contain the explicit disagreement reason. The verifier must reject any other durable file set.

- [ ] **Step 6: Run GREEN and commit**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest -v tests.test_verify_fig518d_native_v2
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -O -m unittest -v tests.test_verify_fig518d_native_v2
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest -v \
  tests.test_fig518d_native_contract tests.test_fig518d_native_calibration \
  tests.test_fig518d_trace_a tests.test_fig518d_trace_b \
  tests.test_fig518d_native_consensus tests.test_fig518d_native_feasibility \
  tests.test_run_fig518d_native_v2 tests.test_review_fig518d_native_overlay \
  tests.test_verify_fig518d_native_v2
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -O -m unittest -v \
  tests.test_fig518d_native_contract tests.test_fig518d_native_calibration \
  tests.test_fig518d_trace_a tests.test_fig518d_trace_b \
  tests.test_fig518d_native_consensus tests.test_fig518d_native_feasibility \
  tests.test_run_fig518d_native_v2 tests.test_review_fig518d_native_overlay \
  tests.test_verify_fig518d_native_v2
git add tests/verify_fig518d_native_v2.py tests/test_verify_fig518d_native_v2.py
git commit -m "独立复核图5.18d原生数字化证据"
```

---

### Task 9: Execute once, inspect overlay, verify, and publish

**Files:**
- Runtime only: `tmp/fig518d_native_v2_20260902_A/**`
- Create after all gates: `data/provenance/steady53/fig5_18d/paper_curve_native_v2/**`

- [ ] **Step 1: Run the complete pre-execution suite**

Run all nine new suites in normal and `-O` modes using the commands from Task 8 Step 6. Expected: all pass; neither target run nor publication directory is created by tests.

- [ ] **Step 2: Prove collision-free targets and protected baseline**

```bash
test ! -e tmp/fig518d_native_v2_20260902_A
test ! -e data/provenance/steady53/fig5_18d/paper_curve_native_v2
shasum -a 256 \
  final_steady_24a.slx HeXe_property_simulink.m Lithium_property_simulink.m \
  hexe_compressor_lookup.mat radiator_table.mat turbine_table1.mat turbine_table2.mat
git diff --name-only -- final_steady_24a.slx '*.mat' \
  HeXe_property_simulink.m Lithium_property_simulink.m \
  data/provenance/steady53/fig5_18d/paper_curve \
  data/provenance/steady53/fig5_18d/two_state_feasibility
```

Expected: both destinations absent and Git diff empty for every protected path. If a destination exists, stop; do not delete it or choose another id without a new decision.

- [ ] **Step 3: Execute the digitization exactly once**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tests/run_fig518d_native_v2.py \
  --run-dir tmp/fig518d_native_v2_20260902_A
```

Expected: one compact status line. Do not rerun if it fails after publishing its fresh run directory; diagnose that immutable result.

- [ ] **Step 4: Inspect the full-resolution overlay**

Open with `view_image` at original detail:

`tmp/fig518d_native_v2_20260902_A/digitization_overlay.png`

Inspect all 24 samples and both method bands. If any marker is on an axis, label, legend, or wrong curve, do not record a pass; preserve the run and return to the relevant trace-method task with a falsifiable image-only correction.

- [ ] **Step 5: Record the source-only overlay review**

Only if all six statements are true, run the review CLI from Task 7 Step 5. Expected: exclusive creation of `overlay_review.json`, no scientific artifact rewrite.

- [ ] **Step 6: Independently verify**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tests/verify_fig518d_native_v2.py \
  --run-dir tmp/fig518d_native_v2_20260902_A
```

Expected: `all_checks_passed=true`, exact source/protected hashes, 24 verified points, and one allowed result. If Wolfram is triggered, stop here and use the plugin only under Section 8 of the approved design; do not publish until the independent result is captured and agrees.

- [ ] **Step 7: Publish the fresh durable directory**

```bash
/Users/ikunsredemptionmac/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tests/verify_fig518d_native_v2.py \
  --run-dir tmp/fig518d_native_v2_20260902_A \
  --publish-dir data/provenance/steady53/fig5_18d/paper_curve_native_v2
```

Expected: a fresh exact artifact set with `manifest.json` last; no old evidence changes.

- [ ] **Step 8: Run final verification**

Repeat all normal/`-O` tests and verifier, then run:

```bash
git diff --check
git diff --name-only -- final_steady_24a.slx '*.mat' \
  HeXe_property_simulink.m Lithium_property_simulink.m \
  data/provenance/steady53/fig5_18d/paper_curve \
  data/provenance/steady53/fig5_18d/two_state_feasibility
git ls-files tmp/fig518d_native_v2_20260902_A
```

Expected: tests pass, formal/old evidence diff is empty, and tmp has no tracked files.

- [ ] **Step 9: Commit truthful evidence and stop at the result gate**

```bash
git add \
  tests/fig518d_native_contract.py tests/test_fig518d_native_contract.py \
  tests/fig518d_native_calibration.py tests/test_fig518d_native_calibration.py \
  tests/fig518d_trace_a.py tests/test_fig518d_trace_a.py \
  tests/fig518d_trace_b.py tests/test_fig518d_trace_b.py \
  tests/fig518d_native_consensus.py tests/test_fig518d_native_consensus.py \
  tests/fig518d_native_feasibility.py tests/test_fig518d_native_feasibility.py \
  tests/run_fig518d_native_v2.py tests/test_run_fig518d_native_v2.py \
  tests/review_fig518d_native_overlay.py tests/test_review_fig518d_native_overlay.py \
  tests/verify_fig518d_native_v2.py tests/test_verify_fig518d_native_v2.py \
  data/provenance/steady53/fig5_18d/paper_curve_native_v2
git commit -m "完成图5.18d原生分辨率双方法复核"
```

Stop. Report the actual enum with ✅/⚠️/❓/❌ evidence grades. Do not create a temporary SLX or run 500/14000 s without the next result-specific approval.

---

## Completion checklist

- [ ] PDF/object/raw-JPEG identities pass and old evidence remains byte-identical.
- [ ] Oriented PNG is a pixel-exact vertical flip with no resize/interpolation.
- [ ] Nine visible tick anchors produce affine residuals no greater than one native pixel.
- [ ] Method A and B are implementation-independent and each yields two × 12 image-only bands.
- [ ] Every accepted pair passes the overlap gate; disagreement is never averaged away.
- [ ] Pointwise time/temperature bounds include stroke, calibration, and pixel quantization evidence.
- [ ] Overlay matches all CSV coordinates and explicit source-only review is recorded.
- [ ] Four fixed cases use only consensus centers/bounds and return one allowed enum.
- [ ] Independent source/pixel/Decimal verification passes in normal and optimized mode.
- [ ] Wolfram is unused unless the explicit trigger fires; any real trigger pauses publication for captured independent verification.
- [ ] Publication is fresh, exclusive, atomic, manifest-last, and hash-complete.
- [ ] Formal SLX/MAT/property files and old digitization/evidence directories are unchanged.
- [ ] No MATLAB, SLX, 500 s, 14000 s, parameter scan, smoothing, model-guided tracing, fitting, or formal promotion occurs.
