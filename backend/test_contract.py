import pytest
from backend.server import validate, answer

def test_types_and_probability_math():
    qs={'c':{'type':'choice','instructions':'pick','criteria':{'a':None,'b':{'details':'B'}}},'s':{'type':'score','instructions':'rate','criteria':['low','high']},'n':{'type':'noul','instructions':'yes?'}}
    validate({'model':'jev-latest','state':{},'questions':qs})
    assert answer(qs['c'],['a','b'],[.25,.75])['choice']=='b'
    assert answer(qs['s'],['0','1'],[.25,.75])['score']==.75
    assert answer(qs['n'],['true','false'],[.25,.75])=={'type':'noul','noul':.25}
    assert answer(qs['c'],['a','b'],[.5,.5])['confidence']==0

@pytest.mark.parametrize('question',[
 {'type':'score','instructions':'x','criteria':['one']},
 {'type':'choice','instructions':'x','criteria':{}},
 {'type':'other','instructions':'x'},
 {'type':'noul','instructions':'x','criteria':{'wrong':'yes'}},
])
def test_rejects_bad_questions(question):
    with pytest.raises(ValueError):validate({'model':'jev-latest','state':'x','questions':{'q':question}})
