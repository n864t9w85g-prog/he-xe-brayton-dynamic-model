from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "provenance" / "compressor_map" / "nasa_tmx2269"
SOURCE_PDF = ROOT / "sources" / "NASA-TM-X-2269-Ball-Tysl-Weigel-1971.pdf"

EXPECTED_HASHES = {
    SOURCE_PDF: "c008e88a5c851f15125b8c2f9206c625af7f5c54bc632c773f0b17768826362e",
    OUT / "source_page_14.png": "da25a1fc8ae13ebc01cd49c1819fb110356a5b4ea163f29dd7f73df3b9211cf0",
    OUT / "source_page_15.png": "877a6085495a647dd2a7332a79cd5183b270573ea11f94f724214700db837140",
}

# Pixel centers on the unmodified 300 dpi page rasters. Circles were located
# with imfindcircles and visually checked. Polygon markers were located by
# template-assisted inspection and then checked against the source pixels.
POINTS = {
    "pressure_ratio": {
        0.5: [(846, 1393), (941, 1392), (1000, 1403), (1048, 1417), (1094, 1444), (1135, 1475)],
        0.6: [(888, 1307), (994, 1307), (1057, 1313), (1118, 1325), (1153, 1346), (1206, 1386)],
        0.7: [(1016, 1200), (1101, 1199), (1161, 1210), (1224, 1234), (1279, 1273), (1343, 1352), (1392, 1441)],
        0.8: [(1104, 1076), (1183, 1072), (1259, 1081), (1337, 1111), (1409, 1168), (1455, 1257)],
        0.9: [(1228, 920), (1275, 916), (1362, 938), (1432, 969), (1521, 1064), (1603, 1322)],
        1.0: [(1361.6, 725.2), (1430.8, 741.4), (1496.6, 765.4), (1579.9, 816.8), (1701.4, 1080.0)],
    },
    "efficiency": {
        0.5: [(742, 1882), (838, 1806), (894, 1783), (991, 1960), (1032, 2138)],
        0.6: [(785, 1901), (955, 1765), (1013, 1777), (1049, 1814), (1103, 1946)],
        0.7: [(915, 1829), (994, 1782), (1060, 1759), (1123, 1779), (1180, 1851), (1241, 2049), (1287, 2322)],
        0.8: [(1005, 1823), (1082, 1759), (1150, 1750), (1229, 1766), (1293, 1853), (1347, 2007)],
        0.9: [(1124, 1812), (1170, 1776), (1259, 1764), (1326, 1773), (1423, 1865), (1497, 2254)],
        1.0: [(1260.9, 1785.0), (1325.7, 1768.6), (1396.7, 1763.8), (1479.0, 1784.4), (1598.0, 2035.5)],
    },
}

COLORS = {
    0.5: (230, 25, 75),
    0.6: (245, 130, 48),
    0.7: (255, 225, 25),
    0.8: (60, 180, 75),
    0.9: (0, 130, 200),
    1.0: (240, 50, 230),
}

LBM_TO_KG = 0.45359237
X_RANGE_KG_S = (0.2 * LBM_TO_KG, 1.8 * LBM_TO_KG)

CALIBRATION = {
    "pressure_ratio": {
        "source_image": "data/provenance/compressor_map/nasa_tmx2269/source_page_14.png",
        "overlay_image": "data/provenance/compressor_map/nasa_tmx2269/overlay_pressure_ratio.png",
        "axes_pixels": {
            "x_left": 768.7843137254905,
            "x_right": 1716.156862745098,
            "y_top": 720.75,
            "y_bottom": 1550.05,
        },
        "x_range_kg_s": X_RANGE_KG_S,
        "y_range": (1.0, 2.4),
        "grid_fit_max_residual_px": 3.05,
        "figure": "Figure 8",
        "pdf_page": 14,
        "printed_page": 12,
    },
    "efficiency": {
        "source_image": "data/provenance/compressor_map/nasa_tmx2269/source_page_15.png",
        "overlay_image": "data/provenance/compressor_map/nasa_tmx2269/overlay_efficiency.png",
        "axes_pixels": {
            "x_left": 665.3137254901965,
            "x_right": 1613.9803921568632,
            "y_top": 1656.8461538461531,
            "y_bottom": 2365.7692307692305,
        },
        "x_range_kg_s": X_RANGE_KG_S,
        "y_range": (0.3, 0.9),
        "grid_fit_max_residual_px": 1.11,
        "figure": "Figure 10",
        "pdf_page": 15,
        "printed_page": 13,
    },
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def assert_sources_unchanged() -> None:
    for path, expected in EXPECTED_HASHES.items():
        actual = sha256(path)
        if actual != expected:
            raise RuntimeError(f"source hash mismatch for {path}: {actual}")


def physical_coordinates(quantity: str, pixel_x: float, pixel_y: float) -> tuple[float, float]:
    item = CALIBRATION[quantity]
    axes = item["axes_pixels"]
    x_min, x_max = item["x_range_kg_s"]
    y_min, y_max = item["y_range"]
    flow = x_min + (pixel_x - axes["x_left"]) * (x_max - x_min) / (
        axes["x_right"] - axes["x_left"]
    )
    value = y_max - (pixel_y - axes["y_top"]) * (y_max - y_min) / (
        axes["y_bottom"] - axes["y_top"]
    )
    return flow, value


def write_points() -> None:
    with (OUT / "digitized_points.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(
            [
                "quantity",
                "speed_ratio",
                "point_index",
                "pixel_x",
                "pixel_y",
                "flow_eq_kg_s",
                "value",
            ]
        )
        for quantity in ("pressure_ratio", "efficiency"):
            for speed, pixels in POINTS[quantity].items():
                for index, (pixel_x, pixel_y) in enumerate(pixels, start=1):
                    flow, value = physical_coordinates(quantity, pixel_x, pixel_y)
                    writer.writerow(
                        [
                            quantity,
                            f"{speed:.1f}",
                            index,
                            f"{pixel_x:.3f}",
                            f"{pixel_y:.3f}",
                            f"{flow:.12f}",
                            f"{value:.12f}",
                        ]
                    )


def write_overlay(quantity: str) -> None:
    item = CALIBRATION[quantity]
    source = ROOT / item["source_image"]
    destination = ROOT / item["overlay_image"]
    with Image.open(source).convert("RGB") as image:
        draw = ImageDraw.Draw(image)
        for speed, points in POINTS[quantity].items():
            color = COLORS[speed]
            for pixel_x, pixel_y in points:
                x = round(pixel_x)
                y = round(pixel_y)
                draw.ellipse((x - 11, y - 11, x + 11, y + 11), outline=color, width=2)
                draw.line((x - 7, y, x + 7, y), fill=color, width=1)
                draw.line((x, y - 7, x, y + 7), fill=color, width=1)

        # Neighboring speed-line markers overlap at several crossings. Restore
        # each exact center after drawing all outlines so the overlay remains
        # machine-checkable without moving or deleting either source point.
        for speed, points in POINTS[quantity].items():
            for pixel_x, pixel_y in points:
                image.putpixel((round(pixel_x), round(pixel_y)), COLORS[speed])

        design = {
            "pressure_ratio": (1548.2, 778.8),
            "efficiency": (1448.8, 1752.1),
        }[quantity]
        x = round(design[0])
        y = round(design[1])
        draw.rectangle((x - 12, y - 12, x + 12, y + 12), outline=(0, 255, 255), width=2)
        image.save(destination)


def write_calibration() -> None:
    document = {
        "source_report": "NASA TM X-2269",
        "source_pdf": "sources/NASA-TM-X-2269-Ball-Tysl-Weigel-1971.pdf",
        "source_pdf_sha256": EXPECTED_HASHES[SOURCE_PDF],
        "render_dpi": 300,
        "working_fluid": "argon",
        "candidate_use_limitation": (
            "Public NASA source map candidate only; no claim that Xu Chi used this compressor. "
            "Any He-Xe use requires a separately tested and documented similarity transform."
        ),
        "digitization_method": (
            "Marker centers on unmodified 300 dpi page rasters; circle detection plus "
            "template-assisted manual inspection. Physical coordinates use a least-squares "
            "fit through all printed grid lines."
        ),
        "x_axis_primary_units": "lbm/s",
        "lbm_to_kg_exact": LBM_TO_KG,
        "speed_lines": {
            "0.5": {"label_percent": 50, "equivalent_tip_speed_m_s": 162},
            "0.6": {"label_percent": 60, "equivalent_tip_speed_m_s": 195},
            "0.7": {"label_percent": 70, "equivalent_tip_speed_m_s": 227},
            "0.8": {"label_percent": 80, "equivalent_tip_speed_m_s": 260},
            "0.9": {"label_percent": 90, "equivalent_tip_speed_m_s": 292},
            "1.0": {"label_percent": 100, "equivalent_tip_speed_m_s": 325},
        },
        "published_design_conditions": {
            "flow_eq_kg_s": 0.69,
            "pressure_ratio": 2.28,
            "efficiency": 0.80,
            "source": "Report text on printed page 12",
            "role": "independent measured-data check; not inserted into the digitized curves",
        },
        "predicted_design_markers": {
            "flow_eq_kg_s": 0.69,
            "pressure_ratio": 2.30,
            "efficiency": 0.82,
            "pressure_ratio_pixel": [1548.2, 778.8],
            "efficiency_pixel": [1448.8, 1752.1],
            "source": "Report text and Figure 8/Figure 10 filled Design markers",
            "role": "predicted design check; not included as a measured speed-line sample",
        },
        "overlay_colors_rgb": {f"{speed:.1f}": color for speed, color in COLORS.items()},
        "visual_review": {
            "status": "verified",
            "reviewed_on": "2026-08-18",
            "maximum_marker_displacement_px": 2.0,
            "criterion_px": 2.0,
        },
    }
    for quantity, item in CALIBRATION.items():
        source_path = ROOT / item["source_image"]
        document[quantity] = dict(item)
        document[quantity]["source_image_sha256"] = EXPECTED_HASHES[source_path]

    (OUT / "calibration.json").write_text(
        json.dumps(document, indent=2, ensure_ascii=True) + "\n", encoding="utf-8"
    )


def main() -> None:
    assert_sources_unchanged()
    OUT.mkdir(parents=True, exist_ok=True)
    write_points()
    for quantity in ("pressure_ratio", "efficiency"):
        write_overlay(quantity)
    write_calibration()


if __name__ == "__main__":
    main()
