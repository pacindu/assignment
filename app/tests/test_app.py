import pytest
import sys
import os

# Allow importing main from the parent directory
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from main import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


# ---------------------------------------------------------------------------
# Index endpoint
# ---------------------------------------------------------------------------

def test_index_returns_200(client):
    response = client.get("/")
    assert response.status_code == 200


def test_index_returns_service_name(client):
    data = client.get("/").get_json()
    assert data["service"] == "NTT GCC Sample API"


def test_index_returns_version(client):
    data = client.get("/").get_json()
    assert "version" in data


def test_index_returns_uptime(client):
    data = client.get("/").get_json()
    assert isinstance(data["uptime_seconds"], int)
    assert data["uptime_seconds"] >= 0


# ---------------------------------------------------------------------------
# Health check endpoint
# ---------------------------------------------------------------------------

def test_health_returns_200(client):
    response = client.get("/health")
    assert response.status_code == 200


def test_health_returns_healthy_status(client):
    data = client.get("/health").get_json()
    assert data["status"] == "healthy"


def test_health_returns_uptime(client):
    data = client.get("/health").get_json()
    assert "uptime_seconds" in data
    assert data["uptime_seconds"] >= 0


# ---------------------------------------------------------------------------
# Status endpoint
# ---------------------------------------------------------------------------

def test_status_returns_200(client):
    response = client.get("/api/status")
    assert response.status_code == 200


def test_status_returns_ok(client):
    data = client.get("/api/status").get_json()
    assert data["status"] == "ok"


# ---------------------------------------------------------------------------
# Security headers (GCC requirement)
# ---------------------------------------------------------------------------

def test_security_header_content_type_options(client):
    response = client.get("/health")
    assert response.headers["X-Content-Type-Options"] == "nosniff"


def test_security_header_frame_options(client):
    response = client.get("/health")
    assert response.headers["X-Frame-Options"] == "DENY"


def test_security_header_xss_protection(client):
    response = client.get("/health")
    assert response.headers["X-XSS-Protection"] == "1; mode=block"


def test_security_header_hsts(client):
    response = client.get("/health")
    assert "max-age=31536000" in response.headers["Strict-Transport-Security"]


def test_security_header_csp(client):
    response = client.get("/health")
    assert "Content-Security-Policy" in response.headers


def test_security_header_cache_control(client):
    response = client.get("/health")
    assert response.headers["Cache-Control"] == "no-store"


# ---------------------------------------------------------------------------
# Negative tests
# ---------------------------------------------------------------------------

def test_unknown_route_returns_404(client):
    response = client.get("/does-not-exist")
    assert response.status_code == 404
