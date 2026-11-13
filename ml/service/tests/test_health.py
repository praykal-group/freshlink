import os

os.environ["ML_INTERNAL_TOKEN"] = "test-token-123"

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402

client = TestClient(app)


def test_health_with_token():
    r = client.get("/health", headers={"X-Internal-Token": "test-token-123"})
    assert r.status_code == 200


def test_health_without_token():
    assert client.get("/health").status_code == 401
