#!/usr/bin/env python3
"""NASA TN D-7487 centrifugal-compressor performance program.

This module is a structured Python translation of the printed FORTRAN listing.
The main numerical model is implemented incrementally; the input contract and
published diffuser pressure-recovery tables are defined here first.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, fields
from enum import Enum
import json
import math
from pathlib import Path
import sys
from typing import Any, ClassVar, Mapping, Sequence, Tuple


AMT: Tuple[float, ...] = (0.2, 0.4, 0.6, 0.8)
BARR: Tuple[float, ...] = (0.02, 0.04, 0.06, 0.08, 0.10, 0.12)

# The FORTRAN DATA statements fill PREC(I,J) with I (Mach) varying fastest.
# These Python tables are transposed to table[mach_index][blockage_index].
PREC1 = (
    (0.234, 0.215, 0.207, 0.193, 0.183, 0.166),
    (0.244, 0.224, 0.215, 0.199, 0.190, 0.176),
    (0.257, 0.233, 0.223, 0.206, 0.196, 0.182),
    (0.269, 0.243, 0.232, 0.212, 0.202, 0.188),
)
PREC2 = (
    (0.644, 0.620, 0.590, 0.562, 0.538, 0.510),
    (0.673, 0.638, 0.606, 0.576, 0.551, 0.524),
    (0.696, 0.656, 0.623, 0.590, 0.564, 0.538),
    (0.722, 0.674, 0.639, 0.605, 0.578, 0.552),
)
PREC3 = (
    (0.782, 0.750, 0.708, 0.672, 0.652, 0.604),
    (0.789, 0.756, 0.716, 0.680, 0.648, 0.612),
    (0.796, 0.762, 0.724, 0.687, 0.654, 0.619),
    (0.802, 0.768, 0.732, 0.695, 0.660, 0.626),
)
PREC4 = (
    (0.842, 0.800, 0.752, 0.710, 0.675, 0.630),
    (0.838, 0.800, 0.756, 0.713, 0.678, 0.635),
    (0.833, 0.800, 0.760, 0.716, 0.680, 0.640),
    (0.828, 0.800, 0.763, 0.719, 0.683, 0.646),
)
PREC5 = (
    (0.878, 0.832, 0.780, 0.736, 0.692, 0.644),
    (0.865, 0.825, 0.780, 0.735, 0.694, 0.647),
    (0.852, 0.818, 0.780, 0.735, 0.695, 0.650),
    (0.838, 0.812, 0.780, 0.734, 0.696, 0.652),
)
PREC_TABLES = (PREC1, PREC2, PREC3, PREC4, PREC5)

MWRMS = (0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2)
CINC60 = (-10.5, -5.0, -2.0, 1.5, 2.5, 4.0, 5.0, 5.0)
CINC50 = (-15.0, -7.5, -3.0, 1.5, 4.0, 6.5, 9.0, 11.0)
CINC40 = (-20.0, -12.0, -5.0, 1.5, 5.0, 8.0, 11.5, 14.5)
DIFLEM = (0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0)
FLRNG = (0.48, 0.56, 0.64, 0.72, 0.79, 0.84, 0.89)

DEG_TO_RAD = 0.01745
RAD_TO_DEG = 57.29577
PI = 3.14159


def linint(
    x1: float,
    y1: float,
    x: Sequence[float],
    y: Sequence[float],
    table: Sequence[Sequence[float]],
) -> float:
    """Translate ``LININT`` from report page 34.

    The printed routine selects the first upper bound on each axis and uses the
    final interval if the query is above the table. Consequently it linearly
    extrapolates outside either endpoint; this implementation preserves that
    behavior for valid, strictly increasing axes.
    """

    if len(x) < 2 or len(y) < 2:
        raise ValueError("LININT axes must contain at least two points")
    if not all(math.isfinite(value) for value in (*x, *y, x1, y1)):
        raise ValueError("LININT axes and query values must be finite")
    if not all(left < right for left, right in zip(x, x[1:])):
        raise ValueError("LININT axes must be strictly increasing")
    if not all(left < right for left, right in zip(y, y[1:])):
        raise ValueError("LININT axes must be strictly increasing")
    if len(table) != len(x) or any(len(row) != len(y) for row in table):
        raise ValueError("LININT table dimensions must match its axes")
    if not all(math.isfinite(value) for row in table for value in row):
        raise ValueError("LININT table values must be finite")

    def upper_index(query: float, axis: Sequence[float]) -> int:
        for index in range(1, len(axis)):
            if query <= axis[index]:
                return index
        return len(axis) - 1

    j3 = upper_index(x1, x)
    j4 = upper_index(y1, y)
    j1 = j3 - 1
    j2 = j4 - 1
    eps1 = (x1 - x[j1]) / (x[j3] - x[j1])
    eps2 = (y1 - y[j2]) / (y[j4] - y[j2])
    eps3 = 1.0 - eps1
    eps4 = 1.0 - eps2
    return (
        table[j1][j2] * eps3 * eps4
        + table[j3][j2] * eps1 * eps4
        + table[j1][j4] * eps2 * eps3
        + table[j3][j4] * eps1 * eps2
    )


def fntgrl(
    no: int,
    deltar: float,
    f: Sequence[float],
    s: list[float],
) -> None:
    """Reconstruct ``FNTGRL`` from the formulas on report page 35.

    ``no`` is the original 1-based FORTRAN station number. The main listing
    provisionally initializes ``S(2)`` with a trapezoid because ``F(3)`` is not
    yet available. At the first call (``no == 3``), the report's special
    second-interval formula replaces that provisional value. The current and
    subsequent intervals then use the report's remaining-interval recurrence.

    The report explicitly states that the original FORTRAN listing for this
    routine is unavailable; this function is therefore a formula-faithful
    reconstruction rather than a transcription.
    """

    if isinstance(no, bool) or not isinstance(no, int) or no < 3:
        raise ValueError("FNTGRL first valid call is at FORTRAN station 3")
    if not math.isfinite(deltar) or deltar <= 0.0:
        raise ValueError("FNTGRL deltar must be finite and positive")
    if len(f) < no or len(s) < no:
        raise ValueError(f"FNTGRL arrays are too short for station {no}")
    if not all(math.isfinite(float(value)) for value in f[:no]):
        raise ValueError("FNTGRL function values must be finite")
    if not all(math.isfinite(float(value)) for value in s[: no - 1]):
        raise ValueError("FNTGRL accumulated values must be finite")

    index = no - 1
    if no == 3:
        s[1] = deltar * (5.0 * f[0] + 8.0 * f[1] - f[2]) / 12.0
    s[index] = s[index - 1] + deltar * (
        5.0 * f[index] + 8.0 * f[index - 1] - f[index - 2]
    ) / 12.0


@dataclass(frozen=True)
class CompressorInput:
    """Validated equivalent of the listing's ``NAMELIST /INPUT/`` values."""

    gam: float
    rgas: float
    pop: float
    top: float
    n: float
    dit: float
    mu0: float
    cf: float
    vovcr: Tuple[float, ...]
    nvovcr: int
    drat: float
    lamx: float
    b2x: float
    z: float
    vldrr: float
    b2: float
    b1mfb: float
    ar: float
    block: float
    al3: float
    adth: float
    nondes: float
    splt: int
    al1mf: float
    curvh: float
    curvt: float
    chih: float
    chit: float

    _INTEGER_FIELDS: ClassVar[frozenset[str]] = frozenset({"nvovcr", "splt"})
    _POSITIVE_FIELDS: ClassVar[frozenset[str]] = frozenset(
        {
            "rgas",
            "pop",
            "top",
            "n",
            "dit",
            "mu0",
            "cf",
            "drat",
            "lamx",
            "z",
            "vldrr",
            "b2",
            "ar",
            "block",
            "adth",
            "nondes",
        }
    )

    @classmethod
    def from_json(cls, path: Path | str) -> "CompressorInput":
        try:
            data = json.loads(Path(path).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise ValueError(f"cannot read compressor input {path}: {exc}") from exc
        if not isinstance(data, dict):
            raise ValueError("compressor input must be a JSON object")
        return cls.from_mapping(data)

    @classmethod
    def from_mapping(cls, mapping: Mapping[str, Any]) -> "CompressorInput":
        names = {field.name for field in fields(cls)}
        supplied = set(mapping)
        missing = sorted(names - supplied)
        unknown = sorted(supplied - names)
        if missing:
            raise ValueError(f"missing input fields: {', '.join(missing)}")
        if unknown:
            raise ValueError(f"unknown input fields: {', '.join(unknown)}")

        values: dict[str, Any] = {}
        for name in names:
            raw = mapping[name]
            if name == "vovcr":
                if isinstance(raw, (str, bytes)) or not isinstance(raw, Sequence):
                    raise ValueError("vovcr must be a numeric sequence")
                try:
                    values[name] = tuple(float(value) for value in raw)
                except (TypeError, ValueError) as exc:
                    raise ValueError("vovcr must be a numeric sequence") from exc
            elif name in cls._INTEGER_FIELDS:
                if isinstance(raw, bool) or not isinstance(raw, (int, float)):
                    raise ValueError(f"{name} must be an integer")
                number = float(raw)
                if not number.is_integer():
                    raise ValueError(f"{name} must be an integer")
                values[name] = int(number)
            else:
                if isinstance(raw, bool):
                    raise ValueError(f"{name} must be numeric")
                try:
                    values[name] = float(raw)
                except (TypeError, ValueError) as exc:
                    raise ValueError(f"{name} must be numeric") from exc

        instance = cls(**values)
        return instance.validate()

    def validate(self) -> "CompressorInput":
        for field in fields(self):
            value = getattr(self, field.name)
            if field.name == "vovcr":
                if not value:
                    raise ValueError("vovcr must contain at least one value")
                if not all(math.isfinite(item) for item in value):
                    raise ValueError("vovcr values must be finite")
                if not all(item > 0.0 for item in value):
                    raise ValueError("vovcr values must be positive")
                if not all(a < b for a, b in zip(value, value[1:])):
                    raise ValueError("vovcr must be strictly increasing")
            elif isinstance(value, float) and not math.isfinite(value):
                raise ValueError(f"{field.name} must be finite")

        if self.gam <= 1.0:
            raise ValueError("gam must be greater than 1")
        for name in self._POSITIVE_FIELDS:
            if getattr(self, name) <= 0.0:
                raise ValueError(f"{name} must be positive")
        if self.nvovcr != len(self.vovcr):
            raise ValueError("nvovcr must equal the number of vovcr values")
        if self.nvovcr > 15:
            raise ValueError("nvovcr exceeds the listing's 15-value array")
        if self.splt not in (0, 1):
            raise ValueError("splt must be 0 or 1")
        if not 0.0 < self.lamx < 1.0:
            raise ValueError("lamx must lie between 0 and 1")
        if not 0.0 < self.drat <= 1.0:
            raise ValueError("drat must lie between 0 and 1")
        if not 0.0 < self.block <= 1.0:
            raise ValueError("block must lie between 0 and 1")
        return self


class PointStatus(Enum):
    VALID = "valid"
    INCIDENCE_CHOKE = "incidence_choke"
    THROAT_CHOKE = "throat_choke"
    IRRATIONAL_EXIT_TRIANGLE = "irrational_exit_triangle"
    NUMERICAL_FAILURE = "numerical_failure"


@dataclass(frozen=True)
class OperatingPoint:
    vovcr: float
    status: PointStatus
    message: str
    equivalent_flow: float
    pressure_ratio: float
    total_efficiency: float
    deigv: float
    deinc: float
    debl: float
    desf: float
    dedf: float
    derc: float
    devld: float
    devd: float
    throat_mach: float
    incidence_choke: bool
    throat_choke: bool


def _invalid_point(
    vovcr: float,
    status: PointStatus,
    message: str,
    equivalent_flow: float = math.nan,
) -> OperatingPoint:
    return OperatingPoint(
        vovcr=vovcr,
        status=status,
        message=message,
        equivalent_flow=equivalent_flow,
        pressure_ratio=math.nan,
        total_efficiency=math.nan,
        deigv=math.nan,
        deinc=math.nan,
        debl=math.nan,
        desf=math.nan,
        dedf=math.nan,
        derc=math.nan,
        devld=math.nan,
        devd=math.nan,
        throat_mach=math.nan,
        incidence_choke=False,
        throat_choke=False,
    )


def _interpolate_1d(query: float, axis: Sequence[float], values: Sequence[float]) -> float:
    if len(axis) != len(values) or len(axis) < 2:
        raise ValueError("interpolation arrays must have matching lengths")
    upper = len(axis) - 1
    for index in range(1, len(axis)):
        if query <= axis[index]:
            upper = index
            break
    lower = upper - 1
    fraction = (query - axis[lower]) / (axis[upper] - axis[lower])
    return values[lower] + fraction * (values[upper] - values[lower])


def _incidence_limit(relative_mach: float, blade_angle_deg: float) -> float:
    if 40.0 <= blade_angle_deg <= 50.0:
        cinc1 = _interpolate_1d(relative_mach, MWRMS, CINC60)
        cinc2 = _interpolate_1d(relative_mach, MWRMS, CINC50)
        return cinc1 + (60.0 - blade_angle_deg) / 10.0 * (cinc2 - cinc1)
    cinc1 = _interpolate_1d(relative_mach, MWRMS, CINC50)
    cinc2 = _interpolate_1d(relative_mach, MWRMS, CINC40)
    return cinc1 + (50.0 - blade_angle_deg) / 10.0 * (cinc2 - cinc1)


def _pressure_recovery(area_ratio: float, mach: float, blockage: float) -> float:
    if not 1.2 < area_ratio < 5.0:
        raise ValueError("ar must lie strictly between 1.2 and 5.0")
    boundaries = (1.2, 2.0, 3.0, 4.0, 5.0)
    lower = 0
    for index in range(1, len(boundaries)):
        if area_ratio < boundaries[index]:
            lower = index - 1
            break
    left = linint(mach, blockage, AMT, BARR, PREC_TABLES[lower])
    right = linint(mach, blockage, AMT, BARR, PREC_TABLES[lower + 1])
    fraction = (area_ratio - boundaries[lower]) / (
        boundaries[lower + 1] - boundaries[lower]
    )
    return left + fraction * (right - left)


def evaluate_operating_point(config: CompressorInput, vovcr: float) -> OperatingPoint:
    """Evaluate one trial point in the order printed on report pages 27-32."""

    if not math.isfinite(vovcr) or vovcr <= 0.0:
        raise ValueError("vovcr must be finite and positive")

    gam = config.gam
    rgas = config.rgas
    pop = config.pop
    top = config.top
    g1 = gam + 1.0
    g2 = gam - 1.0
    cp = gam * rgas / g2
    b2x = config.b2x * DEG_TO_RAD
    al3 = config.al3 * DEG_TO_RAD
    al1mf = config.al1mf * DEG_TO_RAD
    chih = config.chih * DEG_TO_RAD
    chit = config.chit * DEG_TO_RAD
    flfunc = math.sqrt(gam / rgas * (2.0 / g1) ** (g1 / g2))
    rop = pop / rgas / top
    vcr = math.sqrt(2.0 * gam / g1 * rgas * top)
    uit = PI * config.n * config.nondes * config.dit / 60.0

    try:
        # Inducer inlet and incidence, report pages 27-29.
        b1mfb = config.b1mfb * DEG_TO_RAD
        vui_t = 0.0
        vui_mf = 0.0
        vui_h = 0.0
        vmi_h = vovcr * vcr
        u2 = uit / config.drat
        d2 = config.dit / config.drat
        ui_h = uit * config.lamx
        di_h = config.dit * config.lamx
        dmf = math.sqrt(config.dit**2 * (1.0 + config.lamx**2) / 2.0)
        ui_mf = uit * dmf / config.dit
        chimf = (chit - chih) * (dmf - di_h) / (config.dit - di_h) + chih
        curvmf = (
            (config.curvt - config.curvh)
            * (dmf - di_h)
            / (config.dit - di_h)
            + config.curvh
        )
        h0 = (dmf - di_h) / 2.0
        h1 = (config.dit - dmf) / 2.0
        fint = h0 / 2.0 * (config.curvh + curvmf)
        vmult_mf = math.exp(fint)
        vmi_mf = vmult_mf * vmi_h
        gint = (h0 + h1) / 6.0 * (
            (2.0 - h1 / h0) * config.curvh
            + (h0 + h1) ** 2 / h0 / h1 * curvmf
            + (2.0 - h0 / h1) * config.curvt
        )
        vmult_t = math.exp(gint)
        vmi_t = vmult_t * vmi_h
        vmi_hn = vmi_h * math.cos(chih)
        vmi_mfn = vmi_mf * math.cos(chimf)
        vmi_tn = vmi_t * math.cos(chit)
        rhg_h = rop * (1.0 - vmi_h**2 / (2.0 * cp * top)) ** (1.0 / g2)
        rhg_mf = rop * (1.0 - vmi_mf**2 / (2.0 * cp * top)) ** (1.0 / g2)
        rhg_t = rop * (1.0 - vmi_t**2 / (2.0 * cp * top)) ** (1.0 / g2)
        fcn1 = rhg_h * vmi_hn * di_h / 2.0
        fcn2 = rhg_mf * vmi_mfn * dmf / 2.0
        fcn3 = rhg_t * vmi_tn * config.dit / 2.0
        sw = (h0 + h1) / 6.0 * (
            (2.0 - h1 / h0) * fcn1
            + (h0 + h1) ** 2 / h0 / h1 * fcn2
            + (2.0 - h0 / h1) * fcn3
        ) * 6.28318

        dhigv = 0.0
        vi_mf = math.hypot(vmi_mf, vui_mf)
        t1 = top - vi_mf**2 / (2.0 * cp)
        p1p = pop
        popp1 = (1.0 - vi_mf**2 / (2.0 * cp * top)) ** (gam / g2)
        p1 = p1p * popp1
        r1p = p1p / rgas / top
        r1 = r1p * (p1 / p1p) ** (1.0 / gam)
        re = u2 * d2 / config.mu0 * rop

        alstag = al1mf / 2.0
        es = 0.0076 / (math.cos(al1mf) - 0.025) * (
            1.0 + math.cos(alstag) / 0.7
        )
        if al1mf >= 0.001:
            vovcr1 = vovcr
            for _ in range(5000):
                vovcr1 += 0.001
                ake = (vovcr1 * vcr) ** 2 / 2.0
                popp1 = (1.0 - ake / cp / top) ** (gam / g2)
                ake1d = ake / (1.0 - es)
                p1oppo = (1.0 - ake1d / cp / top) ** (gam / g2)
                p1p = pop * p1oppo / popp1
                r1p = p1p / rgas / top
                p1 = p1p * popp1
                r1 = r1p * popp1 ** (1.0 / gam)
                q1 = (
                    PI
                    * config.dit**2
                    * (1.0 - config.lamx**2)
                    * vovcr1
                    * vcr
                    * math.cos(al1mf)
                    / 4.0
                )
                if q1 * r1 >= sw:
                    break
            else:
                return _invalid_point(
                    vovcr, PointStatus.NUMERICAL_FAILURE, "inlet swirl iteration failed"
                )
            vui_mf = vovcr1 * vcr * math.sin(al1mf)
            vmi_mf = vovcr1 * vcr * math.cos(al1mf)
            vi_mf = math.hypot(vui_mf, vmi_mf)
            t1 = top - vi_mf**2 / (2.0 * cp)
            xk = vui_mf**2 + 2.0 * vmi_mf**2
            xc = vui_mf / dmf * 2.0
            vui_t = xc * config.dit / 2.0
            vui_h = xc * di_h / 2.0
            vmi_t = math.sqrt(xk - 2.0 * vui_t**2)
            vmi_h = math.sqrt(xk - 2.0 * vui_h**2)
            dhigv = es * ake1d

        vi_t = math.hypot(vmi_t, vui_t)
        wui_t = uit - vui_t
        b1 = math.atan(wui_t / vmi_t)
        wi_t = math.hypot(vmi_t, wui_t)
        wui_h = ui_h - vui_h
        wi_h = math.hypot(vmi_h, wui_h)
        a1 = math.sqrt(gam * rgas * t1)
        wui_mf = ui_mf - vui_mf
        wi_mf = math.hypot(vmi_mf, wui_mf)
        rmrms = wi_mf / a1
        bi_mf = math.atan(wui_mf / vmi_mf)
        inc = (bi_mf - b1mfb) * RAD_TO_DEG
        eps = math.atan(
            (1.0 - config.block)
            * math.tan(bi_mf)
            / (1.0 + config.block * math.tan(bi_mf) ** 2)
        )
        bopt = bi_mf - eps
        t1pp = t1 + wi_mf**2 / (2.0 * cp)
        wcr = math.sqrt(2.0 * gam / g1 * rgas * t1pp)
        wi_mf_effective = wi_mf * math.cos(bopt - b1mfb)
        t0t1 = 1.0 - g2 / g1 * (wi_mf_effective / wcr) ** 2
        t1 = t1pp * t0t1
        wl = wi_mf * math.sin(abs(bopt - bi_mf))
        dhinc = wl**2 / 2.0
        p1fmf = p1p * math.exp(-dhinc / t1 / rgas)
        delta = pop / 101325.35
        theta = top / 288.15
        ewf = sw * math.sqrt(theta) / delta
        incidence_choke = inc <= _incidence_limit(rmrms, config.b1mfb)

        # Impeller exit and losses, report pages 29-30.
        t2pp = t1pp + (u2**2 - ui_mf**2) / (2.0 * cp)
        phi = vmi_mf / u2
        epslim = 1.0 / math.exp(8.16 * math.cos(b2x) / config.z)
        vsl = math.sqrt(math.cos(b2x)) * u2 / config.z**0.7
        if dmf / d2 > epslim:
            blend = (dmf / d2 - epslim) / (1.0 - epslim)
            vsl = (
                u2 * math.sqrt(math.cos(b2x)) / config.z**0.7 * (1.0 - blend**3)
                + u2 * blend**3
            )
        dhest = u2**2
        t2pest = (dhest / cp / top + 1.0) * top
        r2g = r1 * (t2pest / top) ** (1.0 / g2)

        converged = False
        for _ in range(1000):
            rho2 = r2g
            vm2 = sw / (PI * rho2 * d2 * config.b2)
            vu2 = u2 - vm2 * math.tan(b2x) - vsl
            if vm2 <= 0.0 or vu2 <= 0.0:
                return _invalid_point(
                    vovcr,
                    PointStatus.IRRATIONAL_EXIT_TRIANGLE,
                    "irrational impeller exit triangle",
                    ewf,
                )
            wu2 = u2 - vu2
            w2 = math.hypot(wu2, vm2)
            if vsl * math.cos(b2x) / w2 > 1.0:
                return _invalid_point(
                    vovcr,
                    PointStatus.IRRATIONAL_EXIT_TRIANGLE,
                    "irrational impeller exit triangle",
                    ewf,
                )
            t2 = t2pp - w2**2 / (2.0 * cp)
            if t2 <= 0.0:
                return _invalid_point(
                    vovcr, PointStatus.NUMERICAL_FAILURE, "nonpositive impeller exit temperature", ewf
                )
            a2 = math.sqrt(gam * rgas * t2)
            w2ow1t = w2 / wi_t
            wou2 = (
                phi**2
                + (dmf / d2) ** 2
                + w2ow1t**2 * (phi**2 + config.drat**2)
            ) / 2.0
            al2 = math.atan(vu2 / vm2)
            v2 = math.hypot(vu2, vm2)
            t2p = t2 + v2**2 / (2.0 * cp)
            dhaero = cp * top * (t2p / top - 1.0)
            qaero = dhaero / u2**2
            df_denominator = wi_t / u2 * (
                config.z / PI * (1.0 - config.dit / d2)
                + 2.0 * config.dit / d2
            )
            const1 = 0.6 if config.splt == 1 else 0.75
            df = 1.0 - w2 / wi_t + const1 * qaero / df_denominator
            dhbl = 0.05 * df**2 * u2**2
            lod = (1.0 - dmf / 0.3048) / math.cos(b2x) / 2.0
            dhdf = 0.01356 * rho2 * u2**3 * d2**2 / sw / re**0.2
            dhyd = config.z / PI / math.cos(b2x) + d2 / config.b2
            dhyd = 1.0 / dhyd + config.dit / d2 / (
                2.0 / (1.0 - config.lamx)
                + 2.0
                * config.z
                / PI
                / (1.0 + config.lamx)
                * math.sqrt(
                    1.0
                    + (1.0 + config.lamx**2) / 2.0 * math.tan(b1) ** 2
                )
            )
            dhrc = 0.02 * math.sqrt(math.tan(al2)) * df**2 * u2**2
            const2 = 7.0 if config.splt == 1 else 5.6
            dhsf = const2 * config.cf * lod / dhyd * wou2 * u2**2
            dhact = dhaero + dhdf + dhrc
            his = dhaero - dhbl - dhsf - dhigv - dhinc
            etar = his / dhaero
            tx = etar * dhaero / cp / top + 1.0
            p2p = tx ** (gam / g2) * p1fmf
            p2 = p2p * (t2p / t2) ** (-gam / g2)
            new_r2g = p2 / rgas / t2
            if abs((rho2 - new_r2g) / rho2) <= 0.0001:
                r2g = new_r2g
                converged = True
                break
            r2g = new_r2g
        if not converged:
            return _invalid_point(
                vovcr, PointStatus.NUMERICAL_FAILURE, "impeller density iteration failed", ewf
            )

        # Vaneless diffuser predictor-corrector and integration, pages 30-31.
        xm2 = v2 / a2
        r2 = d2 / 2.0
        amu = 1.4579e-6 * t2**1.5 / (t2 + 110.4)
        anu = amu / r2g
        b0 = 1.0
        xm = xm2
        alpha = al2
        radius_ratio = 1.0
        f_values = [0.0] * 10
        s_values = [0.0] * 10
        p3p = [0.0] * 10
        xmarr = [0.0] * 10
        f_values[0] = xm2**3 / (1.0 + g2 / 2.0 * xm2**2) ** (g1 / 2.0 / g2)
        p3p[0] = p2p
        xmarr[0] = xm2
        deltar = (config.vldrr - 1.0) / 10.0
        zeta = config.cf * r2 / config.b2
        arc_length = 0.0
        b = b0

        for no in range(2, 11):
            index = no - 1
            xm1 = xm
            alpha1 = alpha
            ds = deltar * r2 / math.cos(alpha)
            arc_length += ds
            deltas = 0.037 * arc_length**-0.2 * (v2 / anu) ** -0.2 * ds
            b = b0 - 2.0 * deltas / config.b2
            deltab = b0 - b
            denominator = xm**2 - 1.0 / math.cos(alpha) ** 2
            varm = (
                -2.0
                * (1.0 + g2 / 2.0 * xm**2)
                / denominator
                * (
                    (gam * xm**2 - math.tan(alpha) ** 2)
                    * zeta
                    / b0
                    / math.cos(alpha)
                    + deltas / b0 / deltar
                    - 1.0 / math.cos(alpha) ** 2 / radius_ratio
                )
                * xm**2
                * deltar
            )
            varal = (
                1.0
                / math.cos(alpha) ** 2
                / denominator
                * (
                    (1.0 + g2 * xm**2) * zeta / b0 / math.cos(alpha)
                    + deltab / b0 / deltar
                    - xm**2 / radius_ratio
                )
                * math.tan(alpha)
                * deltar
            )
            varm1 = varm
            varal1 = varal
            b1_depth = b
            old_b0 = b0

            arc_length -= ds
            predicted_xm2 = xm1**2 + varm
            if predicted_xm2 <= 0.0:
                return _invalid_point(
                    vovcr, PointStatus.NUMERICAL_FAILURE, "invalid vaneless diffuser Mach update", ewf
                )
            xm = math.sqrt(predicted_xm2)
            alpha = math.atan(math.tan(alpha1) + varal1)
            ds = deltar * r2 / math.cos(alpha)
            radius_ratio += deltar
            arc_length += ds
            deltas = 0.037 * arc_length**-0.2 * (v2 / anu) ** -0.2 * ds
            b = old_b0 - 2.0 * deltas / config.b2
            deltab = old_b0 - b
            denominator = xm**2 - 1.0 / math.cos(alpha) ** 2
            varm = (
                -2.0
                * (1.0 + g2 / 2.0 * xm**2)
                / denominator
                * (
                    (gam * xm**2 - math.tan(alpha) ** 2)
                    * zeta
                    / old_b0
                    / math.cos(alpha)
                    + deltab / old_b0 / deltar
                    - 1.0 / math.cos(alpha) ** 2 / radius_ratio
                )
                * xm**2
                * deltar
            )
            varal = (
                1.0
                / math.cos(alpha) ** 2
                / denominator
                * (
                    (1.0 + g2 * xm**2) * zeta / old_b0 / math.cos(alpha)
                    + deltab / old_b0 / deltar
                    - xm**2 / radius_ratio
                )
                * math.tan(alpha)
                * deltar
            )
            varm = (varm1 + varm) / 2.0
            varal = (varal1 + varal) / 2.0
            b = (b1_depth + b) / 2.0
            corrected_xm2 = xm1**2 + varm
            if corrected_xm2 <= 0.0 or b <= 0.0:
                return _invalid_point(
                    vovcr, PointStatus.NUMERICAL_FAILURE, "invalid vaneless diffuser state", ewf
                )
            xm = math.sqrt(corrected_xm2)
            alpha = math.atan(math.tan(alpha1) + varal)
            b0 = b
            accusr = math.sqrt(1.0 / (1.0 + g2 / 2.0 * xm**2))
            rhor = 1.0 / (1.0 + g2 / 2.0 * xm**2) ** (1.0 / g2)
            f_values[index] = xm**3 * accusr * rhor * radius_ratio
            if no == 2:
                s_values[index] = (
                    f_values[index] + f_values[index - 1]
                ) * 0.5 * deltar
            else:
                fntgrl(no, deltar, f_values, s_values)
            tpl = 1.0 / (
                1.0
                + gam
                * config.cf
                * r2
                * s_values[index]
                / math.cos(al2)
                / config.b2
                / xm2
                * (1.0 + g2 / 2.0 * xm2**2) ** (g1 / 2.0 / g2)
            )
            p3p[index] = tpl * p2p
            xmarr[index] = xm

        # Vaned diffuser and compressor output, report pages 31-32.
        pthp = p3p[-1]
        xmach = xmarr[-1]
        pth = pthp / (1.0 + g2 / 2.0 * xmach**2) ** (gam / g2)
        dhvld = cp * t2p * (
            (pth / pthp) ** (g2 / gam) - (pth / p2p) ** (g2 / gam)
        )
        bt = 1.0 - b
        xmach = xmach * math.cos(abs(alpha - al3))
        pthp = pth * (1.0 + g2 / 2.0 * xmach**2) ** (gam / g2)
        wfunc = sw * math.sqrt(t2p) / config.adth / pthp / b
        throat_choke = wfunc >= flfunc
        cpstar = 0.0 if throat_choke else _pressure_recovery(config.ar, xmach, bt)
        pexit = cpstar * (pthp - pth) + pth
        rthp = pthp / rgas / t2p
        vcrth = math.sqrt(2.0 * gam / g1 * rgas * t2p)
        rvrvth = sw / rthp / vcrth / config.adth / b
        vovcr4 = 0.020
        p4pg = math.nan
        for _ in range(5000):
            p4pl = pexit / (1.0 - g2 / g1 * vovcr4**2) ** (gam / g2)
            rvrvc4 = (
                (1.0 - g2 / g1 * vovcr4**2) ** (1.0 / g2) * vovcr4
            )
            p4pg = rvrvth * pthp / config.ar / rvrvc4
            vovcr4 += 0.001
            if p4pl >= p4pg:
                break
        else:
            return _invalid_point(
                vovcr, PointStatus.NUMERICAL_FAILURE, "diffuser exit iteration failed", ewf
            )
        ppexit = p4pg
        dhdif = t2p * cp * (
            (pexit / ppexit) ** (g2 / gam) - (pexit / pthp) ** (g2 / gam)
        )
        pressure_ratio = ppexit / pop
        etac = dhaero - dhsf - dhbl - dhvld - dhdif - dhigv - dhinc
        total_efficiency = etac / dhact
        deigv = dhigv / dhact
        deinc = dhinc / dhact
        debl = dhbl / dhact
        desf = dhsf / dhact
        dedf = dhdf / dhact
        derc = dhrc / dhact
        devld = dhvld / dhact
        devd = dhdif / dhact
        status = PointStatus.VALID
        message = "valid operating point"
        if incidence_choke:
            status = PointStatus.INCIDENCE_CHOKE
            message = "inducer choking incidence reached"
        if throat_choke:
            status = PointStatus.THROAT_CHOKE
            message = "vaned diffuser throat choking reached"
        return OperatingPoint(
            vovcr=vovcr,
            status=status,
            message=message,
            equivalent_flow=ewf,
            pressure_ratio=pressure_ratio,
            total_efficiency=total_efficiency,
            deigv=deigv,
            deinc=deinc,
            debl=debl,
            desf=desf,
            dedf=dedf,
            derc=derc,
            devld=devld,
            devd=devd,
            throat_mach=xmach,
            incidence_choke=incidence_choke,
            throat_choke=throat_choke,
        )
    except (ArithmeticError, OverflowError, ValueError) as exc:
        return _invalid_point(
            vovcr,
            PointStatus.NUMERICAL_FAILURE,
            f"numerical model domain failure: {exc}",
        )


@dataclass(frozen=True)
class CompressorRun:
    percent_design_speed: float
    surge_flow: float | None
    choke_flow: float | None
    choke_reached: bool
    points: Tuple[OperatingPoint, ...]
    diagnostics: Tuple[str, ...]


def run_compressor(config: CompressorInput) -> CompressorRun:
    """Perform the listing's choke-discovery and reporting passes."""

    diagnostics: list[str] = []
    choke_point: OperatingPoint | None = None

    # Pass 1 corresponds to L=1: find the first choking condition.
    for index, vovcr in enumerate(config.vovcr):
        point = evaluate_operating_point(config, vovcr)
        if point.status in (
            PointStatus.IRRATIONAL_EXIT_TRIANGLE,
            PointStatus.NUMERICAL_FAILURE,
        ):
            diagnostics.append(f"VOVCR={vovcr:.2f}: {point.message}")
            continue
        if point.incidence_choke or point.throat_choke:
            if index == 0:
                diagnostics.append("VOVCR array too large: first point is already choked")
                return CompressorRun(
                    percent_design_speed=config.nondes * 100.0,
                    surge_flow=None,
                    choke_flow=point.equivalent_flow,
                    choke_reached=True,
                    points=(),
                    diagnostics=tuple(diagnostics),
                )
            choke_point = point
            break

    if choke_point is None:
        diagnostics.append("Compressor choking flow has not been reached")
        return CompressorRun(
            percent_design_speed=config.nondes * 100.0,
            surge_flow=None,
            choke_flow=None,
            choke_reached=False,
            points=(),
            diagnostics=tuple(diagnostics),
        )

    choke_flow = choke_point.equivalent_flow
    surge_fraction = _interpolate_1d(choke_point.throat_mach, DIFLEM, FLRNG)
    surge_flow = surge_fraction * choke_flow

    # Pass 2 corresponds to L=2: omit points outside the usable range.
    points: list[OperatingPoint] = []
    for vovcr in config.vovcr:
        point = evaluate_operating_point(config, vovcr)
        if point.status in (
            PointStatus.IRRATIONAL_EXIT_TRIANGLE,
            PointStatus.NUMERICAL_FAILURE,
        ):
            diagnostics.append(f"VOVCR={vovcr:.2f}: {point.message}")
            continue
        if point.equivalent_flow < surge_flow:
            diagnostics.append(f"Weight flow less than surge for VOVCR={vovcr:.2f}")
            continue
        if point.equivalent_flow > choke_flow + 1e-12:
            break
        points.append(point)
        if point.incidence_choke or point.throat_choke:
            break

    return CompressorRun(
        percent_design_speed=config.nondes * 100.0,
        surge_flow=surge_flow,
        choke_flow=choke_flow,
        choke_reached=True,
        points=tuple(points),
        diagnostics=tuple(diagnostics),
    )


def format_run(result: CompressorRun) -> str:
    lines = [f"PERCENT NDES {result.percent_design_speed:.1f}"]
    for diagnostic in result.diagnostics:
        lines.append(diagnostic)
    if not result.choke_reached:
        return "\n".join(lines)

    if result.surge_flow is None or result.choke_flow is None:
        raise ValueError("complete run is missing surge or choke flow")
    lines.extend(
        (
            f"SURGE FLOW RATE {result.surge_flow:.3f}    "
            f"CHOKE FLOW RATE {result.choke_flow:.3f}",
            "VOVCR  WEQ     PRESSURE_RATIO  ETAT   "
            "DETAIGV  DETAINC  DETABL  DETASF  DETADF  DETARC  DETAVLD  DETAVD",
        )
    )
    for point in result.points:
        lines.append(
            f"{point.vovcr:5.2f}  {point.equivalent_flow:6.3f}  "
            f"{point.pressure_ratio:14.3f}  {point.total_efficiency:5.3f}  "
            f"{point.deigv:7.5f}  {point.deinc:7.5f}  {point.debl:7.5f}  "
            f"{point.desf:7.5f}  {point.dedf:7.5f}  {point.derc:7.5f}  "
            f"{point.devld:8.5f}  {point.devd:7.5f}"
        )
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run the NASA TN D-7487 centrifugal-compressor model."
    )
    parser.add_argument("input_json", type=Path, help="compressor input JSON file")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        config = CompressorInput.from_json(args.input_json)
        result = run_compressor(config)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    print(format_run(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
