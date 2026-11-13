"""Forecast ensemble: w·LSTM + (1−w)·LightGBM, intervals from validation residuals (Section 8).

Model directory (registry name `forecast`): lgbm.txt (LightGBM booster), lstm.onnx (optional),
meta.json {"lstmWeight", "intervalPct", "horizon", "window"}. Without a registered model the
seasonal-naive fallback answers (method SEASONAL_NAIVE), so planning always gets numbers.
"""

import json
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Sequence

import numpy as np

from .features import HORIZON, Future, lgbm_rows, lstm_window, scale_of, seasonal_naive
from .simulate import Day

NAIVE_INTERVAL_PCT = 0.25


@dataclass
class SeriesForecast:
    predicted: List[float]
    lower: List[float]
    upper: List[float]
    method: str


class ForecastModel:
    def __init__(self, model_dir: Path, version: str):
        import lightgbm as lgb

        meta = json.loads((model_dir / "meta.json").read_text(encoding="utf-8"))
        self.booster = lgb.Booster(model_file=str(model_dir / "lgbm.txt"))
        self.lstm = None
        lstm_path = model_dir / "lstm.onnx"
        if lstm_path.exists() and meta.get("lstmWeight", 0) > 0:
            import onnxruntime as ort

            self.lstm = ort.InferenceSession(str(lstm_path), providers=["CPUExecutionProvider"])
            self.lstm_input = self.lstm.get_inputs()[0].name
        self.w = float(meta.get("lstmWeight", 0.0)) if self.lstm is not None else 0.0
        self.interval = float(meta.get("intervalPct", 0.2))
        self.version = version

    def predict(self, hist: Sequence[Day], fut: Sequence[Future]) -> SeriesForecast:
        s = scale_of(hist)
        lgbm = self.booster.predict(lgbm_rows(hist, fut))
        pred = lgbm
        if self.lstm is not None:
            lstm = self.lstm.run(None, {self.lstm_input: lstm_window(hist)})[0][0][: len(fut)]
            pred = self.w * lstm + (1 - self.w) * lgbm
        kg = np.clip(pred * s, 0, None)
        return SeriesForecast(
            [round(float(v), 3) for v in kg],
            [round(float(v * (1 - self.interval)), 3) for v in kg],
            [round(float(v * (1 + self.interval)), 3) for v in kg],
            "ENSEMBLE" if self.lstm is not None else "LIGHTGBM",
        )


def naive_forecast(hist: Sequence[Day], fut: Sequence[Future]) -> SeriesForecast:
    kg = np.clip(seasonal_naive(hist, fut), 0, None)
    return SeriesForecast(
        [round(float(v), 3) for v in kg],
        [round(float(v * (1 - NAIVE_INTERVAL_PCT)), 3) for v in kg],
        [round(float(v * (1 + NAIVE_INTERVAL_PCT)), 3) for v in kg],
        "SEASONAL_NAIVE",
    )


def forecast(model: Optional[ForecastModel], hist: Sequence[Day], fut: Sequence[Future]) -> SeriesForecast:
    if model is not None:
        try:
            return model.predict(hist, fut)
        except (ValueError, RuntimeError):
            pass
    return naive_forecast(hist, fut)


__all__ = ["ForecastModel", "SeriesForecast", "forecast", "naive_forecast", "HORIZON"]
