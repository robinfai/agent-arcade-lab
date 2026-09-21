"""Weight-free contract checks; run with Kev's independent Python environment."""
import json
import unittest
from types import SimpleNamespace
from unittest.mock import patch
from fastapi import HTTPException
from backend import kev_server as bridge

class AdapterTests(unittest.TestCase):
    def body(self):
        return {'model':'jev-latest','state':{},'questions':{'move':{'type':'choice','instructions':'Choose','criteria':{'a':{},'b':{}}}}}

    def test_native_choice_and_probabilities_are_preserved(self):
        native={'model':'kev-latest','answers':{'move':{'type':'choice','choice':'b','probabilities':{'a':0.25,'b':0.75},'confidence':0.5}},'usage':{'input_tokens':10,'output_tokens':7},'latency_ms':12.3}
        model=SimpleNamespace(encode=lambda *a,**kw: self.assertTrue(kw['strict']))
        with patch.dict(bridge.serve.STATE,{'model':model,'tok':None}),patch.object(bridge.serve,'systemone',return_value=native):
            response=bridge.decide(self.body()); result=json.loads(response.body)
        self.assertEqual(result['choice'],'b')
        self.assertEqual(result['probabilities'],native['answers']['move']['probabilities'])
        self.assertEqual(result['model'],'jaredpalmer/kev-4b')
        self.assertEqual(result['generated_tokens'],0)

    def test_overlong_input_is_rejected_before_inference(self):
        def reject(*a,**kw):raise ValueError('branch too long')
        with patch.dict(bridge.serve.STATE,{'model':SimpleNamespace(encode=reject),'tok':None}),patch.object(bridge.serve,'systemone') as infer:
            with self.assertRaises(HTTPException) as e:bridge.decide(self.body())
            self.assertEqual(e.exception.status_code,422)
            infer.assert_not_called()

    def test_invalid_choices_are_rejected(self):
        body=self.body();body['questions']['move']['criteria']={}
        with self.assertRaises(HTTPException) as e:bridge.decide(body)
        self.assertEqual(e.exception.status_code,422)

if __name__=='__main__': unittest.main()
