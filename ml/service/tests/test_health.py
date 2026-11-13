import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture(autouse=True)
def token(monkeypatch):
    monkeypatch.setenv("ML_INTERNAL_TOKEN", "test-token-123")


def test_health_with_token():
    with TestClient(app) as c:
        r = c.get("/health", headers={"X-Internal-Token": "test-token-123"})
    assert r.status_code == 200 and r.json()["status"] == "ok"


def test_health_without_token():
    with TestClient(app) as c:
        assert c.get("/health").status_code == 401


def test_unset_token_rejects_everything(monkeypatch):
    monkeypatch.delenv("ML_INTERNAL_TOKEN")
    with TestClient(app) as c:
        assert c.get("/health", headers={"X-Internal-Token": ""}).status_code == 401
