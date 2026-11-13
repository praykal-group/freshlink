"""OR-Tools VRPTW baseline (comparison only, Section 8). INITIAL mode; soft window ends.

OR-Tools is a dev/training dependency (D-65). Its routes are re-scored with the same evaluator as
the GA, so both numbers use one cost function.
"""

from typing import List

from .problem import Problem, Solution, W_LATE, evaluate

SCALE = 100  # OR-Tools works in integers: 0.01 km / 0.01 min


def available() -> bool:
    try:
        import ortools  # noqa: F401
    except ImportError:
        return False
    return True


def solve(p: Problem, time_limit_s: int = 8) -> Solution:
    from ortools.constraint_solver import pywrapcp, routing_enums_pb2

    if p.fixed_prefix:
        raise ValueError("baseline supports INITIAL mode only (no fixed prefix)")

    # OR-Tools nodes: 0 = depot, then vehicle start nodes, then stops (matrix nodes may repeat).
    nodes = [p.depot_node] + [v.start_node for v in p.vehicles] + [s.node for s in p.stops]
    first_stop = 1 + len(p.vehicles)
    starts = list(range(1, first_stop))
    ends = [0] * len(p.vehicles)
    manager = pywrapcp.RoutingIndexManager(len(nodes), len(p.vehicles), starts, ends)
    routing = pywrapcp.RoutingModel(manager)
    m = p.matrix

    def service(i: int) -> float:
        return p.stops[i - first_stop].service if i >= first_stop else 0.0

    def dist_cb(a, b):
        i, j = manager.IndexToNode(a), manager.IndexToNode(b)
        return int(m.dist_km[nodes[i]][nodes[j]] * SCALE)

    def time_cb(a, b):
        i, j = manager.IndexToNode(a), manager.IndexToNode(b)
        return int((m.dur_min[nodes[i]][nodes[j]] + service(i)) * SCALE)

    dist_idx = routing.RegisterTransitCallback(dist_cb)
    time_idx = routing.RegisterTransitCallback(time_cb)
    routing.SetArcCostEvaluatorOfAllVehicles(dist_idx)

    demand_idx = routing.RegisterUnaryTransitCallback(
        lambda a: int(p.stops[manager.IndexToNode(a) - first_stop].demand * SCALE) if manager.IndexToNode(a) >= first_stop else 0
    )
    routing.AddDimensionWithVehicleCapacity(demand_idx, 0, [int(v.capacity * SCALE) for v in p.vehicles], True, "Load")

    horizon = int(10 * 24 * 60 * SCALE)
    routing.AddDimension(time_idx, horizon, horizon, False, "Time")
    tdim = routing.GetDimensionOrDie("Time")
    # Same lateness weight as the GA. Arc cost unit = 0.01 km and the cumul unit = 0.01 min, so
    # W_LATE km per minute = W_LATE*100 units per 100 cumul units = W_LATE per cumul unit.
    late_coef = int(W_LATE)
    for k, s in enumerate(p.stops):
        idx = manager.NodeToIndex(first_stop + k)
        lo = int((s.window_start or 0) * SCALE)
        tdim.CumulVar(idx).SetMin(lo)
        if s.window_end is not None:
            tdim.SetCumulVarSoftUpperBound(idx, int(s.window_end * SCALE), late_coef)

    params = pywrapcp.DefaultRoutingSearchParameters()
    params.first_solution_strategy = routing_enums_pb2.FirstSolutionStrategy.PATH_CHEAPEST_ARC
    params.local_search_metaheuristic = routing_enums_pb2.LocalSearchMetaheuristic.GUIDED_LOCAL_SEARCH
    params.time_limit.seconds = int(time_limit_s)
    sol = routing.SolveWithParameters(params)
    if sol is None:
        raise RuntimeError("OR-Tools found no solution")

    routes: List[List[int]] = []
    for v in range(len(p.vehicles)):
        idx = routing.Start(v)
        seq: List[int] = []
        while not routing.IsEnd(idx):
            node = manager.IndexToNode(idx)
            if node >= first_stop:
                seq.append(node - first_stop)
            idx = sol.Value(routing.NextVar(idx))
        routes.append(seq)
    return evaluate(p, routes, keep_visits=True)
