"""Deterministic simulated sales world (Section 2: sales history is simulated).

One series per (site, product): base level × weekday pattern × yearly season × festival uplift ×
price elasticity × rain effect × lognormal noise. Weather and mandi price are simulated too.
Every value is a pure function of (site, product, date), so any date range can be regenerated
identically for training and serving.
"""

import hashlib
import math
from dataclasses import dataclass
from datetime import date, timedelta
from typing import List

import numpy as np

from .calendar import is_festival_window

EPOCH = date(2023, 1, 1)

WEEKDAY = [0.92, 0.95, 0.97, 1.0, 1.05, 1.18, 1.12]  # Mon..Sun
FESTIVAL_UPLIFT = 1.4
ELASTICITY = -0.4
RAIN_DROP = 0.88  # heavy rain (> 10 mm) keeps buyers away
NOISE_SIGMA = 0.10


@dataclass
class Day:
    date: date
    kg: float
    price: float
    rain_mm: float
    temp_c: float
    festival: bool


def _seed(*parts: str) -> int:
    return int.from_bytes(hashlib.sha256("|".join(parts).encode()).digest()[:8], "little")


def _unit(*parts: str) -> float:
    """Deterministic U(0,1) for a key."""
    return (_seed(*parts) % 1_000_000) / 1_000_000


def weather(d: date) -> tuple:
    """Chh. Sambhajinagar-like climate: warm, June–September monsoon. Deterministic per date."""
    doy = d.timetuple().tm_yday
    temp = 27.0 + 5.0 * math.sin(2 * math.pi * (doy - 110) / 365.25) + (_unit("temp", d.isoformat()) - 0.5) * 3
    monsoon = 152 <= doy <= 273
    rains = _unit("rain?", d.isoformat()) < (0.55 if monsoon else 0.05)
    rain = -math.log(max(1e-6, 1 - _unit("rainmm", d.isoformat()))) * (12.0 if monsoon else 4.0) if rains else 0.0
    return round(rain, 2), round(temp, 2)


def series(site_id: str, product_id: str, start: date, end: date) -> List[Day]:
    """Inclusive date range."""
    base = 80 + 720 * _unit("base", site_id, product_id)  # kg/day
    season_amp = 0.25 * _unit("amp", product_id)
    season_phase = 2 * math.pi * _unit("phase", product_id)
    base_price = 20 + 600 * _unit("price", product_id)
    out: List[Day] = []
    n = (end - start).days + 1
    for i in range(n):
        d = start + timedelta(days=i)
        rain, temp = weather(d)
        doy = d.timetuple().tm_yday
        season = 1 + season_amp * math.sin(2 * math.pi * doy / 365.25 + season_phase)
        price = base_price * (1 + 0.15 * math.sin(2 * math.pi * doy / 365.25 + season_phase + 1.0)) * (0.95 + 0.1 * _unit("pn", product_id, d.isoformat()))
        festival = is_festival_window(d)
        rng = np.random.default_rng(_seed("noise", site_id, product_id, d.isoformat()))
        kg = (
            base
            * WEEKDAY[d.weekday()]
            * season
            * (FESTIVAL_UPLIFT if festival else 1.0)
            * (price / base_price) ** ELASTICITY
            * (RAIN_DROP if rain > 10 else 1.0)
            * math.exp(rng.normal(0, NOISE_SIGMA) - NOISE_SIGMA**2 / 2)
        )
        out.append(Day(d, round(kg, 3), round(price, 2), rain, temp, festival))
    return out
