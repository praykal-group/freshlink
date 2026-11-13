"""Open-Meteo daily forecast (no key, Section 8). Optional: without OPEN_METEO_URL or site coordinates,
or on any error, the simulated weather of the same world is used (D-67)."""

import os
from datetime import date
from typing import List, Optional, Tuple

import httpx

Daily = Tuple[float, float]  # (rain_mm, temp_c)


def fetch_daily(lat: float, lng: float, start: date, end: date, client: Optional[httpx.Client] = None) -> Optional[List[Daily]]:
    base = os.environ.get("OPEN_METEO_URL")
    if not base:
        return None
    try:
        c = client or httpx.Client(timeout=4.0)
        r = c.get(
            f"{base.rstrip('/')}/v1/forecast",
            params={
                "latitude": lat,
                "longitude": lng,
                "daily": "precipitation_sum,temperature_2m_mean",
                "timezone": "Asia/Kolkata",
                "start_date": start.isoformat(),
                "end_date": end.isoformat(),
            },
        )
        r.raise_for_status()
        daily = r.json()["daily"]
        rains, temps = daily["precipitation_sum"], daily["temperature_2m_mean"]
        n = (end - start).days + 1
        if len(rains) != n or len(temps) != n or any(v is None for v in rains + temps):
            return None
        return [(float(rv), float(tv)) for rv, tv in zip(rains, temps)]
    except (httpx.HTTPError, KeyError, ValueError, TypeError):
        return None
