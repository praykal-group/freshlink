"""Route optimiser benchmarks (ML-04, M6 tests). Writes measured numbers to out/metrics.json.

    python ml/training/routing/benchmark.py --out ml/training/routing/out

1. GA vs OR-Tools on Solomon C101/R101/RC101 (real files if present, else Solomon-style synthetic).
2. Chh. Sambhajinagar case, 10 vehicles / 50 stops: GA vs the dispatcher's manual order.
3. REPLAN latency for 10 vehicles / 50 stops (target < 10 s).
"""

import argparse
import json
import random
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "ml" / "service"))
sys.path.insert(0, str(HERE))

from app.core.routing import baseline  # noqa: E402
from app.core.routing.ga import solve  # noqa: E402
from app.core.routing.problem import Problem, Stop, Vehicle, evaluate, manual_order  # noqa: E402
from app.core.routing.travel import euclidean_matrix, haversine_matrix  # noqa: E402
from solomon import load, synthetic  # noqa: E402

DATA = HERE.parents[0] / "data" / "routing"
DEPOT = (19.8762, 75.3433)  # Chh. Sambhajinagar distribution centre (seed site DC-CSN)


def problem_from_instance(inst):
    pts = [(r[1], r[2]) for r in inst.rows]
    # Node 0 depot; vehicle starts = depot (index 0 reused through extra nodes)
    all_pts = [pts[0]] + [pts[0]] * inst.vehicles + pts[1:]
    m = euclidean_matrix(all_pts)
    vehicles = [Vehicle(f"V{i}", inst.capacity, 1 + i, inst.rows[0][5]) for i in range(inst.vehicles)]
    stops = [Stop(str(r[0]), 1 + inst.vehicles + k, r[3], r[4], r[5], r[6], None) for k, r in enumerate(inst.rows[1:])]
    return Problem(m, vehicles, stops)


def city_problem(seed=7, n_veh=10, n_stops=50):
    rng = random.Random(seed)
    pts = [DEPOT] + [DEPOT] * n_veh + [(DEPOT[0] + rng.uniform(-0.25, 0.25), DEPOT[1] + rng.uniform(-0.3, 0.3)) for _ in range(n_stops)]
    m = haversine_matrix(pts)
    vehicles = [Vehicle(f"V{i}", 3000, 1 + i, 12 * 60) for i in range(n_veh)]
    stops = []
    for k in range(n_stops):
        ws = rng.choice([0, 60, 120, 180])
        stops.append(Stop(f"S{k}", 1 + n_veh + k, rng.uniform(100, 500), ws, ws + 240, 10, rng.uniform(6, 30) * 60))
    return Problem(m, vehicles, stops)


def replan_problem(seed=11, n_veh=10, n_stops=50):
    """Mid-day REPLAN: trucks are on the road (own start positions), each committed to its next stop
    (fixed prefix), two hours into the windows."""
    rng = random.Random(seed)
    starts = [(DEPOT[0] + rng.uniform(-0.2, 0.2), DEPOT[1] + rng.uniform(-0.2, 0.2)) for _ in range(n_veh)]
    stop_pts = [(DEPOT[0] + rng.uniform(-0.25, 0.25), DEPOT[1] + rng.uniform(-0.3, 0.3)) for _ in range(n_stops)]
    m = haversine_matrix([DEPOT] + starts + stop_pts)
    vehicles = [Vehicle(f"V{i}", 3000, 1 + i, 10 * 60) for i in range(n_veh)]
    stops = []
    for k in range(n_stops):
        ws = rng.choice([-60, 0, 60, 120])
        stops.append(Stop(f"S{k}", 1 + n_veh + k, rng.uniform(100, 400), ws, ws + 240, 10, rng.uniform(4, 20) * 60))
    return Problem(m, vehicles, stops, 0, {v: [v] for v in range(n_veh)})


def run_ga(p, seed=1):
    t = time.perf_counter()
    r = solve(p, seed=seed)
    return r, time.perf_counter() - t


def summary(sol, seconds):
    return {
        "fitness": round(sol.fitness, 2), "distance": round(sol.distance_km, 2), "lateMin": round(sol.late_min, 1),
        "overload": round(sol.overload, 2), "feasible": sol.feasible, "seconds": round(seconds, 2),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--ortools-seconds", type=int, default=30)
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    results = {"solomon": [], "city": None, "replan": None}

    for kind in ("C", "R", "RC"):
        path = DATA / f"{kind}101.txt"
        inst = load(path) if path.exists() else synthetic(kind)
        p = problem_from_instance(inst)
        ga, ga_s = run_ga(p)
        t = time.perf_counter()
        ort = baseline.solve(p, args.ortools_seconds)
        ort_s = time.perf_counter() - t
        row = {
            "instance": inst.name, "source": inst.source, "customers": len(inst.rows) - 1,
            "ga": {**summary(ga.solution, ga_s), "generations": ga.generations, "stoppedBy": ga.stopped_by},
            "ortools": summary(ort, ort_s),
            "gapFitnessPct": round(100 * (ga.solution.fitness - ort.fitness) / max(ort.fitness, 1e-9), 2),
            "gapDistancePct": round(100 * (ga.solution.distance_km - ort.distance_km) / max(ort.distance_km, 1e-9), 2),
        }
        results["solomon"].append(row)
        print(json.dumps(row))

    p = city_problem()
    manual = evaluate(p, manual_order(p))
    ga, ga_s = run_ga(p)
    results["city"] = {
        "case": "Chh. Sambhajinagar synthetic, 10 vehicles / 50 stops, haversine x1.3",
        "manual": summary(manual, 0),
        "ga": {**summary(ga.solution, ga_s), "generations": ga.generations, "stoppedBy": ga.stopped_by},
        "distanceSavingPct": round(100 * (1 - ga.solution.distance_km / manual.distance_km), 2),
    }
    print(json.dumps(results["city"]))

    rp = replan_problem()
    ga, ga_s = run_ga(rp, seed=3)
    results["replan"] = {"vehicles": 10, "stops": 50, **summary(ga.solution, ga_s), "generations": ga.generations, "stoppedBy": ga.stopped_by}
    print(json.dumps(results["replan"]))

    results["measuredAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (out / "metrics.json").write_text(json.dumps(results, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
