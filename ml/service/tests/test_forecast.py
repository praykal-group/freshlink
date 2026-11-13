import json
from datetime import date, timedelta

import httpx
import numpy as np
import pytest
from fastapi.testclient import TestClient

from app.core.forecast import simulate, weather
from app.core.forecast.calendar import is_festival_window
from app.core.forecast.features import LGBM_FEATURES, WINDOW, future_days, lgbm_rows, lstm_window, mape, scale_of, seasonal_naive
from app.main import app

from .helpers import sha256

H = {"X-Internal-Token": "test-token-123"}
START = date(2026, 11, 20)


@pytest.fixture(autouse=True)
def env(monkeypatch, tmp_path):
    monkeypatch.setenv("ML_INTERNAL_TOKEN", "test-token-123")
    monkeypatch.setenv("MODELS_DIR", str(tmp_path))
    monkeypatch.delenv("OPEN_METEO_URL", raising=False)
    (tmp_path / "registry.json").write_text(json.dumps({"models": {}}), encoding="utf-8")
    return tmp_path


# ───────────── simulator, calendar, features ─────────────

def test_simulator_is_deterministic_and_positive():
    a = simulate.series("DC-1", "TOMATO", date(2025, 1, 1), date(2025, 3, 31))
    b = simulate.series("DC-1", "TOMATO", date(2025, 2, 1), date(2025, 2, 10))
    assert [d.kg for d in a[31:41]] == [d.kg for d in b]
    assert all(d.kg > 0 and d.price > 0 for d in a)
    assert simulate.series("DC-2", "TOMATO", date(2025, 2, 1), date(2025, 2, 1))[0].kg != b[0].kg


def test_festival_window_and_uplift():
    assert is_festival_window(date(2026, 11, 8)) and is_festival_window(date(2026, 11, 5))
    assert not is_festival_window(date(2026, 11, 9))
    s = simulate.series("DC-1", "ROHU", date(2025, 1, 1), date(2025, 12, 31))
    fest = np.mean([d.kg for d in s if d.festival])
    normal = np.mean([d.kg for d in s if not d.festival])
    assert fest > 1.2 * normal


def test_feature_shapes_and_minimum_history():
    hist = simulate.series("DC-1", "MANGO", START - timedelta(days=60), START - timedelta(days=1))
    fut = future_days(hist, 7)
    assert [f.date for f in fut] == [START + timedelta(days=i) for i in range(7)]
    assert lgbm_rows(hist, fut).shape == (7, len(LGBM_FEATURES))
    assert lstm_window(hist).shape == (1, WINDOW, 7)
    with pytest.raises(ValueError):
        lgbm_rows(hist[:10], fut)


def test_seasonal_naive_is_same_weekday_mean():
    hist = simulate.series("DC-1", "ONION", START - timedelta(days=60), START - timedelta(days=1))
    fut = future_days(hist, 1)
    by = {d.date: d.kg for d in hist}
    expected = np.mean([by[START - timedelta(days=7 * k)] for k in range(1, 5)])
    assert seasonal_naive(hist, fut)[0] == pytest.approx(expected)


def test_mape():
    assert mape([100, 200], [110, 180]) == pytest.approx(10.0)
    assert mape([0, 100], [5, 90]) == pytest.approx(10.0)  # zero actuals skipped


def test_open_meteo_parses_daily_and_falls_back_on_errors(monkeypatch):
    monkeypatch.setenv("OPEN_METEO_URL", "https://api.open-meteo.com")

    def ok(req):
        return httpx.Response(200, json={"daily": {"precipitation_sum": [0.0, 12.5], "temperature_2m_mean": [26.1, 24.0]}})

    got = weather.fetch_daily(19.87, 75.34, START, START + timedelta(days=1), httpx.Client(transport=httpx.MockTransport(ok)))
    assert got == [(0.0, 26.1), (12.5, 24.0)]
    bad = httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(500)))
    assert weather.fetch_daily(19.87, 75.34, START, START + timedelta(days=1), bad) is None


# ───────────── API ─────────────

def run(c, **body):
    payload = {"siteIds": ["DC-1", "DC-2"], "productIds": ["P1", "P2", "P3"], "startDate": START.isoformat(), **body}
    return c.post("/v1/forecast/run", headers=H, json=payload)


def test_forecast_without_a_model_uses_seasonal_naive():
    with TestClient(app) as c:
        r = run(c)
    assert r.status_code == 200, r.text
    b = r.json()
    assert b["method"] == "SEASONAL_NAIVE" and b["modelVersion"] == "seasonal-naive-1"
    assert len(b["rows"]) == 2 * 3 * 7
    assert {row["date"] for row in b["rows"]} == {(START + timedelta(days=i)).isoformat() for i in range(7)}
    assert all(row["lowerKg"] <= row["predictedKg"] <= row["upperKg"] for row in b["rows"])
    assert all(row["historySource"] == "SIMULATED" for row in b["rows"])


def test_forecast_uses_provided_history_when_30_days_are_complete():
    hist = [{"siteId": "DC-1", "productId": "P1", "date": (START - timedelta(days=k)).isoformat(), "kg": 500.0} for k in range(1, 31)]
    partial = [{"siteId": "DC-1", "productId": "P2", "date": (START - timedelta(days=k)).isoformat(), "kg": 10.0} for k in range(1, 20)]
    with TestClient(app) as c:
        rows = run(c, history=hist + partial).json()["rows"]
    src = {(r["siteId"], r["productId"]): r["historySource"] for r in rows}
    assert src[("DC-1", "P1")] == "PROVIDED" and src[("DC-1", "P2")] == "SIMULATED"
    p1 = [r["predictedKg"] for r in rows if r["productId"] == "P1" and r["siteId"] == "DC-1"]
    assert p1 == pytest.approx([500.0] * 7)  # flat history → flat naive forecast


def test_forecast_validation():
    with TestClient(app) as c:
        assert run(c, horizonDays=8).status_code == 422
        too_many = c.post("/v1/forecast/run", headers=H, json={"siteIds": [f"s{i}" for i in range(30)], "productIds": [f"p{i}" for i in range(20)], "startDate": START.isoformat()})
    assert too_many.status_code == 422 and too_many.json()["error"]["code"] == "TOO_MANY_SERIES"


def register_tiny_lgbm(models_dir, corrupt=False):
    """A small but real LightGBM model trained on simulated data, registered as a multi-file model."""
    import lightgbm as lgb

    X, y = [], []
    for p in ("A", "B"):
        days = simulate.series("DC-9", p, date(2025, 1, 1), date(2025, 6, 30))
        for i in range(60, len(days) - 7, 3):
            hist = days[i - 58 : i]
            fut = future_days(hist, 7)
            X.append(lgbm_rows(hist, fut))
            y.append(np.array([d.kg for d in days[i : i + 7]]) / scale_of(hist))
    booster = lgb.train({"objective": "l1", "verbose": -1, "num_leaves": 15}, lgb.Dataset(np.concatenate(X), np.concatenate(y)), 40)
    d = models_dir / "forecast" / "v1"
    d.mkdir(parents=True)
    booster.save_model(str(d / "lgbm.txt"))
    (d / "meta.json").write_text(json.dumps({"lstmWeight": 0.0, "intervalPct": 0.15}), encoding="utf-8")
    files = {"lgbm.txt": sha256(d / "lgbm.txt"), "meta.json": sha256(d / "meta.json")}
    if corrupt:
        files["lgbm.txt"] = "0" * 64
    reg = {"models": {"forecast": {"active": "v1", "versions": {"v1": {"files": files, "metrics": {"mapeTest": 9.9}}}}}}
    (models_dir / "registry.json").write_text(json.dumps(reg), encoding="utf-8")


def test_forecast_uses_a_registered_lightgbm_model(env):
    register_tiny_lgbm(env)
    with TestClient(app) as c:
        b = run(c).json()
        models = c.get("/v1/models", headers=H).json()["models"]
    assert b["method"] == "LIGHTGBM" and b["modelVersion"] == "forecast:v1"
    assert models["forecast"]["loaded"] is True
    row = b["rows"][0]
    assert row["lowerKg"] == pytest.approx(row["predictedKg"] * 0.85, rel=1e-3)


def test_forecast_model_with_a_bad_hash_is_not_loaded(env):
    register_tiny_lgbm(env, corrupt=True)
    with TestClient(app) as c:
        b = run(c).json()
        models = c.get("/v1/models", headers=H).json()["models"]
    assert b["method"] == "SEASONAL_NAIVE"
    assert models["forecast"]["reason"] == "sha256 mismatch; refusing to load"
