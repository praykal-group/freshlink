"""API contracts (Section 8) through FastAPI, with the real registry loader."""

import json
import time

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.core import images as images_mod
from app.core.state import state
from app.core.vision import FISH_CLASSES, PRODUCE_CLASSES
from app.main import app

from .helpers import constant_onnx, sha256, write_registry, yolo_output

TOKEN = "test-token-123"
H = {"X-Internal-Token": TOKEN}
URLS = ["https://s3.example/top.jpg", "https://s3.example/side.jpg", "https://s3.example/close.jpg"]


@pytest.fixture(autouse=True)
def token(monkeypatch):
    monkeypatch.setenv("ML_INTERNAL_TOKEN", TOKEN)


@pytest.fixture
def models_dir(tmp_path, monkeypatch):
    monkeypatch.setenv("MODELS_DIR", str(tmp_path))
    write_registry(tmp_path, {})
    return tmp_path


def register_vision(models_dir, name, classes, output):
    d = models_dir / name / "v1"
    d.mkdir(parents=True)
    constant_onnx(d / "model.onnx", output)
    return {"file": "model.onnx", "sha256": sha256(d / "model.onnx"), "classes": classes, "imgsz": 640, "metrics": {}}


@pytest.fixture
def fake_images(monkeypatch):
    async def fetch(urls):
        return [Image.new("RGB", (640, 640), (200, 180, 160)) for _ in urls]

    monkeypatch.setattr(images_mod, "fetch_images", fetch)


def shelf_item(**kw):
    item = {
        "batchId": "b1", "productCode": "ROHU", "category": "FISH", "grade": "A", "hoursSinceHarvest": 24,
        "meanTempC": 2, "degreeMinutesAbove": 0, "humidityPct": 92, "ethylenePpm": 0, "shockEvents": 0,
        "baseShelfLifeH": 192, "q10": 2.5, "refTempC": 2,
    }
    item.update(kw)
    return item


# ───────────── auth ─────────────

def test_every_route_needs_the_internal_token(models_dir):
    with TestClient(app) as c:
        assert c.get("/health").status_code == 401
        assert c.post("/v1/shelf-life/predict", json={"items": [shelf_item()]}).status_code == 401
        assert c.get("/health", headers={"X-Internal-Token": "wrong"}).status_code == 401
        assert c.get("/health", headers=H).status_code == 200


# ───────────── shelf life ─────────────

def test_shelf_life_uses_q10_without_a_cox_model(models_dir):
    with TestClient(app) as c:
        r = c.post("/v1/shelf-life/predict", headers=H, json={"items": [shelf_item(), shelf_item(batchId="b2", meanTempC=12)]})
    assert r.status_code == 200
    res = r.json()["results"]
    assert res[0] == {**res[0], "batchId": "b1", "method": "Q10_FALLBACK", "modelVersion": "q10-1", "remainingH": 168.0}
    assert res[1]["remainingH"] == pytest.approx(192 / 2.5 - 24, abs=0.01)


def test_shelf_life_200_items_answer_well_under_one_second(models_dir):
    items = [shelf_item(batchId=f"b{i}", meanTempC=i % 20) for i in range(200)]
    with TestClient(app) as c:
        t0 = time.perf_counter()
        r = c.post("/v1/shelf-life/predict", headers=H, json={"items": items})
        elapsed = time.perf_counter() - t0
    assert r.status_code == 200 and len(r.json()["results"]) == 200
    assert elapsed < 1.0


def test_shelf_life_validation(models_dir):
    with TestClient(app) as c:
        r = c.post("/v1/shelf-life/predict", headers=H, json={"items": [shelf_item(q10=0.5)]})
        assert r.status_code == 422 and r.json()["error"]["code"] == "VALIDATION_FAILED"
        assert c.post("/v1/shelf-life/predict", headers=H, json={"items": [shelf_item(extra=1)]}).status_code == 422
        assert c.post("/v1/shelf-life/predict", headers=H, json={"items": []}).status_code == 422


def test_shelf_life_uses_a_registered_cox_model(models_dir):
    d = models_dir / "shelf_life_cox" / "v1"
    d.mkdir(parents=True)
    from .test_shelf_life import cox_params

    (d / "model.json").write_text(json.dumps(cox_params()), encoding="utf-8")
    write_registry(models_dir, {"shelf_life_cox": {"file": "model.json", "sha256": sha256(d / "model.json"), "metrics": {"cIndex_test": 0.8}}})
    with TestClient(app) as c:
        res = c.post("/v1/shelf-life/predict", headers=H, json={"items": [shelf_item(hoursSinceHarvest=0)]}).json()["results"][0]
        models = c.get("/v1/models", headers=H).json()["models"]
    assert res["method"] == "COX" and res["modelVersion"] == "shelf_life_cox:v1"
    assert res["remainingH"] == pytest.approx(240, abs=1.0)
    assert models["shelf_life_cox"]["loaded"] is True


# ───────────── vision ─────────────

def test_vision_answers_503_when_no_model_is_registered(models_dir):
    with TestClient(app) as c:
        r = c.post("/v1/vision/grade", headers=H, json={"batchId": "b1", "category": "FISH", "imageUrls": URLS})
    assert r.status_code == 503
    assert r.json()["error"]["code"] == "MODEL_NOT_AVAILABLE"
    assert "no active version" in r.json()["error"]["details"]["reason"]


def test_vision_contract_with_a_registered_onnx_model(models_dir, fake_images):
    # Every image: one fresh item + a small bruise (4 % of the item) → grade B.
    out = yolo_output([((320, 320, 500, 500), 0, 0.92), ((200, 200, 100, 100), 1, 0.71)], nc=len(PRODUCE_CLASSES))
    write_registry(models_dir, {"vision_produce": register_vision(models_dir, "vision_produce", PRODUCE_CLASSES, out)})
    with TestClient(app) as c:
        r = c.post("/v1/vision/grade", headers=H, json={"batchId": "b1", "category": "PRODUCE", "imageUrls": URLS})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["grade"] == "B" and body["confidence"] == pytest.approx(0.71, abs=1e-3)
    assert body["modelVersion"] == "vision_produce:v1"
    assert len(body["perImage"]) == 3 and body["perImage"][0]["itemDetected"] is True
    assert body["defects"][0]["class"] == "bruise" and body["defects"][0]["areaPct"] == pytest.approx(4.0, abs=0.01)
    assert isinstance(body["latencyMs"], int)


def test_a_model_with_a_wrong_sha256_is_not_loaded(models_dir, fake_images):
    entry = register_vision(models_dir, "vision_fish", FISH_CLASSES, yolo_output([], nc=4))
    entry["sha256"] = "0" * 64
    write_registry(models_dir, {"vision_fish": entry})
    with TestClient(app) as c:
        r = c.post("/v1/vision/grade", headers=H, json={"batchId": "b1", "category": "FISH", "imageUrls": URLS})
        health = c.get("/health", headers=H).json()
    assert r.status_code == 503
    assert health["models"]["vision_fish"] == {**health["models"]["vision_fish"], "loaded": False, "reason": "sha256 mismatch; refusing to load"}
    assert "FISH" not in state.vision


def test_vision_needs_exactly_three_image_urls(models_dir):
    with TestClient(app) as c:
        r = c.post("/v1/vision/grade", headers=H, json={"batchId": "b1", "category": "FISH", "imageUrls": URLS[:2]})
    assert r.status_code == 422
