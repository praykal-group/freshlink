import time
import uuid
from collections import defaultdict
from datetime import date, timedelta
from typing import Dict, List, Tuple

from fastapi import APIRouter
from starlette.concurrency import run_in_threadpool

from ..core.errors import MlError
from ..core.forecast import simulate, weather
from ..core.forecast.calendar import is_festival_window
from ..core.forecast.features import WINDOW, future_days
from ..core.forecast.model import forecast
from ..core.forecast.simulate import Day
from ..core.state import state
from ..schemas.forecast import ForecastRequest, ForecastResponse, ForecastRow

router = APIRouter(prefix="/v1/forecast", tags=["forecast"])

MAX_SERIES = 500


def _history(req: ForecastRequest) -> Dict[Tuple[str, str], List[Day]]:
    """Provided history, keyed per series; only series with WINDOW contiguous days ending yesterday count."""
    if not req.history:
        return {}
    d0 = req.startDate - timedelta(days=1)
    first = d0 - timedelta(days=WINDOW - 1)
    points: Dict[Tuple[str, str], Dict[date, object]] = defaultdict(dict)
    for p in req.history:
        if first <= p.date <= d0:
            points[(p.siteId, p.productId)][p.date] = p
    out: Dict[Tuple[str, str], List[Day]] = {}
    for key, by_date in points.items():
        if len(by_date) < WINDOW:
            continue
        sim = {d.date: d for d in simulate.series(key[0], key[1], first, d0)}
        days = []
        for i in range(WINDOW):
            d = first + timedelta(days=i)
            p = by_date[d]
            w = sim[d]
            days.append(Day(d, float(p.kg), float(p.priceInr) if p.priceInr else w.price, w.rain_mm, w.temp_c, is_festival_window(d)))
        out[key] = days
    return out


def run(req: ForecastRequest) -> ForecastResponse:
    started = time.perf_counter()
    if len(req.siteIds) * len(req.productIds) > MAX_SERIES:
        raise MlError("TOO_MANY_SERIES", f"at most {MAX_SERIES} site×product series per run", 422)
    provided = _history(req)
    d0 = req.startDate - timedelta(days=1)
    end = d0 + timedelta(days=req.horizonDays)
    model = state.forecast
    weather_cache: Dict[str, object] = {}
    rows: List[ForecastRow] = []
    methods = set()
    for site in req.siteIds:
        coords = (req.siteCoords or {}).get(site)
        if site not in weather_cache:
            weather_cache[site] = weather.fetch_daily(coords.lat, coords.lng, req.startDate, end) if coords else None
        fw = weather_cache[site]
        for product in req.productIds:
            hist = provided.get((site, product))
            source = "PROVIDED"
            if hist is None:
                hist = simulate.series(site, product, d0 - timedelta(days=60), d0)
                source = "SIMULATED"
            fut = future_days(hist, req.horizonDays, fw)
            f = forecast(model, hist, fut)
            methods.add(f.method)
            for i, day in enumerate(fut):
                rows.append(
                    ForecastRow(
                        siteId=site, productId=product, date=day.date, predictedKg=f.predicted[i],
                        lowerKg=f.lower[i], upperKg=f.upper[i], historySource=source,
                    )
                )
    method = methods.pop() if len(methods) == 1 else "MIXED"
    return ForecastResponse(
        runId=str(uuid.uuid4()),
        rows=rows,
        modelVersion=model.version if model is not None else "seasonal-naive-1",
        method=method,
        latencyMs=int((time.perf_counter() - started) * 1000),
    )


@router.post("/run", response_model=ForecastResponse)
async def run_forecast(req: ForecastRequest) -> ForecastResponse:
    return await run_in_threadpool(run, req)
