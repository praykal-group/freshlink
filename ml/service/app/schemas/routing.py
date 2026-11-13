"""Route optimiser contract (Section 8): POST /v1/routes/optimize and /v1/routes/baseline."""

from datetime import datetime
from typing import Dict, List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


class _M(BaseModel):
    model_config = ConfigDict(extra="forbid")


class LatLng(_M):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


class VehicleIn(_M):
    id: str = Field(min_length=1, max_length=64)
    capacityKg: float = Field(gt=0)
    # INITIAL: defaults to the depot. REPLAN: the truck's current position.
    start: Optional[LatLng] = None
    shiftEnd: Optional[datetime] = None


class StopIn(_M):
    id: str = Field(min_length=1, max_length=64)
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    demandKg: float = Field(ge=0)
    windowStart: Optional[datetime] = None
    windowEnd: Optional[datetime] = None
    serviceMin: float = Field(default=10, ge=0, le=240)
    # Remaining shelf life of the cargo for this stop, in hours from departAt.
    shelfLifeH: Optional[float] = Field(default=None, ge=0)
    mustKeepVehicle: Optional[str] = None


class OptimizeRequest(_M):
    mode: Literal["INITIAL", "REPLAN"]
    depot: LatLng
    vehicles: List[VehicleIn] = Field(min_length=1, max_length=50)
    stops: List[StopIn] = Field(min_length=1, max_length=300)
    # REPLAN: per vehicle id, stop ids that must open its route in this order (e.g. the stop it is driving to).
    fixedPrefix: Optional[Dict[str, List[str]]] = None
    departAt: Optional[datetime] = None
    timeLimitS: float = Field(default=8.0, gt=0, le=8.0)
    seed: Optional[int] = None


class StopOut(_M):
    id: str
    eta: datetime
    lateMin: float


class RouteOut(_M):
    vehicleId: str
    stops: List[StopOut]
    distanceKm: float
    loadKg: float


class Violations(_M):
    lateMin: float
    overloadKg: float
    spoilMin: float
    wrongVehicle: int


class OptimizeResponse(_M):
    routes: List[RouteOut]
    fitness: float
    distanceKm: float
    feasible: bool
    violations: Violations
    solver: Literal["GA", "OR_TOOLS"]
    generations: int = 0
    stoppedBy: Optional[str] = None
    travelProvider: str
    travelFallbackReason: Optional[str] = None
    latencyMs: int
