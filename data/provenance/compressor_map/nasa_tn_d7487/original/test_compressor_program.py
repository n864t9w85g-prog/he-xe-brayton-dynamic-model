from __future__ import annotations

import json
import io
import math
from contextlib import redirect_stderr, redirect_stdout
from dataclasses import fields, replace
from pathlib import Path
import unittest

from outputs.compressor_program import (
    AMT,
    BARR,
    PREC_TABLES,
    CompressorInput,
    CompressorRun,
    OperatingPoint,
    PointStatus,
    build_parser,
    evaluate_operating_point,
    fntgrl,
    linint,
    main,
    run_compressor,
)


OUTPUT_DIR = Path(__file__).resolve().parent
SAMPLE_PATH = OUTPUT_DIR / "sample_input.json"
FORTRAN_PATH = OUTPUT_DIR / "fortran_transcription.f"
README_PATH = OUTPUT_DIR / "README.md"


class InputTests(unittest.TestCase):
    def load_mapping(self) -> dict[str, object]:
        return json.loads(SAMPLE_PATH.read_text(encoding="utf-8"))

    def test_sample_contains_all_published_namelist_inputs(self) -> None:
        compressor_input = CompressorInput.from_json(SAMPLE_PATH)

        self.assertEqual(len(fields(CompressorInput)), 28)
        self.assertEqual(compressor_input.gam, 1.4)
        self.assertEqual(compressor_input.rgas, 287.05)
        self.assertEqual(compressor_input.pop, 101325.0)
        self.assertEqual(compressor_input.top, 288.15)
        self.assertEqual(compressor_input.n, 72000.0)
        self.assertEqual(compressor_input.dit, 0.0813)
        self.assertEqual(compressor_input.mu0, 1.788e-5)
        self.assertEqual(compressor_input.cf, 0.004)
        self.assertEqual(compressor_input.nvovcr, 15)
        self.assertEqual(len(compressor_input.vovcr), 15)
        self.assertEqual(compressor_input.vovcr[0], 0.47)
        self.assertEqual(compressor_input.vovcr[-1], 0.61)
        self.assertEqual(compressor_input.drat, 0.5614)
        self.assertEqual(compressor_input.lamx, 0.5313)
        self.assertEqual(compressor_input.b2x, 25.0)
        self.assertEqual(compressor_input.z, 32.0)
        self.assertEqual(compressor_input.vldrr, 1.14)
        self.assertEqual(compressor_input.b2, 0.0051)
        self.assertEqual(compressor_input.b1mfb, 49.0)
        self.assertEqual(compressor_input.ar, 2.7)
        self.assertEqual(compressor_input.block, 0.9)
        self.assertEqual(compressor_input.al3, 78.0)
        self.assertEqual(compressor_input.adth, 0.00071)
        self.assertEqual(compressor_input.nondes, 1.0)
        self.assertEqual(compressor_input.splt, 1)
        self.assertEqual(compressor_input.al1mf, 0.0)
        self.assertEqual(compressor_input.curvh, 0.0)
        self.assertEqual(compressor_input.curvt, 0.0)
        self.assertEqual(compressor_input.chih, 7.0)
        self.assertEqual(compressor_input.chit, 0.0)

    def test_missing_input_is_rejected(self) -> None:
        mapping = self.load_mapping()
        del mapping["gam"]

        with self.assertRaisesRegex(ValueError, "missing.*gam"):
            CompressorInput.from_mapping(mapping)

    def test_unknown_input_is_rejected(self) -> None:
        mapping = self.load_mapping()
        mapping["mystery"] = 1.0

        with self.assertRaisesRegex(ValueError, "unknown.*mystery"):
            CompressorInput.from_mapping(mapping)

    def test_nvovcr_must_match_array_length(self) -> None:
        mapping = self.load_mapping()
        mapping["nvovcr"] = 14

        with self.assertRaisesRegex(ValueError, "nvovcr"):
            CompressorInput.from_mapping(mapping)

    def test_values_must_be_finite(self) -> None:
        mapping = self.load_mapping()
        mapping["top"] = math.inf

        with self.assertRaisesRegex(ValueError, "top.*finite"):
            CompressorInput.from_mapping(mapping)

    def test_required_positive_value_is_rejected(self) -> None:
        mapping = self.load_mapping()
        mapping["dit"] = 0.0

        with self.assertRaisesRegex(ValueError, "dit.*positive"):
            CompressorInput.from_mapping(mapping)

    def test_vovcr_must_be_strictly_increasing(self) -> None:
        mapping = self.load_mapping()
        mapping["vovcr"][5] = mapping["vovcr"][4]

        with self.assertRaisesRegex(ValueError, "vovcr.*increasing"):
            CompressorInput.from_mapping(mapping)

    def test_splt_is_zero_or_one(self) -> None:
        valid = CompressorInput.from_json(SAMPLE_PATH)

        with self.assertRaisesRegex(ValueError, "splt"):
            replace(valid, splt=2).validate()


class PublishedTableTests(unittest.TestCase):
    def test_axes_match_listing(self) -> None:
        self.assertEqual(AMT, (0.2, 0.4, 0.6, 0.8))
        self.assertEqual(BARR, (0.02, 0.04, 0.06, 0.08, 0.10, 0.12))

    def test_five_tables_have_mach_rows_and_blockage_columns(self) -> None:
        self.assertEqual(len(PREC_TABLES), 5)
        for table in PREC_TABLES:
            self.assertEqual(len(table), len(AMT))
            self.assertTrue(all(len(row) == len(BARR) for row in table))

    def test_published_values_have_correct_orientation(self) -> None:
        prec1, prec2, prec3, prec4, prec5 = PREC_TABLES
        self.assertEqual(prec1[0][0], 0.234)
        self.assertEqual(prec1[3][0], 0.269)
        self.assertEqual(prec1[0][5], 0.166)
        self.assertEqual(prec1[3][5], 0.188)
        self.assertEqual(prec2[3][5], 0.552)
        self.assertEqual(prec3[1][3], 0.680)
        self.assertEqual(prec4[2][4], 0.680)
        self.assertEqual(prec5[3][5], 0.652)


class LinintTests(unittest.TestCase):
    X = (0.0, 1.0, 2.0)
    Y = (10.0, 20.0, 30.0)
    TABLE = (
        (35.0, 65.0, 95.0),
        (37.0, 67.0, 97.0),
        (39.0, 69.0, 99.0),
    )

    def test_returns_exact_grid_corner(self) -> None:
        self.assertEqual(linint(0.0, 10.0, self.X, self.Y, self.TABLE), 35.0)
        self.assertEqual(linint(2.0, 30.0, self.X, self.Y, self.TABLE), 99.0)

    def test_returns_exact_interior_grid_value(self) -> None:
        self.assertEqual(linint(1.0, 20.0, self.X, self.Y, self.TABLE), 67.0)

    def test_bilinear_interpolation_matches_analytic_plane(self) -> None:
        self.assertAlmostEqual(
            linint(0.5, 15.0, self.X, self.Y, self.TABLE),
            51.0,
            places=14,
        )

    def test_uses_first_and_last_intervals_for_endpoint_extrapolation(self) -> None:
        self.assertAlmostEqual(
            linint(-0.5, 5.0, self.X, self.Y, self.TABLE),
            19.0,
            places=14,
        )
        self.assertAlmostEqual(
            linint(2.5, 35.0, self.X, self.Y, self.TABLE),
            115.0,
            places=14,
        )

    def test_published_table_weighting_matches_fortran_orientation(self) -> None:
        expected = (0.224 + 0.233 + 0.215 + 0.223) / 4.0
        self.assertAlmostEqual(
            linint(0.5, 0.05, AMT, BARR, PREC_TABLES[0]),
            expected,
            places=14,
        )

    def test_rejects_axis_with_fewer_than_two_points(self) -> None:
        with self.assertRaisesRegex(ValueError, "at least two"):
            linint(0.0, 15.0, (0.0,), self.Y, ((1.0, 2.0, 3.0),))

    def test_rejects_nonincreasing_axis(self) -> None:
        with self.assertRaisesRegex(ValueError, "strictly increasing"):
            linint(0.5, 15.0, (0.0, 1.0, 1.0), self.Y, self.TABLE)

    def test_rejects_table_dimension_mismatch(self) -> None:
        with self.assertRaisesRegex(ValueError, "dimensions"):
            linint(0.5, 15.0, self.X, self.Y, self.TABLE[:-1])


class FntgrlTests(unittest.TestCase):
    def test_first_call_corrects_provisional_second_station(self) -> None:
        f = [2.0, 5.0, 10.0]
        s = [0.0, 3.5, 0.0]

        fntgrl(3, 1.0, f, s)

        expected_second = (5.0 * 2.0 + 8.0 * 5.0 - 10.0) / 12.0
        expected_third = expected_second + (5.0 * 10.0 + 8.0 * 5.0 - 2.0) / 12.0
        self.assertAlmostEqual(s[0], 0.0, places=14)
        self.assertAlmostEqual(s[1], expected_second, places=14)
        self.assertAlmostEqual(s[2], expected_third, places=14)

    def test_later_call_adds_remaining_interval(self) -> None:
        f = [2.0, 5.0, 10.0, 17.0]
        s = [0.0, 0.0, 0.0, 0.0]
        fntgrl(3, 0.25, f, s)
        previous = s[2]

        fntgrl(4, 0.25, f, s)

        increment = 0.25 * (5.0 * 17.0 + 8.0 * 10.0 - 5.0) / 12.0
        self.assertAlmostEqual(s[3], previous + increment, places=14)

    def test_constant_function_integrates_to_interval_length(self) -> None:
        f = [3.0, 3.0, 3.0, 3.0]
        s = [0.0, 1.5, 0.0, 0.0]

        fntgrl(3, 0.5, f, s)
        fntgrl(4, 0.5, f, s)

        self.assertAlmostEqual(s[1], 1.5, places=14)
        self.assertAlmostEqual(s[2], 3.0, places=14)
        self.assertAlmostEqual(s[3], 4.5, places=14)

    def test_linear_function_is_exact_at_every_available_station(self) -> None:
        f = [1.0, 3.0, 5.0, 7.0]
        s = [0.0, 2.0, 0.0, 0.0]

        fntgrl(3, 1.0, f, s)
        fntgrl(4, 1.0, f, s)

        self.assertAlmostEqual(s[1], 2.0, places=14)
        self.assertAlmostEqual(s[2], 6.0, places=14)
        self.assertAlmostEqual(s[3], 12.0, places=14)

    def test_rejects_station_before_first_valid_call(self) -> None:
        with self.assertRaisesRegex(ValueError, "station 3"):
            fntgrl(2, 1.0, [1.0, 2.0], [0.0, 0.0])

    def test_rejects_array_too_short_for_station(self) -> None:
        with self.assertRaisesRegex(ValueError, "station 4"):
            fntgrl(4, 1.0, [1.0, 2.0, 3.0], [0.0, 0.0, 0.0])

    def test_rejects_nonpositive_or_nonfinite_spacing(self) -> None:
        for spacing in (0.0, -1.0, math.inf):
            with self.subTest(spacing=spacing):
                with self.assertRaisesRegex(ValueError, "deltar"):
                    fntgrl(3, spacing, [1.0, 2.0, 3.0], [0.0, 0.0, 0.0])


class OperatingPointTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = CompressorInput.from_json(SAMPLE_PATH)

    def test_published_100_percent_speed_point_at_vovcr_054(self) -> None:
        point = evaluate_operating_point(self.config, 0.54)

        self.assertIsInstance(point, OperatingPoint)
        self.assertEqual(point.status, PointStatus.VALID)
        self.assertAlmostEqual(point.vovcr, 0.54, places=14)
        self.assertAlmostEqual(point.equivalent_flow, 0.675, delta=0.0005)
        self.assertAlmostEqual(point.pressure_ratio, 6.465, delta=0.0005)
        self.assertAlmostEqual(point.total_efficiency, 0.780, delta=0.0005)
        self.assertAlmostEqual(point.deigv, 0.0, delta=0.00005)
        self.assertAlmostEqual(point.deinc, 0.00042, delta=0.00005)
        self.assertAlmostEqual(point.debl, 0.03097, delta=0.00005)
        self.assertAlmostEqual(point.desf, 0.05513, delta=0.00005)
        self.assertAlmostEqual(point.dedf, 0.03307, delta=0.00005)
        self.assertAlmostEqual(point.derc, 0.02587, delta=0.00005)
        self.assertAlmostEqual(point.devld, 0.02407, delta=0.00005)
        self.assertAlmostEqual(point.devd, 0.05096, delta=0.00005)

    def test_efficiency_equals_one_minus_all_decrements(self) -> None:
        point = evaluate_operating_point(self.config, 0.54)
        decrement_sum = sum(
            (
                point.deigv,
                point.deinc,
                point.debl,
                point.desf,
                point.dedf,
                point.derc,
                point.devld,
                point.devd,
            )
        )

        self.assertAlmostEqual(point.total_efficiency, 1.0 - decrement_sum, places=12)

    def test_point_calculation_is_deterministic_and_finite(self) -> None:
        first = evaluate_operating_point(self.config, 0.54)
        second = evaluate_operating_point(self.config, 0.54)

        self.assertEqual(first, second)
        numeric_values = (
            first.equivalent_flow,
            first.pressure_ratio,
            first.total_efficiency,
            first.deigv,
            first.deinc,
            first.debl,
            first.desf,
            first.dedf,
            first.derc,
            first.devld,
            first.devd,
        )
        self.assertTrue(all(math.isfinite(value) for value in numeric_values))

    def test_negative_exit_velocity_reports_irrational_exit_triangle(self) -> None:
        high_backsweep = replace(self.config, b2x=60.0)

        point = evaluate_operating_point(high_backsweep, 0.54)

        self.assertEqual(point.status, PointStatus.IRRATIONAL_EXIT_TRIANGLE)
        self.assertIn("exit triangle", point.message.lower())

    def test_nonfinite_or_nonpositive_vovcr_is_rejected(self) -> None:
        for vovcr in (0.0, -0.1, math.inf, math.nan):
            with self.subTest(vovcr=vovcr):
                with self.assertRaisesRegex(ValueError, "vovcr"):
                    evaluate_operating_point(self.config, vovcr)


class CompressorRunTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = CompressorInput.from_json(SAMPLE_PATH)

    def test_sample_two_pass_run_matches_published_range(self) -> None:
        result = run_compressor(self.config)

        self.assertIsInstance(result, CompressorRun)
        self.assertTrue(result.choke_reached)
        self.assertAlmostEqual(result.surge_flow, 0.614, delta=0.0005)
        self.assertAlmostEqual(result.choke_flow, 0.719, delta=0.0005)
        self.assertEqual(len(result.points), 12)
        self.assertEqual(result.points[0].vovcr, 0.48)
        self.assertEqual(result.points[-1].vovcr, 0.59)
        self.assertEqual(result.points[-1].status, PointStatus.INCIDENCE_CHOKE)
        self.assertTrue(any("0.47" in message for message in result.diagnostics))

    def test_points_remain_ordered_and_bounded_by_surge_and_choke(self) -> None:
        result = run_compressor(self.config)
        flows = [point.equivalent_flow for point in result.points]

        self.assertEqual(flows, sorted(flows))
        self.assertTrue(all(flow >= result.surge_flow for flow in flows))
        self.assertTrue(all(flow <= result.choke_flow + 1e-12 for flow in flows))

    def test_missing_choke_deletes_incomplete_performance_output(self) -> None:
        shortened = replace(
            self.config,
            vovcr=self.config.vovcr[:-3],
            nvovcr=self.config.nvovcr - 3,
        )

        result = run_compressor(shortened)

        self.assertFalse(result.choke_reached)
        self.assertIsNone(result.choke_flow)
        self.assertIsNone(result.surge_flow)
        self.assertEqual(result.points, ())
        self.assertTrue(any("not been reached" in text.lower() for text in result.diagnostics))


class CliTests(unittest.TestCase):
    def test_help_names_json_input(self) -> None:
        help_text = build_parser().format_help()

        self.assertIn("input_json", help_text)
        self.assertIn("NASA TN D-7487", help_text)

    def test_sample_cli_prints_summary_and_table(self) -> None:
        stdout = io.StringIO()
        stderr = io.StringIO()

        with redirect_stdout(stdout), redirect_stderr(stderr):
            exit_code = main([str(SAMPLE_PATH)])

        self.assertEqual(exit_code, 0)
        self.assertEqual(stderr.getvalue(), "")
        self.assertIn("PERCENT NDES", stdout.getvalue())
        self.assertIn("SURGE FLOW RATE", stdout.getvalue())
        self.assertIn("VOVCR", stdout.getvalue())
        self.assertIn("6.465", stdout.getvalue())

    def test_invalid_input_path_returns_nonzero(self) -> None:
        stdout = io.StringIO()
        stderr = io.StringIO()

        with redirect_stdout(stdout), redirect_stderr(stderr):
            exit_code = main([str(OUTPUT_DIR / "missing.json")])

        self.assertEqual(exit_code, 2)
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("error:", stderr.getvalue().lower())


class ArtifactTests(unittest.TestCase):
    def test_fortran_transcription_contains_all_program_units(self) -> None:
        source = FORTRAN_PATH.read_text(encoding="utf-8")

        self.assertIn("NASA TN D-7487", source)
        self.assertIn("NAMELIST /INPUT/", source)
        self.assertIn("DATA (AMT(I),I=1,4)", source)
        self.assertIn("DATA ((PREC1(I,J),I=1,4),J=1,6)", source)
        self.assertIn("CALL LININT", source)
        self.assertIn("CALL FNTGRL", source)
        self.assertIn("SUBROUTINE LININT", source)
        self.assertIn("SUBROUTINE FNTGRL", source)
        self.assertIn("RECONSTRUCTED", source)
        self.assertIn("NO ORIGINAL FORTRAN LISTING", source)

    def test_readme_documents_provenance_commands_and_limits(self) -> None:
        readme = README_PATH.read_text(encoding="utf-8")

        for required_text in (
            "NASA TN D-7487",
            "report pages 26-33",
            "report page 34",
            "report page 35",
            "python3 outputs/compressor_program.py outputs/sample_input.json",
            "python3 -m unittest -v outputs/test_compressor_program.py",
            "python3 -m py_compile",
            "FNTGRL",
            "reconstructed",
            "JSON",
            "Units",
            "Validation",
        ):
            with self.subTest(required_text=required_text):
                self.assertIn(required_text, readme)


if __name__ == "__main__":
    unittest.main()
