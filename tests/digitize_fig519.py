#!/usr/bin/env python3
"""Deterministically digitize the four traces of thesis Figure 5.19.

This program deliberately consumes only the hash-gated scanned thesis page.  It
does not read a Simulink model, MAT file, model baseline, or any model output.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import stat
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tmp/steady53_recheck_20260827/paper-106.png"
OUTPUT = ROOT / "data/provenance/steady53/fig5_19"
SOURCE_SHA256 = "770d193eaca80742ef5ece0ef5ba6d0bc20ad7aaa8ca2ac9b60a4799d1f0a1e2"
PDF_SHA256 = "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a"
THRESHOLD = 120
X_NEIGHBORHOOD = 1
SAMPLE_TIMES = (10, 15, 20, 30, 40, 50, 75, 100, 150, 200, 230, 300, 400, 450, 495)
ARTIFACT_NAMES = ("source_page_106.png", "paper_points.csv", "provenance.json", "digitization_overlay.png", "README.md")
BASELINE_LAYER_NAMES = ("baseline.mat", "baseline_P_sw.csv", "baseline_WT_sw.csv", "baseline_Wc_sw.csv")
BASELINE_TOP_LEVEL_NAMES = ("baseline_metrics.json", "signal_contract.json")
INITIALIZATION_TOP_LEVEL_NAMES = ("initialization_audit.json",)
BASELINE_LAYER_DIR = "model_baseline"


def registered_paths(include_initialization: bool = False) -> tuple[str, ...]:
    """The closed Figure 5.19 registry at the Task 5 or Task 6 layer."""
    paths = ARTIFACT_NAMES + tuple(f"{BASELINE_LAYER_DIR}/{name}" for name in BASELINE_LAYER_NAMES) + BASELINE_TOP_LEVEL_NAMES
    return paths + (INITIALIZATION_TOP_LEVEL_NAMES if include_initialization else ())


@dataclass(frozen=True)
class Panel:
    panel_id: str
    x_pair: tuple[int, int, float, float]
    y_pair: tuple[int, int, float, float]
    power_allowance_kW: float


PANELS = (
    Panel("a", (179, 503, 0.0, 500.0), (341, 593, 3750.0, 1750.0), 25.0),
    Panel("b", (555, 880, 0.0, 500.0), (338, 580, 2300.0, 1800.0), 6.0),
    Panel("c", (179, 503, 0.0, 500.0), (675, 925, 1350.0, 1100.0), 3.0),
    Panel("d", (555, 881, 0.0, 500.0), (701, 925, 1100.0, 600.0), 8.0),
)


def _hash(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _safe_output(output: Path) -> Path:
    raw = Path(output)
    if not raw.is_absolute():
        raw = ROOT / raw
    if ".." in raw.parts:
        raise RuntimeError("refusing lexical path escape")
    probe = Path(raw.anchor)
    for part in raw.parts[1:]:
        probe /= part
        if os.path.lexists(probe):
            mode = os.lstat(probe).st_mode
            if stat.S_ISLNK(mode):
                raise RuntimeError("refusing symlinked output path")
            if probe != raw and not stat.S_ISDIR(mode):
                raise RuntimeError("output parent is not a directory")
    resolved = raw.resolve(strict=False)
    if ROOT.resolve() not in resolved.parents:
        raise RuntimeError("output must remain under the repository root")
    return resolved


def _source_bytes(source: Path) -> bytes:
    if source.resolve() != SOURCE.resolve() or source.is_symlink():
        raise RuntimeError("only the contracted thesis page may be digitized")
    data = source.read_bytes()
    if _hash(data) != SOURCE_SHA256:
        raise RuntimeError("source page hash does not match the source contract")
    return data


def _pixel_for_time(panel: Panel, time_s: float) -> int:
    left, right, first, last = panel.x_pair
    return round(left + (time_s - first) * (right - left) / (last - first))


def _power_for_pixel(panel: Panel, y: float) -> float:
    top, bottom, top_power, bottom_power = panel.y_pair
    return top_power + (y - top) * (bottom_power - top_power) / (bottom - top)


def _groups_at_x(gray: Image.Image, panel: Panel, x: int) -> list[tuple[int, int, float]]:
    top, bottom, _, _ = panel.y_pair
    dark = []
    for y in range(top + 4, bottom - 3):  # axis-border rejection
        if min(gray.getpixel((xx, y)) for xx in range(x - X_NEIGHBORHOOD, x + X_NEIGHBORHOOD + 1)) < THRESHOLD:
            dark.append(y)
    return _groups_from_dark_y(dark)


def _groups_from_dark_y(dark: list[int]) -> list[tuple[int, int, float]]:
    """Return contiguous ink groups; centers are their arithmetic pixel centers."""
    groups: list[list[int]] = []
    for y in dark:
        if not groups or y > groups[-1][-1] + 1:
            groups.append([y])
        else:
            groups[-1].append(y)
    return [(group[0], group[-1], sum(group) / len(group)) for group in groups]


def _select_group(groups: list[tuple[int, int, float]], later_center: float | None) -> tuple[int, int, float] | None:
    if later_center is not None:
        groups = [group for group in groups if abs(group[2] - later_center) <= 80]
    if not groups:
        return None
    # Fixed image-only tie break: closest to later center, then uppermost center.
    return min(groups, key=lambda group: (0.0 if later_center is None else abs(group[2] - later_center), group[2]))


def extract_bytes(data: bytes) -> tuple[list[dict[str, object]], Image.Image]:
    """Trace each panel from right to left, selecting only image-continuous ink."""
    image = Image.open(io.BytesIO(data)).convert("RGB")
    gray = image.convert("L")
    points: list[dict[str, object]] = []
    for panel in PANELS:
        accepted: list[dict[str, object]] = []
        later_center: float | None = None
        for time_s in reversed(SAMPLE_TIMES):
            x = _pixel_for_time(panel, time_s)
            groups = _groups_at_x(gray, panel, x)
            if not groups:
                raise RuntimeError(f"empty trace column: panel {panel.panel_id}, t={time_s}")
            selected = _select_group(groups, later_center)
            if selected is None:
                raise RuntimeError(f"trace jump exceeds 80 pixels: panel {panel.panel_id}, t={time_s}")
            later_center = selected[2]
            accepted.append({
                "panel_id": panel.panel_id, "trace_id": f"fig5.19-{panel.panel_id}",
                "x_px": x, "y_px": selected[2], "time_s": float(time_s),
                "power_kW": _power_for_pixel(panel, selected[2]),
                "selection_method": "three-column dark-ink contiguous-group continuity; uppermost tie-break",
                "power_allowance_kW": panel.power_allowance_kW, "time_allowance_s": 3,
            })
        points.extend(reversed(accepted))
    return points, image


def extract(source: Path = SOURCE) -> tuple[list[dict[str, object]], Image.Image]:
    return extract_bytes(_source_bytes(source))


def _csv_bytes(rows: list[dict[str, object]]) -> bytes:
    fields = ("panel_id", "trace_id", "x_px", "y_px", "time_s", "power_kW", "selection_method", "power_allowance_kW", "time_allowance_s")
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    for row in rows:
        writer.writerow({key: f"{value:.6f}" if key in {"y_px", "power_kW"} else value for key, value in row.items()})
    return stream.getvalue().encode()


def _overlay_bytes(image: Image.Image, rows: list[dict[str, object]]) -> bytes:
    overlay = image.copy()
    draw = ImageDraw.Draw(overlay)
    colors = {"a": "#e41a1c", "b": "#377eb8", "c": "#4daf4a", "d": "#984ea3"}
    for row in rows:
        x, y = float(row["x_px"]), float(row["y_px"])
        draw.ellipse((x - 3, y - 3, x + 3, y + 3), outline=colors[str(row["panel_id"])], width=2)
    stream = io.BytesIO()
    overlay.save(stream, format="PNG", optimize=False, compress_level=9)
    return stream.getvalue()


def _provenance() -> bytes:
    data = {
        "artifact": "paper-only digitization of Figure 5.19", "source_page": "source_page_106.png",
        "source_page_sha256": SOURCE_SHA256, "source_pdf_sha256": PDF_SHA256,
        "pdf_page": 106, "printed_page": 91, "figure": "5.19", "panels": [panel.__dict__ for panel in PANELS],
        "grayscale_threshold": THRESHOLD, "x_neighborhood": "x-1 through x+1 (width 3)",
        "trace_rule": "for each panel, process t=495 backward; form contiguous dark-pixel y groups; select center nearest accepted later-time center; uppermost center breaks ties",
        "rejections": "reject empty columns, axis-border groups, and groups jumping over 80 px",
        "fixed_times_s": SAMPLE_TIMES, "time_allowance_s": 3,
        "limitations": "scan-limited early near-vertical traces; t=10 is a proxy, not author t0",
        "prohibitions": "no smoothing; no time shifting; no model-guided selection; no model file read; no fitted correction",
        "paper_reproduced": False, "formal_promotion": False,
    }
    return (json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()


def _readme() -> bytes:
    return """# Figure 5.19 paper-only digitization\n\nThis directory is observation evidence from the scanned thesis page only, not a model result or a reproduction claim. It contains 60 points (15 fixed times for each of four panels). The digitizer reads no model file, SLX, MAT file, baseline, or model output.\n\nAt each fixed time it uses the literal pixel calibrations in `provenance.json`, thresholds the three image columns x-1:x+1 at grayscale <120, groups contiguous dark y pixels, and traces backwards from 495 s by nearest image-continuous group center. Ties use the uppermost group center. Axis-border ink, empty columns, and jumps over 80 pixels are rejected.\n\nLimitations: the early trace is nearly vertical and scan-limited; t=10 s is a proxy for the authors' t0, not an asserted original sampling instant. There is no smoothing, time shifting, model-guided choice, fitted correction, or formal promotion. `paper_reproduced = false`; `formal_promotion = false`.\n\n`manifest.csv` is nonrecursive and intentionally excludes itself; it records hashes for every other durable artifact in this directory.\n""".encode()


def manifest_bytes(entries: dict[str, bytes], roles: dict[str, tuple[str, str]]) -> bytes:
    stream = io.StringIO(newline="")
    writer = csv.writer(stream, lineterminator="\n")
    writer.writerow(("path", "bytes", "sha256", "role", "identity"))
    for name in sorted(entries):
        payload = entries[name]
        role, identity = roles[name]
        writer.writerow((name, len(payload), _hash(payload), role, identity))
    return stream.getvalue().encode()


def _manifest(artifacts: dict[str, bytes]) -> bytes:
    roles = {
        "source_page_106.png": ("contracted source", "paper-106-only"),
        "paper_points.csv": ("generated digitization", "paper-106-only"),
        "provenance.json": ("generated provenance", "paper-106-only"),
        "digitization_overlay.png": ("generated overlay", "paper-106-only"),
        "README.md": ("generated documentation", "paper-106-only"),
    }
    # Preserve Task 4's insertion-order bytes for its standalone publication.
    stream = io.StringIO(newline="")
    writer = csv.writer(stream, lineterminator="\n")
    writer.writerow(("path", "bytes", "sha256", "role", "identity"))
    for name, payload in artifacts.items():
        role, identity = roles[name]
        writer.writerow((name, len(payload), _hash(payload), role, identity))
    return stream.getvalue().encode()


def _artifacts_from_source_bytes(source_bytes: bytes) -> dict[str, bytes]:
    if _hash(source_bytes) != SOURCE_SHA256:
        raise RuntimeError("source page hash does not match the source contract")
    rows, image = extract_bytes(source_bytes)
    return {
        "source_page_106.png": source_bytes,
        "paper_points.csv": _csv_bytes(rows),
        "provenance.json": _provenance(),
        "digitization_overlay.png": _overlay_bytes(image, rows),
        "README.md": _readme(),
    }


def _planned(source: Path) -> dict[str, bytes]:
    artifacts = _artifacts_from_source_bytes(_source_bytes(source))
    artifacts["manifest.csv"] = _manifest(artifacts)
    return artifacts


def _manifest_rows(output: Path) -> dict[str, dict[str, str]]:
    manifest = output / "manifest.csv"
    if manifest.is_symlink() or not manifest.is_file():
        raise RuntimeError("manifest is missing or unsafe")
    with manifest.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    base_schema = {"path", "bytes", "sha256", "role", "identity"}
    extended_schema = base_schema | {"storage", "repository_relative_path", "absolute_path"}
    if not rows or set(rows[0]) not in (base_schema, extended_schema):
        raise RuntimeError("manifest schema is invalid")
    indexed = {row["path"]: row for row in rows}
    if len(indexed) != len(rows):
        raise RuntimeError("manifest has duplicate paths")
    return indexed


def _validate_registered_shape(output: Path) -> None:
    include_initialization = os.path.lexists(output / "initialization_audit.json")
    expected = set(registered_paths(include_initialization)) | {"manifest.csv"}
    actual = {str(path.relative_to(output)) for path in output.rglob("*") if path.is_file() or path.is_symlink()}
    if actual != expected:
        raise RuntimeError("artifact set is incomplete or unexpected")
    for path in output.rglob("*"):
        if path.is_symlink():
            raise RuntimeError("symlinked artifact is forbidden")
    layer = output / BASELINE_LAYER_DIR
    if layer.exists() and (not layer.is_dir() or layer.is_symlink()):
        raise RuntimeError("baseline layer is unsafe")


def _check_exact_directory(output: Path, artifacts: dict[str, bytes], allow_baseline_layer: bool = False) -> None:
    if not output.is_dir() or output.is_symlink():
        raise RuntimeError("destination is not a safe directory")
    if allow_baseline_layer:
        _validate_registered_shape(output)
    else:
        names = {entry.name for entry in output.iterdir()}
        if names != set(artifacts):
            raise RuntimeError("artifact set is incomplete or unexpected")
    for name, payload in artifacts.items():
        target = output / name
        if target.is_symlink() or not target.is_file() or target.read_bytes() != payload:
            raise RuntimeError(f"conflicting existing artifact: {name}")


def verify_paper_layer(output: Path = OUTPUT) -> None:
    """Verify only the paper layer against its durable contracted page."""
    output = _safe_output(Path(output))
    if not output.is_dir() or output.is_symlink():
        raise RuntimeError("durable publication directory is missing or unsafe")
    source_bytes = (output / "source_page_106.png").read_bytes()
    artifacts = _artifacts_from_source_bytes(source_bytes)
    rows = _manifest_rows(output)
    if not set(ARTIFACT_NAMES).issubset(rows):
        raise RuntimeError("paper layer rows are missing")
    for name, payload in artifacts.items():
        row = rows[name]
        if row["bytes"] != str(len(payload)) or row["sha256"] != _hash(payload):
            raise RuntimeError(f"paper layer manifest mismatch: {name}")


def _write_file_exclusive(path: Path, payload: bytes) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    try:
        offset = 0
        while offset < len(payload):
            offset += os.write(fd, payload[offset:])
        os.fsync(fd)
    finally:
        os.close(fd)


def _fsync_directory(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _publish_new_atomic(output: Path, artifacts: dict[str, bytes]) -> None:
    staging = output.parent / (output.name + ".staging")
    if os.path.lexists(staging):
        raise RuntimeError("stale staging directory requires manual audit")
    os.mkdir(staging, 0o755)
    try:
        for name, payload in artifacts.items():
            _write_file_exclusive(staging / name, payload)
        _check_exact_directory(staging, artifacts)
        _fsync_directory(staging)
        if os.path.lexists(output):
            raise RuntimeError("destination appeared during publication")
        os.rename(staging, output)
        _fsync_directory(output.parent)
    except Exception:
        # Preserve staging for audit; never delete a path that could be replaced.
        raise


def publish(source: Path = SOURCE, output: Path = OUTPUT) -> None:
    output = _safe_output(Path(output))
    if os.path.lexists(output):
        # A completed baseline layer is owned by Task 5.  Keep this program a
        # no-op for it while still recomputing every paper artifact.
        if (output / BASELINE_LAYER_DIR).exists():
            verify_paper_layer(output)
            _validate_registered_shape(output)
        else:
            artifacts = _planned(Path(source))
            _check_exact_directory(output, artifacts)
        return
    artifacts = _planned(Path(source))
    _publish_new_atomic(output, artifacts)


def verify_only(output: Path = OUTPUT) -> None:
    output = _safe_output(Path(output))
    if not output.is_dir() or output.is_symlink():
        raise RuntimeError("durable publication directory is missing or unsafe")
    if (output / BASELINE_LAYER_DIR).exists():
        _validate_registered_shape(output)
        verify_paper_layer(output)
        rows = _manifest_rows(output)
        include_initialization = os.path.lexists(output / "initialization_audit.json")
        for relative in registered_paths(include_initialization):
            payload = (output / relative).read_bytes()
            row = rows.get(relative)
            if row is None or row["bytes"] != str(len(payload)) or row["sha256"] != _hash(payload):
                raise RuntimeError(f"manifest mismatch: {relative}")
        return
    source_bytes = (output / "source_page_106.png").read_bytes()
    if _hash(source_bytes) != SOURCE_SHA256:
        raise RuntimeError("durable source page hash is wrong")
    artifacts = _artifacts_from_source_bytes(source_bytes)
    artifacts["manifest.csv"] = _manifest(artifacts)
    _check_exact_directory(output, artifacts)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    if args.verify_only:
        verify_only()
    else:
        publish()
    print("POINTS=60 PANELS=4")


if __name__ == "__main__":
    main()
