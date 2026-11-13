import time
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional

from fastapi import APIRouter
from starlette.concurrency import run_in_threadpool

from ..core.errors import MlError
from ..core.routing import baseline as ortools_baseline
from ..core.routing.ga import solve as ga_solve
from ..core.routing.problem import Problem, Solution, Stop, Vehicle
from ..core.routing.travel import build_matrix
from ..schemas.routing import OptimizeRequest, OptimizeResponse, RouteOut, StopOut, Violations

router = APIRouter(prefix="/v1/routes", tags=["routing"])


def _minutes(dt: Optional[datetime], t0: datetime) -> Optional[float]:
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return (dt - t0).total_seconds() / 60.0


def build_problem(req: OptimizeRequest):
    t0 = req.departAt or datetime.now(timezone.utc)
    if t0.tzinfo is None:
        t0 = t0.replace(tzinfo=timezone.utc)

    vehicle_ids = [v.id for v in req.vehicles]
    stop_ids = [s.id for s in req.stops]
    if len(set(vehicle_ids)) != len(vehicle_ids):
        raise MlError("DUPLICATE_ID", "vehicle ids must be unique", 422)
    if len(set(stop_ids)) != len(stop_ids):
        raise MlError("DUPLICATE_ID", "stop ids must be unique", 422)
    v_index = {vid: i for i, vid in enumerate(vehicle_ids)}
    s_index = {sid: i for i, sid in enumerate(stop_ids)}

    points = [(req.depot.lat, req.depot.lng)]
    for v in req.vehicles:
        start = v.start or req.depot
        points.append((start.lat, start.lng))
    first_stop = len(points)
    points += [(s.lat, s.lng) for s in req.stops]
    matrix, fallback = build_matrix(points, t0)

    vehicles = [Vehicle(v.id, v.capacityKg, 1 + i, _minutes(v.shiftEnd, t0)) for i, v in enumerate(req.vehicles)]
    stops: List[Stop] = []
    for k, s in enumerate(req.stops):
        if s.mustKeepVehicle is not None and s.mustKeepVehicle not in v_index:
            raise MlError("UNKNOWN_VEHICLE", f"stop {s.id}: mustKeepVehicle {s.mustKeepVehicle} is not in vehicles", 422)
        ws, we = _minutes(s.windowStart, t0), _minutes(s.windowEnd, t0)
        if ws is not None and we is not None and we < ws:
            raise MlError("INVALID_WINDOW", f"stop {s.id}: windowEnd is before windowStart", 422)
        stops.append(
            Stop(
                s.id,
                first_stop + k,
                s.demandKg,
                ws,
                we,
                s.serviceMin,
                None if s.shelfLifeH is None else s.shelfLifeH * 60.0,
                None if s.mustKeepVehicle is None else v_index[s.mustKeepVehicle],
            )
        )

    fixed: Dict[int, List[int]] = {}
    if req.fixedPrefix:
        if req.mode != "REPLAN":
            raise MlError("INVALID_MODE", "fixedPrefix is only allowed in REPLAN mode", 422)
        seen = set()
        for vid, seq in req.fixedPrefix.items():
            if vid not in v_index:
                raise MlError("UNKNOWN_VEHICLE", f"fixedPrefix vehicle {vid} is not in vehicles", 422)
            for sid in seq:
                if sid not in s_index or sid in seen:
                    raise MlError("INVALID_PREFIX", f"fixedPrefix stop {sid} is unknown or listed twice", 422)
                seen.add(sid)
            fixed[v_index[vid]] = [s_index[sid] for sid in seq]

    return Problem(matrix, vehicles, stops, 0, fixed), t0, matrix.provider, fallback


def to_response(sol: Solution, p: Problem, t0: datetime, solver: str, provider: str, fallback, started, generations=0, stopped_by=None):
    routes = []
    for v, res in enumerate(sol.results):
        routes.append(
            RouteOut(
                vehicleId=p.vehicles[v].id,
                stops=[
                    StopOut(id=p.stops[vis.stop].id, eta=t0 + timedelta(minutes=vis.arrival), lateMin=round(vis.late, 1))
                    for vis in res.visits
                ],
                distanceKm=round(res.distance_km, 3),
                loadKg=round(res.load, 3),
            )
        )
    return OptimizeResponse(
        routes=routes,
        fitness=round(sol.fitness, 3),
        distanceKm=round(sol.distance_km, 3),
        feasible=sol.feasible,
        violations=Violations(lateMin=round(sol.late_min, 1), overloadKg=round(sol.overload, 3), spoilMin=round(sol.spoil_min, 1), wrongVehicle=sol.wrong_vehicle),
        solver=solver,
        generations=generations,
        stoppedBy=stopped_by,
        travelProvider=provider,
        travelFallbackReason=fallback,
        latencyMs=int((time.perf_counter() - started) * 1000),
    )


@router.post("/optimize", response_model=OptimizeResponse)
async def optimize(req: OptimizeRequest) -> OptimizeResponse:
    """GA DVRPTW. ML-04: replan < 10 s for 10 vehicles / 50 stops (hard GA limit 8 s)."""
    started = time.perf_counter()
    p, t0, provider, fallback = await run_in_threadpool(build_problem, req)
    result = await run_in_threadpool(ga_solve, p, req.seed, req.timeLimitS)
    return to_response(result.solution, p, t0, "GA", provider, fallback, started, result.generations, result.stopped_by)


@router.post("/baseline", response_model=OptimizeResponse)
async def baseline(req: OptimizeRequest) -> OptimizeResponse:
    """OR-Tools VRPTW, for comparison tests only (INITIAL mode)."""
    if not ortools_baseline.available():
        raise MlError("BASELINE_UNAVAILABLE", "OR-Tools is not installed in this image", 503)
    started = time.perf_counter()
    p, t0, provider, fallback = await run_in_threadpool(build_problem, req)
    try:
        sol = await run_in_threadpool(ortools_baseline.solve, p, int(max(1, req.timeLimitS)))
    except ValueError as e:
        raise MlError("INVALID_MODE", str(e), 422) from e
    except RuntimeError as e:
        raise MlError("NO_SOLUTION", str(e), 422) from e
    return to_response(sol, p, t0, "OR_TOOLS", provider, fallback, started)
