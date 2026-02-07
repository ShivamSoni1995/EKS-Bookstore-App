import pytest
from main import app

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_health_check(client):
    """Test health check endpoint"""
    response = client.get('/api/health')
    assert response.status_code == 200
    assert response.json['status'] == 'healthy'

def test_get_products(client):
    """Test products endpoint"""
    response = client.get('/api/products')
    assert response.status_code == 200
    assert isinstance(response.json, list)

def test_get_categories(client):
    """Test categories endpoint"""
    response = client.get('/api/categories')
    assert response.status_code == 200
    assert isinstance(response.json, list)