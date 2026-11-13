"""Remaining shelf life (Section 8, ML-02).

Primary: Cox proportional hazards, served from exported parameters (D-54):
    S(t | x) = S0(t) ** exp(beta . (x - means));  remaining = t* - elapsed, where S(t*) = 0.5
Fallback (always available): Q10 temperature model
    remaining = baseShelfLife * Q10 ** ((refTemp - meanTemp) / 10) - elapsed, clamped >= 0
"""

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np

COX_FEATURES = [
    "log_base_shelf_life_h",
    "mean_temp_c",
    "degree_minutes_above",
    "humidity_pct",
    "ethylene_ppm",
    "shock_events",
    "grade_B",
    "grade_C",
]

Q10_METHOD = "Q10_FALLBACK"
COX_METHOD = "COX"
Q10_VERSION = "q10-1"
WEIBULL_SHAPE = 3.0
CURVE_POINTS = 13


@dataclass
class Exposure:
    base_shelf_life_h: float
    q10: float
    ref_temp_c: float
    hours_since_harvest: float
    mean_temp_c: float
    degree_minutes_above: float = 0.0
    humidity_pct: Optional[float] = None
    ethylene_ppm: Optional[float] = None
    shock_events: int = 0
    grade: Optional[str] = None


@dataclass
class Prediction:
    remaining_h: float
    curve: List[Dict[str, float]]
    method: str
    model_version: str
    censored: bool = False


def q10_total_h(e: Exposure) -> float:
    """Total shelf life (hours from harvest) at the observed mean temperature."""
    q10 = max(e.q10, 1.0)
    return max(0.0, e.base_shelf_life_h * q10 ** ((e.ref_temp_c - e.mean_temp_c) / 10.0))


def weibull_curve(total_h: float, points: int = CURVE_POINTS) -> List[Dict[str, float]]:
    """S(h) with S(total_h) = 0.5, shape 3: a smooth curve to plot alongside the Q10 estimate."""
    if total_h <= 0:
        return [{"h": 0.0, "p": 0.0}]
    scale = total_h / (math.log(2) ** (1 / WEIBULL_SHAPE))
    hs = np.linspace(0, 2 * total_h, points)
    return [{"h": round(float(h), 2), "p": round(float(math.exp(-((h / scale) ** WEIBULL_SHAPE))), 4)} for h in hs]


def predict_q10(e: Exposure) -> Prediction:
    total = q10_total_h(e)
    remaining = max(0.0, total - max(0.0, e.hours_since_harvest))
    return Prediction(round(remaining, 2), weibull_curve(total), Q10_METHOD, Q10_VERSION)


def features(e: Exposure) -> np.ndarray:
    return np.array(
        [
            math.log(max(e.base_shelf_life_h, 1.0)),
            e.mean_temp_c,
            e.degree_minutes_above,
            e.humidity_pct if e.humidity_pct is not None else 90.0,
            e.ethylene_ppm if e.ethylene_ppm is not None else 0.0,
            float(e.shock_events),
            1.0 if e.grade == "B" else 0.0,
            1.0 if e.grade == "C" else 0.0,
        ],
        dtype=np.float64,
    )


class CoxModel:
    """Parameters exported by ml/training/shelf_life/train_cox.py:
    {"features": [...], "beta": [...], "means": [...], "baselineSurvival": [[t, S0(t)], ...]}"""

    def __init__(self, params: Dict, version: str):
        if list(params.get("features", [])) != COX_FEATURES:
            raise ValueError("Cox parameter file has a different feature list than the service")
        self.beta = np.asarray(params["beta"], dtype=np.float64)
        self.means = np.asarray(params["means"], dtype=np.float64)
        table = np.asarray(params["baselineSurvival"], dtype=np.float64)
        if table.ndim != 2 or table.shape[1] != 2 or len(table) < 2:
            raise ValueError("baselineSurvival must be [[t, S0], ...] with at least 2 rows")
        order = np.argsort(table[:, 0])
        self.t, self.s0 = table[order, 0], np.clip(table[order, 1], 1e-12, 1.0)
        self.version = version

    @classmethod
    def load(cls, path: Path, version: str) -> "CoxModel":
        return cls(json.loads(path.read_text(encoding="utf-8")), version)

    def survival(self, e: Exposure) -> np.ndarray:
        lp = float(self.beta @ (features(e) - self.means))
        return self.s0 ** math.exp(lp)

    def median_time(self, s: np.ndarray) -> Tuple[float, bool]:
        """First t with S(t) <= 0.5 (linear interpolation). Censored → last t, flagged."""
        below = np.where(s <= 0.5)[0]
        if not below.size:
            return float(self.t[-1]), True
        i = int(below[0])
        if i == 0:
            return float(self.t[0]), False
        t0, t1, s_0, s_1 = self.t[i - 1], self.t[i], s[i - 1], s[i]
        frac = (s_0 - 0.5) / max(s_0 - s_1, 1e-12)
        return float(t0 + frac * (t1 - t0)), False

    def predict(self, e: Exposure) -> Prediction:
        s = self.survival(e)
        t_med, censored = self.median_time(s)
        remaining = max(0.0, t_med - max(0.0, e.hours_since_harvest))
        step = max(1, len(self.t) // CURVE_POINTS)
        curve = [{"h": round(float(t), 2), "p": round(float(p), 4)} for t, p in zip(self.t[::step], s[::step])]
        return Prediction(round(remaining, 2), curve, COX_METHOD, self.version, censored)


def predict(e: Exposure, cox: Optional[CoxModel]) -> Prediction:
    """Cox when a model is loaded and gives a finite answer; Q10 otherwise. Never raises for valid input."""
    if cox is not None:
        try:
            p = cox.predict(e)
            if math.isfinite(p.remaining_h):
                return p
        except (ValueError, FloatingPointError, OverflowError):
            pass
    return predict_q10(e)


def check_finite(values: Sequence[Optional[float]]) -> bool:
    return all(v is None or math.isfinite(v) for v in values)
