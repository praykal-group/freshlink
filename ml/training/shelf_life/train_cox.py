"""Fit a Cox PH model on documented observations and export parameters for the service (D-54).

    python ml/training/shelf_life/train_cox.py --data observations.csv --out ml/training/shelf_life/out

Outputs:
  cox_params.json  {"features", "beta", "means", "baselineSurvival"} — evaluated by
                   ml/service/app/core/shelf_life.py (S(t|x) = S0(t) ** exp(beta·(x-means)))
  metrics.json     MEASURED C-index and median-time error on a held-out split (ML-02)
"""

import argparse
import json
import math
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "ml" / "service"))

from app.core.shelf_life import COX_FEATURES, CoxModel, Exposure  # noqa: E402

REQUIRED = [
    "source_id", "product_code", "base_shelf_life_h", "mean_temp_c", "degree_minutes_above", "humidity_pct",
    "ethylene_ppm", "shock_events", "grade", "duration_h", "event",
]
MIN_ROWS = 60
MIN_EVENTS = 20


def to_features(df):
    import numpy as np

    out = df.copy()
    out["log_base_shelf_life_h"] = np.log(out["base_shelf_life_h"].clip(lower=1))
    out["humidity_pct"] = out["humidity_pct"].fillna(90.0)
    out["ethylene_ppm"] = out["ethylene_ppm"].fillna(0.0)
    grade = out["grade"].fillna("A").astype(str).str.upper()
    out["grade_B"] = (grade == "B").astype(float)
    out["grade_C"] = (grade == "C").astype(float)
    return out[COX_FEATURES + ["duration_h", "event"]]


def main() -> None:
    import numpy as np
    import pandas as pd
    from lifelines import CoxPHFitter
    from lifelines.utils import concordance_index

    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--test-frac", type=float, default=0.2)
    ap.add_argument("--penalizer", type=float, default=0.01)
    args = ap.parse_args()

    df = pd.read_csv(args.data)
    missing = [c for c in REQUIRED if c not in df.columns]
    if missing:
        sys.exit(f"missing columns: {missing}")
    if df["source_id"].isna().any() or (df["source_id"].astype(str).str.strip() == "").any():
        sys.exit("every row needs a source_id documented in shelf_life/DATA_SOURCES.md")
    if len(df) < MIN_ROWS or int(df["event"].sum()) < MIN_EVENTS:
        sys.exit(f"not enough data ({len(df)} rows, {int(df['event'].sum())} events; need {MIN_ROWS}/{MIN_EVENTS}). Keep the Q10 fallback.")

    # Split by source so test rows come from studies/tests the model has not seen.
    sources = sorted(df["source_id"].astype(str).unique())
    rng = np.random.default_rng(42)
    rng.shuffle(sources)
    n_test = max(1, int(round(len(sources) * args.test_frac)))
    test_sources = set(sources[:n_test])
    test = df[df["source_id"].astype(str).isin(test_sources)]
    train = df[~df["source_id"].astype(str).isin(test_sources)]

    cph = CoxPHFitter(penalizer=args.penalizer)
    cph.fit(to_features(train), duration_col="duration_h", event_col="event")

    params = {
        "features": COX_FEATURES,
        "beta": [float(cph.params_[f]) for f in COX_FEATURES],
        "means": [float(cph._norm_mean[f]) for f in COX_FEATURES],  # lifelines centres covariates
        "baselineSurvival": [[float(t), float(s)] for t, s in cph.baseline_survival_.iloc[:, 0].items()],
    }

    # Evaluate through the exact service code path.
    model = CoxModel(params, "eval")
    preds, abs_err = [], []
    for _, r in test.iterrows():
        e = Exposure(
            base_shelf_life_h=float(r.base_shelf_life_h), q10=2.0, ref_temp_c=0.0, hours_since_harvest=0.0,
            mean_temp_c=float(r.mean_temp_c), degree_minutes_above=float(r.degree_minutes_above),
            humidity_pct=None if pd.isna(r.humidity_pct) else float(r.humidity_pct),
            ethylene_ppm=None if pd.isna(r.ethylene_ppm) else float(r.ethylene_ppm),
            shock_events=int(r.shock_events), grade=None if pd.isna(r.grade) else str(r.grade).upper(),
        )
        t_med = model.predict(e).remaining_h
        preds.append(t_med)
        if int(r.event) == 1:
            abs_err.append(abs(t_med - float(r.duration_h)))

    c_index = concordance_index(test["duration_h"], preds, test["event"])
    metrics = {
        "cIndex_test": round(float(c_index), 4),
        "medianAbsErrorH_test": None if not abs_err else round(float(np.median(abs_err)), 2),
        "meanAbsErrorH_test": None if not abs_err else round(float(np.mean(abs_err)), 2),
        "nTrain": int(len(train)),
        "nTest": int(len(test)),
        "testEvents": int(test["event"].sum()),
        "testSources": sorted(test_sources),
        "penalizer": args.penalizer,
        "trainedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "cox_params.json").write_text(json.dumps(params), encoding="utf-8")
    (out / "metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    print(json.dumps(metrics, indent=2))
    if not math.isfinite(metrics["cIndex_test"]) or metrics["cIndex_test"] < 0.75:
        print("C-index below the ML-02 target (0.75): consider keeping the Q10 fallback active.")


if __name__ == "__main__":
    main()
