import time

from fastapi import APIRouter
from starlette.concurrency import run_in_threadpool

from ..core import images
from ..core.errors import MlError
from ..core.state import state
from ..core.vision import combine, grade_image, model_name_for
from ..schemas.api import DefectOut, GradeRequest, GradeResponse, PerImageOut

router = APIRouter(prefix="/v1/vision", tags=["vision"])


@router.post("/grade", response_model=GradeResponse, response_model_by_alias=True)
async def grade(req: GradeRequest) -> GradeResponse:
    started = time.perf_counter()
    model = state.vision.get(req.category)
    if model is None:
        reason = state.registry.describe().get(model_name_for(req.category), {}).get("reason") if state.registry else None
        raise MlError("MODEL_NOT_AVAILABLE", f"No {req.category.lower()} grading model is loaded", 503, {"reason": reason})

    imgs = await images.fetch_images([str(u) for u in req.imageUrls])

    def run():
        out = []
        for img in imgs:
            out.append(grade_image(model.detect(img), img.size))
        return out

    per_image = await run_in_threadpool(run)
    grade_letter, confidence = combine(per_image)
    defects = [DefectOut(**d) for g in per_image for d in g.defects]
    return GradeResponse(
        batchId=req.batchId,
        grade=grade_letter,
        confidence=confidence,
        defects=defects,
        perImage=[
            PerImageOut(index=i, grade=g.grade, confidence=g.confidence, itemDetected=g.item_detected, defects=[DefectOut(**d) for d in g.defects])
            for i, g in enumerate(per_image)
        ],
        modelVersion=model.version,
        latencyMs=int((time.perf_counter() - started) * 1000),
    )
