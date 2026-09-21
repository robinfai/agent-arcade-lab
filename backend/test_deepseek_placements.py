import json
import httpx
import pytest
from fastapi.testclient import TestClient
from backend import deepseek_server as remote

@pytest.mark.parametrize('endpoint,name',[('/v1/tool-decision','place_piece'),('/v1/land-decision','land_at_target')])
def test_remote_native_placement_contract(monkeypatch,endpoint,name):
    monkeypatch.setenv('DEEPSEEK_API_KEY','test-only')
    original=httpx.AsyncClient
    def handler(request):
        payload=json.loads(request.content)
        assert payload['tools'][0]['function']['name']==name
        assert payload['thinking']['type']=='disabled'
        return httpx.Response(200,json={'model':'deepseek-flash','choices':[{'message':{'tool_calls':[{'function':{'name':name,'arguments':json.dumps({'placement_id':'p1'})}}]}}]})
    monkeypatch.setattr(remote.httpx,'AsyncClient',lambda **kwargs:original(transport=httpx.MockTransport(handler)))
    request={'model':'jev-latest','state':{},'questions':{'move':{'type':'choice','instructions':'Return the label of the best outcome.','criteria':{'p1':{}}}}}
    r=TestClient(remote.app).post(endpoint,json=request)
    assert r.status_code==200
    assert r.json()['choice']=='p1' and r.json()['error'] is None
