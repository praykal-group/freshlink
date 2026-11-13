"""Forecast contract (Section 8): POST /v1/forecast/run."""

from datetime import date
from typing import Dict, List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


class _M(BaseModel):
    model_config = ConfigDict(extra="forbid")


class HistoryPoint(_M):
    siteId: str
    productId: str
    date: date
    kg: float = Field(ge=0)
    priceInr: Optional[float] = Field(default=None, gt=0)


class Coord(_M):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


class ForecastRequest(_M):
    siteIds: List[str] = Field(min_length=1, max_length=50)
    productIds: List[str] = Field(min_length=1, max_length=50)
    startDate: date
    horizonDays: int = Field(default=7, ge=1, le=7)
    # Real sales history when the backend has it; otherwise the simulated world is used (Section 2).
    history: Optional[List[HistoryPoint]] = Field(default=None, max_length=200_000)
    # Optional site coordinates for Open-Meteo weather (D-67).
    siteCoords: Optional[Dict[str, Coord]] = None


class ForecastRow(_M):
    siteId: str
    productId: str
    date: date
    predictedKg: float
    lowerKg: float
    upperKg: float
    historySource: Literal["PROVIDED", "SIMULATED"]


class ForecastResponse(_M):
    runId: str
    rows: List[ForecastRow]
    modelVersion: str
    method: Literal["ENSEMBLE", "LIGHTGBM", "SEASONAL_NAIVE", "MIXED"]
    latencyMs: int
