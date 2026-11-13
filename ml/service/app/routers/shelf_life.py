import time

from fastapi import APIRouter

from ..core.shelf_life import Exposure, predict
from ..core.state import state
from ..schemas.api import CurvePoint, ShelfLifeRequest, ShelfLifeResponse, ShelfLifeResult

router = APIRouter(prefix="/v1/shelf-life", tags=["shelf-life"])


@router.post("/predict", response_model=ShelfLifeResponse)
def predict_batch(req: ShelfLifeRequest) -> ShelfLifeResponse:
    """Always answers: Cox when loaded, otherwise the Q10 fallback (ML-02). Target < 1 s."""
    started = time.perf_counter()
    results = []
    for it in req.items:
        p = predict(
            Exposure(
                base_shelf_life_h=it.baseShelfLifeH,
                q10=it.q10,
                ref_temp_c=it.refTempC,
                hours_since_harvest=it.hoursSinceHarvest,
                mean_temp_c=it.meanTempC,
                degree_minutes_above=it.degreeMinutesAbove,
                humidity_pct=it.humidityPct,
                ethylene_ppm=it.ethylenePpm,
                shock_events=it.shockEvents,
                grade=it.grade,
            ),
            state.cox,
        )
        results.append(
            ShelfLifeResult(
                batchId=it.batchId,
                remainingH=p.remaining_h,
                survivalCurve=[CurvePoint(**c) for c in p.curve],
                method=p.method,
                modelVersion=p.model_version,
                censored=p.censored,
            )
        )
    return ShelfLifeResponse(results=results, latencyMs=int((time.perf_counter() - started) * 1000))
