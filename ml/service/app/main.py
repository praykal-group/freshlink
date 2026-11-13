"""I-CCMS ML service (internal only, Section 8). Every request needs X-Internal-Token."""

import hmac
import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from .core.errors import MlError
from .core.state import state
from .routers import forecast, routing, shelf_life, vision

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO").upper(), format="%(asctime)s %(levelname)s %(name)s %(message)s")


@asynccontextmanager
async def lifespan(_: FastAPI):
    state.load()
    yield


app = FastAPI(title="iccms-ml", version="0.5.0", docs_url=None, redoc_url=None, lifespan=lifespan)


def _token() -> str:
    # Read per request so tests and restarts pick up the current value.
    return os.environ.get("ML_INTERNAL_TOKEN", "")


@app.middleware("http")
async def internal_token(request: Request, call_next):
    """Constant-time token check. An unset token rejects everything (fail closed)."""
    expected = _token()
    supplied = request.headers.get("x-internal-token", "")
    if not expected or not hmac.compare_digest(supplied, expected):
        return JSONResponse(status_code=401, content={"error": {"code": "UNAUTHORIZED", "message": "invalid internal token"}})
    return await call_next(request)


@app.exception_handler(MlError)
async def ml_error(_: Request, e: MlError):
    return JSONResponse(status_code=e.status, content={"error": {"code": e.code, "message": e.message, "details": e.details}})


@app.exception_handler(RequestValidationError)
async def validation_error(_: Request, e: RequestValidationError):
    errors = [{"loc": list(err.get("loc", [])), "msg": err.get("msg")} for err in e.errors()]
    return JSONResponse(status_code=422, content={"error": {"code": "VALIDATION_FAILED", "message": "invalid request", "details": {"errors": errors}}})


@app.get("/health")
def health() -> dict:
    models = state.registry.describe() if state.registry else {}
    return {"status": "ok", "models": models}


@app.get("/v1/models")
def models() -> dict:
    return {"models": state.registry.describe() if state.registry else {}}


app.include_router(vision.router)
app.include_router(shelf_life.router)
app.include_router(forecast.router)
app.include_router(routing.router)
