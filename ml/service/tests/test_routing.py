import random
import time
from datetime import datetime, timedelta, timezone

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.routing import travel
from app.core.routing.ga import cheapest_insertion, decode, encode, solve
from app.core.routing.problem import Problem, Stop, Vehicle, evaluate, evaluate_route, manual_order
from app.core.routing.travel import TravelMatrix, euclidean_matrix, haversine_km, haversine_matrix
from app.main import app

H = {"X-Internal-Token": "test-token-123"}


@pytest.fixture(autouse=True)
def token(monkeypatch, tmp_path):
    monkeypatch.setenv("ML_INTERNAL_TOKEN", "test-token-123")
    monkeypatch.setenv("MODELS_DIR", str(tmp_path))
    monkeypatch.delenv("ROUTING_PROVIDER", raising=False)


# ───────────── travel matrices ─────────────

def test_haversine_mumbai_pune_is_about_120_km():
    assert 115 < haversine_km((19.0760, 72.8777), (18.5204, 73.8567)) < 125


def test_haversine_matrix_applies_road_factor_and_peak_speed():
    t0 = datetime(2026, 11, 13, 3, 30, tzinfo=timezone.utc)  # 09:00 IST → peak
    m = haversine_matrix([(19.87, 75.34), (19.97, 75.34)], t0)
    assert m.dist_km[0][1] == pytest.approx(haversine_km((19.87, 75.34), (19.97, 75.34)) * 1.3)
    assert m.travel_min(0, 1, 0) > m.dur_min[0][1]  # 28 km/h at peak vs 40 base
    assert m.travel_min(0, 1, 14 * 60) < m.dur_min[0][1]  # 23:00 IST night speed


def test_osrm_matrix_parses_the_table_service():
    def handler(req: httpx.Request):
        assert "/table/v1/driving/75.340000,19.870000;75.350000,19.880000" in str(req.url)
        return httpx.Response(200, json={"code": "Ok", "distances": [[0, 1500], [1600, 0]], "durations": [[0, 180], [200, 0]]})

    m = travel.osrm_matrix([(19.87, 75.34), (19.88, 75.35)], "http://osrm", httpx.Client(transport=httpx.MockTransport(handler)))
    assert m.dist_km[0][1] == 1.5 and m.dur_min[1][0] == pytest.approx(200 / 60) and m.provider == "osrm"


def test_google_matrix_prefers_traffic_duration():
    def handler(req: httpx.Request):
        el = {"status": "OK", "distance": {"value": 2000}, "duration": {"value": 300}, "duration_in_traffic": {"value": 420}}
        return httpx.Response(200, json={"status": "OK", "rows": [{"elements": [el, el]} for _ in req.url.params["origins"].split("|")]})

    m = travel.google_matrix([(19.87, 75.34), (19.88, 75.35)], "key", httpx.Client(transport=httpx.MockTransport(handler)))
    assert m.dist_km[0][1] == 2.0 and m.dur_min[0][1] == 7.0


def test_build_matrix_falls_back_to_haversine(monkeypatch):
    monkeypatch.setenv("ROUTING_PROVIDER", "osrm")
    monkeypatch.setenv("OSRM_URL", "http://127.0.0.1:9")  # nothing listens there
    m, reason = travel.build_matrix([(19.87, 75.34), (19.88, 75.35)])
    assert m.provider == "haversine" and reason and reason.startswith("osrm failed")


# ───────────── route evaluation ─────────────

def line_problem(**stop_kw):
    """Depot at 0, stops on a line, 1 distance unit = 1 minute."""
    m = euclidean_matrix([(0, 0), (0, 0), (10, 0), (20, 0)])
    return Problem(m, [Vehicle("V0", 100, 1, None)], [Stop("A", 2, 40, **stop_kw), Stop("B", 3, 40)])


def test_evaluation_waits_for_window_and_counts_lateness():
    p = line_problem(window_start=30, window_end=35)
    r = evaluate_route(p, 0, [0, 1], keep_visits=True)
    assert r.visits[0].arrival == 10 and r.visits[0].start == 30  # waited
    assert r.visits[1].arrival == 40 and r.late_min == 0
    late = evaluate_route(line_problem(window_end=5), 0, [0, 1])
    assert late.late_min == 5


def test_evaluation_counts_overload_spoilage_wrong_vehicle_and_shift_end():
    m = euclidean_matrix([(0, 0), (0, 0), (0, 0), (10, 0), (20, 0)])
    p = Problem(m, [Vehicle("V0", 50, 1, 30), Vehicle("V1", 50, 2)], [Stop("A", 3, 40, shelf_limit=5, must_vehicle=1), Stop("B", 4, 40)])
    r = evaluate_route(p, 0, [0, 1])
    assert r.overload == 30 and r.spoil_min == 5 and r.wrong_vehicle == 1
    assert r.late_min == pytest.approx(10)  # back at the depot at 40, shift ends at 30
    assert r.distance_km == 40


# ───────────── encoding, seed, constraints ─────────────

def random_problem(rng, n_veh=3, n_stops=10, prefix=False):
    pts = [(0.0, 0.0)] + [(rng.uniform(0, 50), rng.uniform(0, 50)) for _ in range(n_veh)] + [(rng.uniform(0, 100), rng.uniform(0, 100)) for _ in range(n_stops)]
    vehicles = [Vehicle(f"V{i}", 1000, 1 + i) for i in range(n_veh)]
    stops = [Stop(f"S{k}", 1 + n_veh + k, 10) for k in range(n_stops)]
    fixed = {v: [v] for v in range(n_veh)} if prefix else {}
    return Problem(euclidean_matrix(pts), vehicles, stops, 0, fixed)


def test_encode_decode_roundtrip_with_fixed_prefix():
    p = random_problem(random.Random(1), prefix=True)
    routes = cheapest_insertion(p)
    free = p.free_stops
    assert decode(p, encode(routes, p, free), free) == routes
    for v, r in enumerate(routes):
        assert r[0] == v  # prefix opens every route


def test_ga_keeps_fixed_prefix_and_must_vehicle():
    rng = random.Random(5)
    p = random_problem(rng, n_veh=3, n_stops=12, prefix=True)
    p.stops[7].must_vehicle = 2
    res = solve(p, seed=1, time_limit_s=2, generations=60, pop_size=40)
    for v, route in enumerate(res.solution.routes):
        assert route[0] == v
    assert 7 in res.solution.routes[2]
    assert res.solution.wrong_vehicle == 0
    assert sorted(s for r in res.solution.routes for s in r) == list(range(12))  # every stop exactly once


def planted_instance(seed: int):
    """Random instance built from a hidden feasible plan: windows around its arrivals, capacity around its loads."""
    rng = random.Random(seed)
    n_veh, n_stops = rng.randint(2, 4), rng.randint(8, 15)
    pts = [(50.0, 50.0)] + [(50.0, 50.0)] * n_veh + [(rng.uniform(0, 100), rng.uniform(0, 100)) for _ in range(n_stops)]
    m = euclidean_matrix(pts)
    order = list(range(n_stops))
    rng.shuffle(order)
    plan = [order[v::n_veh] for v in range(n_veh)]
    demand = [float(rng.randint(5, 40)) for _ in range(n_stops)]
    cap = max(sum(demand[s] for s in r) for r in plan) * 1.15
    stops = [Stop(f"S{k}", 1 + n_veh + k, demand[k]) for k in range(n_stops)]
    for v, r in enumerate(plan):
        t, node = 0.0, 1 + v
        for s in r:
            t += m.dur_min[node][stops[s].node]
            stops[s].window_start = max(0.0, t - rng.uniform(20, 60))
            stops[s].window_end = t + rng.uniform(30, 90)
            t += 5
            stops[s].service = 5
            node = stops[s].node
    return Problem(m, [Vehicle(f"V{i}", cap, 1 + i) for i in range(n_veh)], stops)


def test_property_ga_respects_capacity_and_time_windows_on_50_feasible_instances():
    failures = []
    for seed in range(50):
        p = planted_instance(seed)
        sol = solve(p, seed=seed, time_limit_s=2, generations=80, pop_size=50).solution
        if sol.overload > 1e-6 or sol.late_min > 1e-6:
            failures.append((seed, round(sol.overload, 2), round(sol.late_min, 2)))
        assert sorted(s for r in sol.routes for s in r) == list(range(len(p.stops)))
    assert failures == []


def test_ga_beats_the_manual_dispatch_order_by_at_least_10_percent():
    rng = random.Random(7)
    depot = (19.8762, 75.3433)
    pts = [depot] + [depot] * 10 + [(depot[0] + rng.uniform(-0.25, 0.25), depot[1] + rng.uniform(-0.3, 0.3)) for _ in range(50)]
    m = haversine_matrix(pts)
    vehicles = [Vehicle(f"V{i}", 3000, 1 + i, 12 * 60) for i in range(10)]
    stops = []
    for k in range(50):
        ws = rng.choice([0, 60, 120, 180])
        stops.append(Stop(f"S{k}", 11 + k, rng.uniform(100, 500), ws, ws + 240, 10))
    p = Problem(m, vehicles, stops)
    manual = evaluate(p, manual_order(p))
    ga = solve(p, seed=1).solution
    assert ga.feasible
    assert ga.distance_km <= 0.9 * manual.distance_km


# ───────────── API ─────────────

T0 = datetime(2026, 11, 13, 1, 30, tzinfo=timezone.utc)  # 07:00 IST


def city_request(n_veh=10, n_stops=50, mode="INITIAL", seed=3):
    rng = random.Random(seed)
    dep = {"lat": 19.8762, "lng": 75.3433}
    vehicles = [{"id": f"V{i}", "capacityKg": 3000, "shiftEnd": (T0 + timedelta(hours=12)).isoformat()} for i in range(n_veh)]
    if mode == "REPLAN":
        for v in vehicles:
            v["start"] = {"lat": dep["lat"] + rng.uniform(-0.2, 0.2), "lng": dep["lng"] + rng.uniform(-0.2, 0.2)}
    stops = []
    for k in range(n_stops):
        ws = T0 + timedelta(minutes=rng.choice([0, 60, 120, 180]))
        stops.append({
            "id": f"S{k}", "lat": dep["lat"] + rng.uniform(-0.25, 0.25), "lng": dep["lng"] + rng.uniform(-0.3, 0.3),
            "demandKg": rng.uniform(100, 400), "windowStart": ws.isoformat(), "windowEnd": (ws + timedelta(hours=4)).isoformat(),
            "serviceMin": 10, "shelfLifeH": rng.uniform(6, 30),
        })
    body = {"mode": mode, "depot": dep, "vehicles": vehicles, "stops": stops, "departAt": T0.isoformat(), "seed": 1}
    if mode == "REPLAN":
        body["fixedPrefix"] = {f"V{i}": [f"S{i}"] for i in range(n_veh)}
    return body


def test_optimize_contract():
    with TestClient(app) as c:
        r = c.post("/v1/routes/optimize", headers=H, json=city_request(3, 12))
    assert r.status_code == 200, r.text
    b = r.json()
    assert b["solver"] == "GA" and b["travelProvider"] == "haversine" and b["feasible"] is True
    assert sorted(s["id"] for route in b["routes"] for s in route["stops"]) == sorted(f"S{k}" for k in range(12))
    first = next(route["stops"][0] for route in b["routes"] if route["stops"])
    # Python 3.10's fromisoformat does not accept a trailing "Z" (3.11+ does).
    assert datetime.fromisoformat(first["eta"].replace("Z", "+00:00")) > T0


def test_replan_10_vehicles_50_stops_under_10_seconds_and_keeps_prefix():
    with TestClient(app) as c:
        t = time.perf_counter()
        r = c.post("/v1/routes/optimize", headers=H, json=city_request(mode="REPLAN"))
        elapsed = time.perf_counter() - t
    assert r.status_code == 200, r.text
    assert elapsed < 10.0
    for route in r.json()["routes"]:
        assert route["stops"][0]["id"] == f"S{route['vehicleId'][1:]}"


def test_baseline_contract():
    with TestClient(app) as c:
        body = city_request(3, 12)
        body["timeLimitS"] = 2
        r = c.post("/v1/routes/baseline", headers=H, json=body)
    assert r.status_code == 200, r.text
    assert r.json()["solver"] == "OR_TOOLS"
    assert sum(len(route["stops"]) for route in r.json()["routes"]) == 12


@pytest.mark.parametrize(
    "mutate,code",
    [
        (lambda b: b["stops"][0].update(mustKeepVehicle="NOPE"), "UNKNOWN_VEHICLE"),
        (lambda b: b.update(fixedPrefix={"V0": ["S1"]}), "INVALID_MODE"),
        (lambda b: b["stops"][0].update(windowEnd=T0.isoformat(), windowStart=(T0 + timedelta(hours=1)).isoformat()), "INVALID_WINDOW"),
        (lambda b: b["stops"].append(dict(b["stops"][0])), "DUPLICATE_ID"),
    ],
)
def test_optimize_validation(mutate, code):
    body = city_request(2, 4)
    mutate(body)
    with TestClient(app) as c:
        r = c.post("/v1/routes/optimize", headers=H, json=body)
    assert r.status_code == 422 and r.json()["error"]["code"] == code
