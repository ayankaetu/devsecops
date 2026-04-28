import pytest
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app.app import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


def test_index(client):
    """Test root endpoint returns OK status."""
    response = client.get("/")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "ok"


def test_health(client):
    """Test health endpoint."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "healthy"


def test_version(client):
    """Test version endpoint."""
    response = client.get("/api/version")
    assert response.status_code == 200
    data = response.get_json()
    assert "version" in data


def test_no_hardcoded_credentials():
    """Verify that no hardcoded passwords exist in app source."""
    import re
    with open(os.path.join(os.path.dirname(__file__), "../app/app.py")) as f:
        content = f.read()
    # Should not find plain hardcoded password assignments
    pattern = r'(?i)(password|secret|token)\s*=\s*["\'][^"\']{4,}["\']'
    matches = re.findall(pattern, content)
    assert len(matches) == 0, f"Hardcoded credentials found: {matches}"
