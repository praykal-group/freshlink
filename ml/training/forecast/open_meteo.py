"""Open-Meteo historical daily weather (no key) for training features.

    python open_meteo.py --lat 19.8762 --lng 75.3433 --start 2023-01-01 --end 2025-12-31 --out weather.csv
"""

import argparse
import csv

import httpx

ARCHIVE = "https://archive-api.open-meteo.com/v1/archive"


def fetch(lat: float, lng: float, start: str, end: str):
    r = httpx.get(
        ARCHIVE,
        params={"latitude": lat, "longitude": lng, "start_date": start, "end_date": end,
                "daily": "precipitation_sum,temperature_2m_mean", "timezone": "Asia/Kolkata"},
        timeout=60,
    )
    r.raise_for_status()
    d = r.json()["daily"]
    return list(zip(d["time"], d["precipitation_sum"], d["temperature_2m_mean"]))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--lat", type=float, required=True)
    ap.add_argument("--lng", type=float, required=True)
    ap.add_argument("--start", required=True)
    ap.add_argument("--end", required=True)
    ap.add_argument("--out", default="weather.csv")
    a = ap.parse_args()
    rows = fetch(a.lat, a.lng, a.start, a.end)
    with open(a.out, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["date", "rain_mm", "temp_c"])
        w.writerows(rows)
    print(f"wrote {len(rows)} days to {a.out}")
