import pytest
import json
import asyncio
from .app import create_app

@pytest.fixture
def client():
    """Create test client"""
    app = create_app()
    app.config['TESTING'] = True
    
    with app.test_client() as client:
        with app.app_context():
            # Clear users before each test
            asyncio.run(app.user_repository.clear())
            yield client

def test_health_check(client):
    """Test health check endpoint"""
    response = client.get('/health')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert data['status'] == 'healthy'

def test_version_check(client):
    """Test version endpoint"""
    response = client.get('/version')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert data['version'] == 'layered-architecture'

def test_create_user(client):
    """Test user creation"""
    user_data = {
        'name': 'Test User',
        'email': 'test@example.com'
    }
    
    response = client.post('/users', 
                          data=json.dumps(user_data),
                          content_type='application/json')
    
    assert response.status_code == 201
    data = json.loads(response.data)
    assert data['name'] == 'Test User'
    assert data['email'] == 'test@example.com'
    assert 'id' in data
