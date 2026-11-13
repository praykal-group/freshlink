"""Solomon VRPTW instances: loader for the standard text format + seeded Solomon-style generator.

Real files (C101.txt, R101.txt, RC101.txt) go in ml/training/data/routing/ (gitignored). When they
are absent, `synthetic()` builds clustered (C), random (R) and mixed (RC) instances with the same
shape (depot + 100 customers, 25 vehicles of capacity 200); results are then labelled synthetic.
"""

import random
from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple


@dataclass
class Instance:
    name: str
    source: str  # "solomon" | "synthetic"
    vehicles: int
    capacity: float
    # rows: (id, x, y, demand, ready, due, service); row 0 = depot
    rows: List[Tuple[int, float, float, float, float, float, float]]


def load(path: Path) -> Instance:
    lines = [l.strip() for l in path.read_text().splitlines() if l.strip()]
    vi = next(i for i, l in enumerate(lines) if l.upper().startswith("VEHICLE"))
    vehicles, capacity = map(float, lines[vi + 2].split()[:2])
    ci = next(i for i, l in enumerate(lines) if l.upper().startswith("CUSTOMER"))
    rows = []
    for l in lines[ci + 1 :]:
        parts = l.split()
        if len(parts) >= 7 and parts[0].isdigit():
            i, x, y, d, r, due, s = parts[:7]
            rows.append((int(i), float(x), float(y), float(d), float(r), float(due), float(s)))
    return Instance(path.stem.upper(), "solomon", int(vehicles), capacity, rows)


def synthetic(kind: str, n: int = 100, seed: int = 101) -> Instance:
    rng = random.Random(f"{kind}-{seed}")
    depot = (40.0, 50.0)
    horizon = 1236.0 if kind != "RC" else 960.0
    pts: List[Tuple[float, float]] = []
    if kind in ("C", "RC"):
        n_clustered = n if kind == "C" else n // 2
        centres = [(rng.uniform(10, 90), rng.uniform(10, 90)) for _ in range(10)]
        for k in range(n_clustered):
            cx, cy = centres[k % len(centres)]
            pts.append((min(100, max(0, rng.gauss(cx, 3))), min(100, max(0, rng.gauss(cy, 3)))))
    while len(pts) < n:
        pts.append((rng.uniform(0, 100), rng.uniform(0, 100)))
    rows = [(0, depot[0], depot[1], 0.0, 0.0, horizon, 0.0)]
    for i, (x, y) in enumerate(pts, start=1):
        dist0 = ((x - depot[0]) ** 2 + (y - depot[1]) ** 2) ** 0.5
        width = {"C": 60.0, "R": 30.0, "RC": 40.0}[kind] + rng.uniform(0, 30)
        ready = rng.uniform(dist0, max(dist0 + 1, horizon - dist0 - width - 10))
        rows.append((i, x, y, float(rng.randint(10, 40)), round(ready), round(ready + width), 10.0 if kind != "C" else 90.0))
    return Instance(f"{kind}101-like", "synthetic", 25, 200.0, rows)
