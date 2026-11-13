"""Travel matrices (D-13): haversine (default, no API), OSRM table, Google Distance Matrix.

All providers return distance in km and duration in minutes between every pair of points.
Haversine also carries a time-of-day speed factor; OSRM/Google durations are used as given.
If a remote provider fails, the caller falls back to haversine and reports which one was used.
"""

import math
import os
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Callable, List, Optional, Sequence, Tuple

import httpx

LatLng = Tuple[float, float]

ROAD_FACTOR = 1.3  # straight line → road distance (Section D-13)
IST = timezone(timedelta(hours=5, minutes=30))

# Indicative speed profile for city/peri-urban reefer trucks (km/h by IST hour). Replace with
# measured trip data once telemetry exists.
BASE_SPEED_KMH = 40.0


def speed_kmh(hour: int) -> float:
    if 8 <= hour < 11 or 17 <= hour < 20:
        return 28.0  # peaks
    if hour >= 22 or hour < 6:
        return 50.0  # night
    return BASE_SPEED_KMH


def haversine_km(a: LatLng, b: LatLng) -> float:
    r = 6371.0088
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp, dl = p2 - p1, math.radians(b[1] - a[1])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(h)))


@dataclass
class TravelMatrix:
    dist_km: List[List[float]]
    dur_min: List[List[float]]
    provider: str
    # minute offset from t0 → multiplier on dur_min (haversine only); None = constant.
    time_factor: Optional[Callable[[float], float]] = None

    def travel_min(self, i: int, j: int, depart_min: float) -> float:
        base = self.dur_min[i][j]
        return base if self.time_factor is None else base * self.time_factor(depart_min)


def haversine_matrix(points: Sequence[LatLng], t0: Optional[datetime] = None) -> TravelMatrix:
    n = len(points)
    dist = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i + 1, n):
            d = haversine_km(points[i], points[j]) * ROAD_FACTOR
            dist[i][j] = dist[j][i] = d
    dur = [[d / BASE_SPEED_KMH * 60.0 for d in row] for row in dist]
    start = (t0 or datetime.now(timezone.utc)).astimezone(IST)

    def factor(minute: float) -> float:
        hour = (start + timedelta(minutes=minute)).hour
        return BASE_SPEED_KMH / speed_kmh(hour)

    return TravelMatrix(dist, dur, "haversine", factor)


def euclidean_matrix(points: Sequence[Tuple[float, float]]) -> TravelMatrix:
    """Benchmarks (Solomon): distance units = time units, no speed profile."""
    n = len(points)
    dist = [[math.dist(points[i], points[j]) for j in range(n)] for i in range(n)]
    return TravelMatrix(dist, [row[:] for row in dist], "euclidean", None)


def osrm_matrix(points: Sequence[LatLng], base_url: str, client: Optional[httpx.Client] = None) -> TravelMatrix:
    coords = ";".join(f"{lng:.6f},{lat:.6f}" for lat, lng in points)
    url = f"{base_url.rstrip('/')}/table/v1/driving/{coords}"
    c = client or httpx.Client(timeout=5.0)
    r = c.get(url, params={"annotations": "distance,duration"})
    r.raise_for_status()
    body = r.json()
    if body.get("code") != "Ok":
        raise RuntimeError(f"OSRM: {body.get('code')}")
    dist = [[(v or 0.0) / 1000.0 for v in row] for row in body["distances"]]
    dur = [[(v or 0.0) / 60.0 for v in row] for row in body["durations"]]
    return TravelMatrix(dist, dur, "osrm", None)


GOOGLE_URL = "https://maps.googleapis.com/maps/api/distancematrix/json"
GOOGLE_MAX_ELEMENTS = 100  # per request (Distance Matrix limit)


def google_matrix(points: Sequence[LatLng], api_key: str, client: Optional[httpx.Client] = None) -> TravelMatrix:
    n = len(points)
    dist = [[0.0] * n for _ in range(n)]
    dur = [[0.0] * n for _ in range(n)]
    c = client or httpx.Client(timeout=10.0)
    fmt = lambda p: f"{p[0]:.6f},{p[1]:.6f}"  # noqa: E731
    rows_per_call = max(1, GOOGLE_MAX_ELEMENTS // n)
    for start in range(0, n, rows_per_call):
        origins = points[start : start + rows_per_call]
        r = c.get(
            GOOGLE_URL,
            params={
                "origins": "|".join(map(fmt, origins)),
                "destinations": "|".join(map(fmt, points)),
                "departure_time": "now",
                "key": api_key,
            },
        )
        r.raise_for_status()
        body = r.json()
        if body.get("status") != "OK":
            raise RuntimeError(f"Google: {body.get('status')}")
        for oi, row in enumerate(body["rows"]):
            for dj, el in enumerate(row["elements"]):
                if el.get("status") != "OK":
                    raise RuntimeError(f"Google element: {el.get('status')}")
                dist[start + oi][dj] = el["distance"]["value"] / 1000.0
                d = el.get("duration_in_traffic") or el["duration"]
                dur[start + oi][dj] = d["value"] / 60.0
    return TravelMatrix(dist, dur, "google", None)


def build_matrix(points: Sequence[LatLng], t0: Optional[datetime] = None) -> Tuple[TravelMatrix, Optional[str]]:
    """Provider from ROUTING_PROVIDER; any failure falls back to haversine. Returns (matrix, fallback_reason)."""
    provider = os.environ.get("ROUTING_PROVIDER", "haversine").lower()
    try:
        if provider == "osrm" and os.environ.get("OSRM_URL"):
            return osrm_matrix(points, os.environ["OSRM_URL"]), None
        if provider == "google" and os.environ.get("GOOGLE_MAPS_API_KEY"):
            return google_matrix(points, os.environ["GOOGLE_MAPS_API_KEY"]), None
        if provider not in ("haversine", "osrm", "google"):
            return haversine_matrix(points, t0), f"unknown provider {provider}"
        if provider != "haversine":
            return haversine_matrix(points, t0), f"{provider} not configured"
    except (httpx.HTTPError, RuntimeError, KeyError, ValueError) as e:
        return haversine_matrix(points, t0), f"{provider} failed: {e.__class__.__name__}"
    return haversine_matrix(points, t0), None
