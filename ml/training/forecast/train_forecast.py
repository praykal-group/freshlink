"""Train the demand forecast ensemble (Section 8, ML-03) and measure MAPE on a time-based split.

    python ml/training/forecast/train_forecast.py --out ml/training/forecast/out [--sales sales.csv] [--prices agmarknet.csv]

Data: simulated sales from the service's simulator (Section 2) unless --sales is given
(columns site_id,product_id,date,kg[,price]). --prices replaces the simulated mandi price with an
Agmarknet daily modal price series (see agmarknet.py). Split by forecast origin: last 3 months =
test, the 3 months before = validation, the rest = train.

Outputs (register with scripts/register_model.py forecast <version> <out dir> --activate):
  lgbm.txt, lstm.onnx, meta.json {lstmWeight, intervalPct, horizon, window}, metrics.json
"""

import argparse
import json
import sys
import time
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "ml" / "service"))

from app.core.forecast import simulate  # noqa: E402
from app.core.forecast.calendar import is_festival_window  # noqa: E402
from app.core.forecast.features import (  # noqa: E402
    HORIZON, WINDOW, Future, lgbm_rows, lstm_window, mape, scale_of, seasonal_naive,
)
from app.core.forecast.simulate import Day  # noqa: E402

START, END = date(2023, 1, 1), date(2025, 12, 31)
N_SITES, N_PRODUCTS = 6, 10


def load_series(args):
    if args.sales:
        import pandas as pd

        df = pd.read_csv(args.sales, parse_dates=["date"])
        out = {}
        for (s, p), g in df.sort_values("date").groupby(["site_id", "product_id"]):
            out[(str(s), str(p))] = [
                Day(r.date.date(), float(r.kg), float(getattr(r, "price", 0) or 0) or 1.0, *simulate.weather(r.date.date()), is_festival_window(r.date.date()))
                for r in g.itertuples()
            ]
        return out, "provided CSV"
    sites = [f"site-{i}" for i in range(1, N_SITES + 1)]
    products = [f"product-{j}" for j in range(1, N_PRODUCTS + 1)]
    return {(s, p): simulate.series(s, p, START, END) for s in sites for p in products}, "simulated (Section 2)"


def apply_prices(series, path):
    from agmarknet import load_daily_prices  # noqa: E402

    prices = load_daily_prices(path)
    for key, days in series.items():
        for d in days:
            if d.date in prices:
                d.price = prices[d.date]


def samples(series, origins_from, origins_to, step=1):
    """(series key, hist, future days, actual kg) for every origin d0 in [from, to]."""
    out = []
    for key, days in series.items():
        idx = {d.date: i for i, d in enumerate(days)}
        d0 = origins_from
        while d0 <= origins_to:
            i = idx.get(d0)
            if i is not None and i + 1 >= WINDOW and i + HORIZON < len(days):
                hist = days[i + 1 - WINDOW - 28 : i + 1] if i + 1 >= WINDOW + 28 else days[: i + 1]
                fut_days = days[i + 1 : i + 1 + HORIZON]
                fut = [Future(f.date, days[i].price, f.rain_mm, f.temp_c, f.festival) for f in fut_days]
                out.append((key, hist, fut, np.array([f.kg for f in fut_days])))
            d0 += timedelta(days=step)
    return out


def lgbm_xy(sams):
    X = np.concatenate([lgbm_rows(h, f) for _, h, f, _ in sams])
    y = np.concatenate([a / scale_of(h) for _, h, _, a in sams])
    return X, y


def train_lstm(train, val, epochs, seed):
    import torch
    from torch import nn

    torch.manual_seed(seed)

    class Net(nn.Module):
        def __init__(self, f):
            super().__init__()
            self.l1 = nn.LSTM(f, 64, batch_first=True)
            self.l2 = nn.LSTM(64, 32, batch_first=True)
            self.drop = nn.Dropout(0.2)
            self.head = nn.Linear(32, HORIZON)

        def forward(self, x):
            x, _ = self.l1(x)
            x, _ = self.l2(self.drop(x))
            return self.head(self.drop(x[:, -1, :]))

    def tensors(sams):
        X = np.concatenate([lstm_window(h) for _, h, _, _ in sams])
        Y = np.stack([a / scale_of(h) for _, h, _, a in sams]).astype(np.float32)
        return torch.from_numpy(X), torch.from_numpy(Y)

    Xt, Yt = tensors(train)
    Xv, Yv = tensors(val)
    net = Net(Xt.shape[2])
    opt = torch.optim.Adam(net.parameters(), lr=1e-3)
    loss_fn = nn.L1Loss()
    best, best_state, stale = float("inf"), None, 0
    for ep in range(epochs):
        net.train()
        perm = torch.randperm(len(Xt))
        for k in range(0, len(Xt), 256):
            b = perm[k : k + 256]
            opt.zero_grad()
            loss = loss_fn(net(Xt[b]), Yt[b])
            loss.backward()
            opt.step()
        net.eval()
        with torch.no_grad():
            v = loss_fn(net(Xv), Yv).item()
        print(f"  lstm epoch {ep + 1}: val L1 {v:.4f}")
        if v < best - 1e-4:
            best, best_state, stale = v, {k: t.clone() for k, t in net.state_dict().items()}, 0
        else:
            stale += 1
            if stale >= 3:
                break
    net.load_state_dict(best_state)
    net.eval()
    return net


def export_lstm(net, path):
    import torch

    dummy = torch.zeros(1, WINDOW, 7)
    torch.onnx.export(net, dummy, str(path), input_names=["window"], output_names=["kg_scaled"],
                      dynamic_axes={"window": {0: "batch"}, "kg_scaled": {0: "batch"}}, opset_version=13, dynamo=False)


def lstm_predict(path, sams):
    import onnxruntime as ort

    sess = ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])
    X = np.concatenate([lstm_window(h) for _, h, _, _ in sams])
    return sess.run(None, {"window": X})[0]


def main():
    import lightgbm as lgb

    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--sales")
    ap.add_argument("--prices")
    ap.add_argument("--epochs", type=int, default=15)
    ap.add_argument("--no-lstm", action="store_true")
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()
    t_start = time.time()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    series, source = load_series(args)
    if args.prices:
        sys.path.insert(0, str(HERE))
        apply_prices(series, args.prices)
    last = max(d.date for days in series.values() for d in days)
    test_from = last - timedelta(days=90 + HORIZON)
    val_from = test_from - timedelta(days=90)
    first = min(d.date for days in series.values() for d in days) + timedelta(days=WINDOW + 28)
    train = samples(series, first, val_from - timedelta(days=HORIZON + 1), step=2)
    val = samples(series, val_from, test_from - timedelta(days=HORIZON + 1))
    test = samples(series, test_from, last - timedelta(days=HORIZON))
    print(f"series={len(series)} train={len(train)} val={len(val)} test={len(test)} origins")

    Xtr, ytr = lgbm_xy(train)
    Xva, yva = lgbm_xy(val)
    booster = lgb.train(
        {"objective": "l1", "learning_rate": 0.05, "num_leaves": 31, "min_data_in_leaf": 50, "feature_fraction": 0.9, "seed": args.seed, "verbose": -1},
        lgb.Dataset(Xtr, ytr),
        num_boost_round=1000,
        valid_sets=[lgb.Dataset(Xva, yva)],
        callbacks=[lgb.early_stopping(50, verbose=False)],
    )
    booster.save_model(str(out / "lgbm.txt"))

    def lgbm_pred(sams):
        return [booster.predict(lgbm_rows(h, f)) * scale_of(h) for _, h, f, _ in sams]

    val_lgbm, test_lgbm = lgbm_pred(val), lgbm_pred(test)
    w, interval = 0.0, 0.2
    val_lstm = test_lstm = None
    if not args.no_lstm:
        net = train_lstm(train, val, args.epochs, args.seed)
        export_lstm(net, out / "lstm.onnx")
        val_lstm = [p * scale_of(h) for p, (_, h, _, _) in zip(lstm_predict(out / "lstm.onnx", val), val)]
        test_lstm = [p * scale_of(h) for p, (_, h, _, _) in zip(lstm_predict(out / "lstm.onnx", test), test)]
        # Ensemble weight chosen on validation only.
        actual_val = [a for *_, a in val]
        grid = [round(x, 1) for x in np.linspace(0, 1, 11)]
        scores = {g: mape(np.concatenate(actual_val), np.concatenate([g * l + (1 - g) * b for l, b in zip(val_lstm, val_lgbm)])) for g in grid}
        w = min(scores, key=scores.get)

    def ens(lstm, lgbm):
        return [w * l + (1 - w) * b for l, b in zip(lstm, lgbm)] if lstm is not None else lgbm

    val_ens = ens(val_lstm, val_lgbm)
    rel = np.abs(np.concatenate([a for *_, a in val]) - np.concatenate(val_ens)) / np.maximum(np.concatenate(val_ens), 1e-6)
    interval = float(np.quantile(rel, 0.8))

    actual = np.concatenate([a for *_, a in test])
    test_ens = np.concatenate(ens(test_lstm, test_lgbm))
    naive = np.concatenate([seasonal_naive(h, f) for _, h, f, _ in test])
    lo, hi = test_ens * (1 - interval), test_ens * (1 + interval)
    metrics = {
        "dataSource": source,
        "split": {"testOrigins": f"{test_from}..{last - timedelta(days=HORIZON)}", "valOrigins": f"{val_from}..{test_from - timedelta(days=HORIZON + 1)}"},
        "series": len(series),
        "testForecasts": int(actual.size),
        "mapeTest": {
            "ensemble": round(mape(actual, test_ens), 2),
            "lightgbm": round(mape(actual, np.concatenate(test_lgbm)), 2),
            "lstm": None if test_lstm is None else round(mape(actual, np.concatenate(test_lstm)), 2),
            "seasonalNaive": round(mape(actual, naive), 2),
        },
        "lstmWeight": w,
        "intervalPct": round(interval, 4),
        "intervalCoverageTest": round(float(np.mean((actual >= lo) & (actual <= hi))), 4),
        "lgbmRounds": booster.best_iteration,
        "trainSeconds": round(time.time() - t_start, 1),
        "trainedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    meta = {"lstmWeight": w, "intervalPct": round(interval, 4), "horizon": HORIZON, "window": WINDOW, "dataSource": source}
    (out / "meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    (out / "metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
