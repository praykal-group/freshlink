"""I-CCMS ML service (internal only). Routers for vision, shelf-life, forecast and routing join in M5/M6."""

import hmac
import os

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

INTERNAL_TOKEN = os.environ.get("ML_INTERNAL_TOKEN", "")

app = FastAPI(title="iccms-ml", version="0.1.0", docs_url=None, redoc_url=None)


@app.middleware("http")
async def internal_token(request: Request, call_next):
    """Every request needs X-Internal-Token (Section 8). Constant-time compare."""
    supplied = request.headers.get("x-internal-token", "")
    if not INTERNAL_TOKEN or not hmac.compare_digest(supplied, INTERNAL_TOKEN):
        return JSONResponse(
            status_code=401,
            content={"error": {"code": "UNAUTHORIZED", "message": "invalid internal token"}},
        )
    return await call_next(request)


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "models": []}
