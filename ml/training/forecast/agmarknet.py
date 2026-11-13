"""Agmarknet mandi prices → daily modal price series (Section 8).

Two ways in:
  1. Manual CSV export from agmarknet.gov.in (columns include Arrival_Date / Price Date and Modal_Price / Modal Price)
  2. data.gov.in API (resource "Current daily price of various commodities from various markets (Mandi)"),
     key in DATA_GOV_IN_KEY:  python agmarknet.py --api --commodity Tomato --state Maharashtra --out prices.csv
Prices are Rs/quintal in the source; this loader keeps the unit and averages markets per day.
"""

import argparse
import csv
import os
import sys
from collections import defaultdict
from datetime import date, datetime
from typing import Dict

API = "https://api.data.gov.in/resource/9ef84268-d588-465a-a308-a864a43d0070"
DATE_KEYS = ("Arrival_Date", "Price Date", "arrival_date", "date")
PRICE_KEYS = ("Modal_Price", "Modal Price", "modal_price", "Modal Price (Rs./Quintal)")


def _parse_date(s: str) -> date:
    for fmt in ("%d/%m/%Y", "%d-%m-%Y", "%Y-%m-%d", "%d %b %Y"):
        try:
            return datetime.strptime(s.strip(), fmt).date()
        except ValueError:
            continue
    raise ValueError(f"unknown date format: {s!r}")


def load_daily_prices(path: str) -> Dict[date, float]:
    sums: Dict[date, list] = defaultdict(list)
    with open(path, newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            dk = next((k for k in DATE_KEYS if k in row), None)
            pk = next((k for k in PRICE_KEYS if k in row), None)
            if not dk or not pk or not row[pk].strip():
                continue
            try:
                sums[_parse_date(row[dk])].append(float(row[pk].replace(",", "")))
            except ValueError:
                continue
    return {d: sum(v) / len(v) for d, v in sums.items()}


def fetch_api(commodity: str, state: str, out: str, limit: int = 1000) -> None:
    import httpx

    key = os.environ.get("DATA_GOV_IN_KEY")
    if not key:
        sys.exit("set DATA_GOV_IN_KEY (free key from data.gov.in)")
    rows, offset = [], 0
    with httpx.Client(timeout=30) as c:
        while True:
            r = c.get(API, params={"api-key": key, "format": "json", "limit": limit, "offset": offset,
                                   "filters[commodity]": commodity, "filters[state]": state})
            r.raise_for_status()
            recs = r.json().get("records", [])
            rows += recs
            if len(recs) < limit:
                break
            offset += limit
    with open(out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["arrival_date", "market", "commodity", "modal_price"])
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k) for k in w.fieldnames})
    print(f"wrote {len(rows)} rows to {out}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--api", action="store_true")
    ap.add_argument("--commodity")
    ap.add_argument("--state", default="Maharashtra")
    ap.add_argument("--out", default="prices.csv")
    a = ap.parse_args()
    if a.api:
        fetch_api(a.commodity, a.state, a.out)
