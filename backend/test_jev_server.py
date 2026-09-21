import httpx
import pytest
from fastapi.testclient import TestClient
from backend import jev_server

REQUEST = {'model': 'local', 'state': 'game state', 'questions': {'move': {
    'type': 'choice', 'instructions': 'Choose', 'criteria': {'left': None, 'right': None}}}}
ANSWER = {'model': 'jev-test', 'answers': {'move': {'type': 'choice', 'choice': 'left',
    'probabilities': {'left': 0.8, 'right': 0.2}, 'confidence': 0.6}}, 'usage': {}}


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv('JEV_API_KEY', 'test-secret')
    return TestClient(jev_server.app)


def mock_upstream(monkeypatch, *, status=200, data=ANSWER, error=None):
    async def post(self, url, **kwargs):
        assert url == jev_server.UPSTREAM
        assert kwargs['headers']['Authorization'] == 'Bearer test-secret'
        assert kwargs['json'] == {**REQUEST, 'model': 'jev-latest'}
        if error:
            raise error
        return httpx.Response(status, json=data)
    monkeypatch.setattr(httpx.AsyncClient, 'post', post)


@pytest.mark.parametrize('endpoint', ['tool', 'land', 'snake'])
def test_adapter(client, monkeypatch, endpoint):
    mock_upstream(monkeypatch)
    r = client.post(f'/v1/{endpoint}-decision', json=REQUEST)
    assert r.status_code == 200
    assert r.json()['choice'] == 'left'
    assert r.json()['model'] == 'jev-test'
    assert r.json()['probabilities'] == ANSWER['answers']['move']['probabilities']
    assert float(r.headers['X-Inference-Ms']) >= 0


def test_missing_key(client, monkeypatch):
    monkeypatch.delenv('JEV_API_KEY')
    assert not client.get('/health').json()['ready']
    assert client.post('/v1/tool-decision', json=REQUEST).status_code == 503


@pytest.mark.parametrize('status,data,error,expected', [
    (401, {'detail': 'test-secret'}, None, 502),
    (429, {}, None, 502),
    (200, {'answers': {'move': {'choice': 'illegal'}}}, None, 502),
    (200, [], None, 502),
    (200, {}, httpx.ReadTimeout('test-secret'), 504),
])
def test_fail_closed(client, monkeypatch, status, data, error, expected):
    mock_upstream(monkeypatch, status=status, data=data, error=error)
    r = client.post('/v1/snake-decision', json=REQUEST)
    assert r.status_code == expected
    assert 'test-secret' not in r.text


def test_invalid_request(client):
    assert client.post('/v1/tool-decision', json={}).status_code == 422
    assert 'test-secret' not in client.get('/health').text


def test_cors(client):
    r = client.options('/v1/snake-decision', headers={
        'Origin': 'http://127.0.0.1:18787', 'Access-Control-Request-Method': 'POST',
        'Access-Control-Request-Headers': 'content-type'})
    assert r.status_code == 200
