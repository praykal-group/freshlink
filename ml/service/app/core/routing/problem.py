"""DVRPTW model and route evaluation (Section 8).

Time is in minutes from t0 (departure of the plan). Node 0 is the depot; each vehicle has its own
start node (its current position for REPLAN); stops follow. Routes end at the depot.

fitness = distance_km + 1000·late_min + 5000·overload_kg + 2000·spoil_min + 5000·wrong_vehicle
  late_min   minutes after a stop's window end (and after the vehicle's shift end on return)
  spoil_min  minutes a stop is served after its remaining shelf life
"""

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence

from .travel import TravelMatrix

W_LATE = 1000.0
W_OVERLOAD = 5000.0
W_SPOIL = 2000.0
W_WRONG_VEHICLE = 5000.0


@dataclass
class Stop:
    id: str
    node: int
    demand: float
    window_start: Optional[float] = None
    window_end: Optional[float] = None
    service: float = 0.0
    shelf_limit: Optional[float] = None  # minutes from t0 by which it must be served
    must_vehicle: Optional[int] = None  # vehicle index


@dataclass
class Vehicle:
    id: str
    capacity: float
    start_node: int
    shift_end: Optional[float] = None
    ready: float = 0.0


@dataclass
class Problem:
    matrix: TravelMatrix
    vehicles: List[Vehicle]
    stops: List[Stop]
    depot_node: int = 0
    # vehicle index -> stop indices that must open that vehicle's route, in order (REPLAN)
    fixed_prefix: Dict[int, List[int]] = field(default_factory=dict)
    return_to_depot: bool = True

    @property
    def free_stops(self) -> List[int]:
        fixed = {s for seq in self.fixed_prefix.values() for s in seq}
        return [i for i in range(len(self.stops)) if i not in fixed]


@dataclass
class Visit:
    stop: int
    arrival: float
    start: float
    late: float
    spoil: float


@dataclass
class RouteResult:
    vehicle: int
    visits: List[Visit]
    distance_km: float
    load: float
    late_min: float
    overload: float
    spoil_min: float
    wrong_vehicle: int
    end_time: float

    @property
    def cost(self) -> float:
        return (
            self.distance_km
            + W_LATE * self.late_min
            + W_OVERLOAD * self.overload
            + W_SPOIL * self.spoil_min
            + W_WRONG_VEHICLE * self.wrong_vehicle
        )


def evaluate_route(p: Problem, v: int, seq: Sequence[int], keep_visits: bool = False) -> RouteResult:
    veh = p.vehicles[v]
    m = p.matrix
    t = veh.ready
    node = veh.start_node
    dist = late = spoil = load = 0.0
    wrong = 0
    visits: List[Visit] = []
    for si in seq:
        s = p.stops[si]
        tt = m.travel_min(node, s.node, t)
        dist += m.dist_km[node][s.node]
        arrival = t + tt
        start = arrival if s.window_start is None else max(arrival, s.window_start)
        lt = 0.0 if s.window_end is None else max(0.0, start - s.window_end)
        sp = 0.0 if s.shelf_limit is None else max(0.0, start - s.shelf_limit)
        late += lt
        spoil += sp
        load += s.demand
        if s.must_vehicle is not None and s.must_vehicle != v:
            wrong += 1
        if keep_visits:
            visits.append(Visit(si, arrival, start, lt, sp))
        t = start + s.service
        node = s.node
    if seq and p.return_to_depot:
        t += m.travel_min(node, p.depot_node, t)
        dist += m.dist_km[node][p.depot_node]
    if veh.shift_end is not None and seq:
        late += max(0.0, t - veh.shift_end)
    return RouteResult(v, visits, dist, load, late, max(0.0, load - veh.capacity), spoil, wrong, t)


@dataclass
class Solution:
    routes: List[List[int]]  # per vehicle, stop indices (fixed prefix included)
    results: List[RouteResult]

    @property
    def fitness(self) -> float:
        return sum(r.cost for r in self.results)

    @property
    def distance_km(self) -> float:
        return sum(r.distance_km for r in self.results)

    @property
    def late_min(self) -> float:
        return sum(r.late_min for r in self.results)

    @property
    def overload(self) -> float:
        return sum(r.overload for r in self.results)

    @property
    def spoil_min(self) -> float:
        return sum(r.spoil_min for r in self.results)

    @property
    def wrong_vehicle(self) -> int:
        return sum(r.wrong_vehicle for r in self.results)

    @property
    def feasible(self) -> bool:
        return self.late_min < 1e-6 and self.overload < 1e-6 and self.spoil_min < 1e-6 and self.wrong_vehicle == 0


def evaluate(p: Problem, routes: List[List[int]], keep_visits: bool = False) -> Solution:
    return Solution(routes, [evaluate_route(p, v, r, keep_visits) for v, r in enumerate(routes)])


def manual_order(p: Problem) -> List[List[int]]:
    """Dispatcher baseline for ML-04: stops in the given order, filling vehicles one after another by capacity."""
    routes: List[List[int]] = [list(p.fixed_prefix.get(v, [])) for v in range(len(p.vehicles))]
    loads = [sum(p.stops[s].demand for s in r) for r in routes]
    v = 0
    for si in p.free_stops:
        d = p.stops[si].demand
        while v < len(routes) - 1 and loads[v] + d > p.vehicles[v].capacity:
            v += 1
        routes[v].append(si)
        loads[v] += d
    return routes
