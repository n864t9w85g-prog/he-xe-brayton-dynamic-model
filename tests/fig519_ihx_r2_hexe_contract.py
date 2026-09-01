"""Pure immutable contract for the Figure 5.19 IHX-region-2 A3 attempt.

The Figure 5.18(a) temperature is only a visual proxy.  This module performs
no model mutation, MATLAB invocation, or simulation.
"""
from __future__ import annotations

from collections.abc import Mapping
from decimal import Decimal, localcontext
from types import MappingProxyType


class ContractError(RuntimeError):
    """Raised when a caller violates the pure A3 contract interface."""


ATTEMPT_ID = "20260901_A3"
ANCHOR_IDENTITY = "figure_5_18a_t0_visual_proxy_not_author_initial_state"
SOURCE_MODEL_SHA256 = (
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391"
)
AVERAGE_PATH = "final_steady_24a/IHX/IHX_region_2/T_c1_average_Integrator"
OUTLET_PATH = "final_steady_24a/IHX/IHX_region_2/T_c2_out_Integrator"
OLD_AVERAGE_K = Decimal("1245.8184669844006")
OLD_OUTLET_K = Decimal("1393.6037139151003")
ANCHOR_K = Decimal("1200.0000000000000")

PAPER_DIRECTIONS = MappingProxyType(
    {
        "reactor": ("fall",),
        "turbine": ("rise",),
        "compressor": ("fall", "rise"),
        "electrical_paper_eta": ("rise", "fall"),
    }
)
NONFLAT_THRESHOLDS_W = MappingProxyType(
    {
        "reactor": Decimal("0.5141158541664481"),
        "turbine": Decimal("1.609319536946714"),
        "compressor": Decimal("2.2659989586099982"),
        "electrical_paper_eta": Decimal("3.7926344096194953"),
    }
)

NUMERICAL_OR_PHYSICAL_GATE_FAILED = "numerical_or_physical_gate_failed"
SHIFT_NOT_FALSIFIED_NOT_VALIDATED = (
    "ihx_r2_hexe_shift_alone_not_falsified_but_not_validated"
)
SHIFT_FALSIFIED = "ihx_r2_hexe_shift_alone_falsified"

_FALSE_PROMOTION_FLAGS = MappingProxyType(
    {
        "paper_reproduced": False,
        "author_initial_state_identified": False,
        "formal_promotion": False,
    }
)


def candidate_contract() -> Mapping[str, object]:
    """Return the immutable one-delta A3 candidate definition."""
    with localcontext() as context:
        context.prec = 34
        delta = ANCHOR_K - OLD_OUTLET_K
        new_average = OLD_AVERAGE_K + delta
        new_outlet = OLD_OUTLET_K + delta
        old_gap = OLD_OUTLET_K - OLD_AVERAGE_K
        new_gap = new_outlet - new_average
    if new_outlet != ANCHOR_K or old_gap != new_gap:
        raise ContractError("A3 one-delta temperature identity is inconsistent")
    return MappingProxyType(
        {
            "attempt_id": ATTEMPT_ID,
            "anchor_identity": ANCHOR_IDENTITY,
            "source_model_sha256": SOURCE_MODEL_SHA256,
            "average_path": AVERAGE_PATH,
            "outlet_path": OUTLET_PATH,
            "old_average_K": OLD_AVERAGE_K,
            "old_outlet_K": OLD_OUTLET_K,
            "anchor_K": ANCHOR_K,
            "delta_K": delta,
            "new_average_K": new_average,
            "new_outlet_K": new_outlet,
            "old_gap_K": old_gap,
            "new_gap_K": new_gap,
        }
    )


def promotion_flags() -> Mapping[str, bool]:
    """Return immutable negative promotion flags for this exploratory attempt."""
    return _FALSE_PROMOTION_FLAGS


def classify(
    numerical_gate: bool,
    directions: Mapping[str, tuple[str, ...]],
    nonflat: Mapping[str, bool],
) -> str:
    """Mechanically classify an A3 result without making scientific claims."""
    if type(numerical_gate) is not bool:
        raise ContractError("numerical_gate must be a bool")
    if not numerical_gate:
        return NUMERICAL_OR_PHYSICAL_GATE_FAILED
    if not isinstance(directions, Mapping):
        raise ContractError("directions must be a mapping")
    if not isinstance(nonflat, Mapping):
        raise ContractError("nonflat must be a mapping")

    exact_directions = dict(directions) == dict(PAPER_DIRECTIONS)
    exact_nonflat = set(nonflat) == set(PAPER_DIRECTIONS) and all(
        type(nonflat[name]) is bool and nonflat[name]
        for name in PAPER_DIRECTIONS
    )
    if exact_directions and exact_nonflat:
        return SHIFT_NOT_FALSIFIED_NOT_VALIDATED
    return SHIFT_FALSIFIED
