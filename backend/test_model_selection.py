from types import SimpleNamespace
import pytest
from fastapi import HTTPException
from backend import server


def test_local_switch_unloads_before_loading_and_uses_pinned_revision(monkeypatch):
    events=[]
    mx=SimpleNamespace(synchronize=lambda:events.append('sync'),clear_cache=lambda:events.append('clear'))
    monkeypatch.setattr(server,'engine',SimpleNamespace(mx=mx))
    monkeypatch.setattr(server,'MODEL','mlx-community/Qwen3.5-0.8B-4bit')
    monkeypatch.setattr(server,'MODEL_ALIAS','qwen3.5-0.8b')
    def create(model,revision):
        assert server.engine is None
        assert events==['sync','clear']
        assert revision==server.LOCAL_MODELS[model]
        events.append('load')
        return SimpleNamespace(load_ms=1)
    monkeypatch.setattr(server,'Engine',create)
    target='mlx-community/Qwen3.5-4B-4bit'
    assert server.load_model({'model':target})['model']==target
    assert server.load_model({'model':target})['ready']
    assert events==['sync','clear','load']


def test_unknown_model_does_not_change_engine():
    old=server.engine
    with pytest.raises(HTTPException) as error: server.load_model({'model':'unknown'})
    assert error.value.status_code==400
    assert server.engine is old


def test_failed_load_is_not_reported_ready(monkeypatch):
    monkeypatch.setattr(server,'engine',None)
    monkeypatch.setattr(server,'MODEL',server.MODEL)
    monkeypatch.setattr(server,'MODEL_ALIAS',server.MODEL_ALIAS)
    def fail(**kwargs): raise RuntimeError('failure')
    monkeypatch.setattr(server,'Engine',fail)
    with pytest.raises(HTTPException):server.load_model({'model':'mlx-community/Qwen3.5-4B-4bit'})
    assert not server.health()['ready']


def test_unload_reports_no_model_without_deleting_config(monkeypatch):
    events=[]
    mx=SimpleNamespace(synchronize=lambda:events.append('sync'),clear_cache=lambda:events.append('clear'))
    monkeypatch.setattr(server,'engine',SimpleNamespace(mx=mx))
    previous=server.MODEL
    assert server.unload_model()['unloaded']
    assert not server.health()['ready']
    assert server.MODEL==previous
    assert server.memory()['active_mib']==0
    assert events==['sync','clear']


def test_snake_loads_required_model_before_inference_atomically(monkeypatch):
    from backend import tool_call
    import threading
    events=[]
    monkeypatch.setattr(server,'MODEL','mlx-community/Qwen3.5-4B-4bit')
    def load(body):
        # Nested acquisition matches the real loader's locking behavior.
        with server.lock:
            server.MODEL=body['model']
            events.append('load')
    def infer(body,name):
        acquired=[]
        def other_request():
            got=server.lock.acquire(blocking=False)
            acquired.append(got)
            if got: server.lock.release()
        thread=threading.Thread(target=other_request)
        thread.start();thread.join(timeout=2)
        assert acquired==[False]
        assert server.MODEL=='mlx-community/Qwen3.5-0.8B-4bit'
        assert name=='snake_move'
        events.append('infer')
        return {'model':server.MODEL}
    monkeypatch.setattr(server,'load_model',load)
    monkeypatch.setattr(tool_call,'placement_decision',infer)
    assert tool_call.snake_decision({})['model'].endswith('0.8B-4bit')
    assert events==['load','infer']


def test_snake_load_failure_does_not_infer(monkeypatch):
    from backend import tool_call
    def fail(body): raise HTTPException(503,'load failed')
    def unexpected(*args): pytest.fail('must not infer after load failure')
    monkeypatch.setattr(server,'load_model',fail)
    monkeypatch.setattr(tool_call,'placement_decision',unexpected)
    with pytest.raises(HTTPException) as exc: tool_call.snake_decision({})
    assert exc.value.status_code==503
