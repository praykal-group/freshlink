"""Features shared by training and serving (one implementation, Section 21).

Each series is scaled by its mean over the last 30 observed days, so one global model serves every
site/product. Forecast origin d0 = last observed day; targets are d0+1 … d0+H.

LightGBM (direct multi-horizon, one row per target day):
  h, dow, festival, price/price30, rain, temp, lag1, lag7, mean7, mean14, same-weekday mean (4 w)
LSTM (2 layers 64/32, Section 8): window of 30 days × LSTM_FEATURES → H outputs (scaled kg).
"""

import math
from dataclasses import dataclass
from datetime import date, timedelta
from typing import List, Optional, Sequence

import numpy as np

from .calendar import is_festival_window
from .simulate import Day, weather

WINDOW = 30
HORIZON = 7
LGBM_FEATURES = ["h", "dow", "festival", "price_rel", "rain_mm", "temp_c", "lag1", "lag7", "mean7", "mean14", "same_dow4"]
LSTM_FEATURES = ["kg", "price_rel", "rain", "temp", "dow_sin", "dow_cos", "festival"]


@dataclass
class Future:
    """What is known about a target day at forecast time."""

    date: date
    price: float
    rain_mm: float
    temp_c: float
    festival: bool


def scale_of(hist: Sequence[Day]) -> float:
    return max(1.0, float(np.mean([d.kg for d in hist[-WINDOW:]])))


def price_scale_of(hist: Sequence[Day]) -> float:
    return max(1e-6, float(np.mean([d.price for d in hist[-WINDOW:]])))


def future_days(hist: Sequence[Day], horizon: int, future_weather: Optional[Sequence[tuple]] = None) -> List[Future]:
    """Calendar + weather for d0+1..d0+H. Price for unseen days = last observed price (persistence)."""
    d0 = hist[-1].date
    last_price = hist[-1].price
    out = []
    for h in range(1, horizon + 1):
        d = d0 + timedelta(days=h)
        rain, temp = future_weather[h - 1] if future_weather else weather(d)
        out.append(Future(d, last_price, rain, temp, is_festival_window(d)))
    return out


def lgbm_rows(hist: Sequence[Day], fut: Sequence[Future]) -> np.ndarray:
    if len(hist) < WINDOW:
        raise ValueError(f"need {WINDOW} days of history, got {len(hist)}")
    s, ps = scale_of(hist), price_scale_of(hist)
    kg = [d.kg / s for d in hist]
    by_date = {d.date: d.kg / s for d in hist}
    lag1 = kg[-1]
    mean7, mean14 = float(np.mean(kg[-7:])), float(np.mean(kg[-14:]))
    rows = []
    for h, f in enumerate(fut, start=1):
        lag7 = by_date.get(f.date - timedelta(days=7), by_date.get(f.date - timedelta(days=14), lag1))
        same = [by_date[f.date - timedelta(days=7 * k)] for k in range(1, 5) if (f.date - timedelta(days=7 * k)) in by_date]
        rows.append([h, f.date.weekday(), float(f.festival), f.price / ps, f.rain_mm, f.temp_c, lag1, lag7, mean7, mean14, float(np.mean(same)) if same else mean7])
    return np.asarray(rows, dtype=np.float32)


def lstm_window(hist: Sequence[Day]) -> np.ndarray:
    if len(hist) < WINDOW:
        raise ValueError(f"need {WINDOW} days of history, got {len(hist)}")
    s, ps = scale_of(hist), price_scale_of(hist)
    win = hist[-WINDOW:]
    rows = []
    for d in win:
        a = 2 * math.pi * d.date.weekday() / 7
        rows.append([d.kg / s, d.price / ps, d.rain_mm / 10.0, (d.temp_c - 27.0) / 5.0, math.sin(a), math.cos(a), float(d.festival)])
    return np.asarray(rows, dtype=np.float32)[None, ...]  # [1, 30, F]


def seasonal_naive(hist: Sequence[Day], fut: Sequence[Future]) -> np.ndarray:
    """Fallback (always available): mean of the same weekday over the last 4 weeks, in kg."""
    by_date = {d.date: d.kg for d in hist}
    out = []
    for f in fut:
        same = [by_date[f.date - timedelta(days=7 * k)] for k in range(1, 5) if (f.date - timedelta(days=7 * k)) in by_date]
        out.append(float(np.mean(same)) if same else float(np.mean([d.kg for d in hist[-7:]])))
    return np.asarray(out)


def mape(actual: Sequence[float], pred: Sequence[float]) -> float:
    a, p = np.asarray(actual, dtype=float), np.asarray(pred, dtype=float)
    mask = a > 1e-9
    return float(np.mean(np.abs(a[mask] - p[mask]) / a[mask]) * 100.0)
