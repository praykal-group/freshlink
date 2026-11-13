import math

import pytest

from app.core.shelf_life import COX_FEATURES, CoxModel, Exposure, predict, predict_q10, q10_total_h

from .helpers import SEED_PRODUCTS


def exp_for(base, q10, lo, hi, *, temp=None, elapsed=0.0, grade=None):
    ref = (lo + hi) / 2
    return Exposure(base, q10, ref, elapsed, ref if temp is None else temp, grade=grade)


# ───────────── Q10 fallback (ML-02: always returns a value) ─────────────

@pytest.mark.parametrize("code,base,q10,lo,hi", SEED_PRODUCTS)
def test_q10_returns_a_non_negative_value_for_every_product(code, base, q10, lo, hi):
    for temp in (-5, 0, 4, 10, 20, 35, 50):
        for elapsed in (0, 12, 100, 5000):
            p = predict_q10(exp_for(base, q10, lo, hi, temp=temp, elapsed=elapsed))
            assert p.remaining_h >= 0 and math.isfinite(p.remaining_h), (code, temp, elapsed)
            assert p.method == "Q10_FALLBACK"
            assert p.curve and all(0 <= c["p"] <= 1 for c in p.curve)


def test_q10_at_reference_temperature_is_base_minus_elapsed():
    assert predict_q10(Exposure(192, 2.5, 2, 24, 2)).remaining_h == pytest.approx(168)


def test_q10_ten_degrees_warmer_divides_by_q10():
    assert q10_total_h(Exposure(192, 2.5, 2, 0, 12)) == pytest.approx(192 / 2.5)


def test_q10_warmer_means_shorter():
    cold = predict_q10(Exposure(240, 2.5, 2, 0, 2)).remaining_h
    warm = predict_q10(Exposure(240, 2.5, 2, 0, 8)).remaining_h
    assert warm < cold


def test_q10_curve_is_half_at_total_life():
    p = predict_q10(Exposure(100, 2, 10, 0, 10))
    mid = [c for c in p.curve if c["h"] == pytest.approx(100)]
    assert mid and mid[0]["p"] == pytest.approx(0.5, abs=1e-3)


# ───────────── Cox from exported parameters ─────────────

def cox_params(beta=None):
    ts = [float(t) for t in range(0, 401, 20)]
    s0 = [math.exp(-((t / 240) ** 3) * math.log(2)) for t in ts]  # baseline median exactly 240 h
    return {
        "features": COX_FEATURES,
        "beta": beta or [0.0] * len(COX_FEATURES),
        "means": [math.log(192), 2.0, 0.0, 90.0, 0.0, 0.0, 0.0, 0.0],
        "baselineSurvival": [[t, s] for t, s in zip(ts, s0)],
    }


def at_means(**kw):
    base = dict(base_shelf_life_h=192, q10=2.5, ref_temp_c=2, hours_since_harvest=0, mean_temp_c=2.0,
                degree_minutes_above=0, humidity_pct=90, ethylene_ppm=0, shock_events=0, grade=None)
    base.update(kw)
    return Exposure(**base)


def test_cox_at_mean_covariates_gives_the_baseline_median():
    p = CoxModel(cox_params(), "t").predict(at_means())
    assert p.method == "COX" and p.remaining_h == pytest.approx(240, abs=1.0)


def test_cox_subtracts_elapsed_and_clamps():
    m = CoxModel(cox_params(), "t")
    assert m.predict(at_means(hours_since_harvest=40)).remaining_h == pytest.approx(200, abs=1.0)
    assert m.predict(at_means(hours_since_harvest=1000)).remaining_h == 0


def test_cox_positive_temperature_coefficient_shortens_life():
    beta = [0.0] * len(COX_FEATURES)
    beta[COX_FEATURES.index("mean_temp_c")] = 0.3
    m = CoxModel(cox_params(beta), "t")
    assert m.predict(at_means(mean_temp_c=8)).remaining_h < m.predict(at_means(mean_temp_c=2)).remaining_h


def test_cox_flags_censored_when_survival_never_reaches_half():
    beta = [0.0] * len(COX_FEATURES)
    beta[COX_FEATURES.index("mean_temp_c")] = 1.0
    p = CoxModel(cox_params(beta), "t").predict(at_means(mean_temp_c=-10))  # very protective
    assert p.censored is True and p.remaining_h == pytest.approx(400)


def test_cox_rejects_a_parameter_file_with_other_features():
    bad = cox_params()
    bad["features"] = ["mean_temp_c"]
    with pytest.raises(ValueError):
        CoxModel(bad, "t")


def test_predict_uses_q10_when_no_cox_model():
    assert predict(at_means(), None).method == "Q10_FALLBACK"
