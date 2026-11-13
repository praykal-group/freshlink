"""Export the simulated sales world (seeded, Section 2) to CSV for inspection or other tools.

    python ml/training/forecast/simulate_sales.py --sites 6 --products 10 --start 2023-01-01 --end 2025-12-31 --out sales.csv
"""

import argparse
import csv
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "ml" / "service"))

from app.core.forecast.simulate import series  # noqa: E402

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--sites", type=int, default=6)
    ap.add_argument("--products", type=int, default=10)
    ap.add_argument("--start", default="2023-01-01")
    ap.add_argument("--end", default="2025-12-31")
    ap.add_argument("--out", default="sales.csv")
    a = ap.parse_args()
    n = 0
    with open(a.out, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["site_id", "product_id", "date", "kg", "price", "rain_mm", "temp_c", "festival"])
        for i in range(1, a.sites + 1):
            for j in range(1, a.products + 1):
                for d in series(f"site-{i}", f"product-{j}", date.fromisoformat(a.start), date.fromisoformat(a.end)):
                    w.writerow([f"site-{i}", f"product-{j}", d.date.isoformat(), d.kg, d.price, d.rain_mm, d.temp_c, int(d.festival)])
                    n += 1
    print(f"wrote {n} rows to {a.out}")
