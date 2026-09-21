import pytest
from backend.tool_call import parse_call

VALID='<tool_call>\n<function=place_piece>\n<parameter=placement_id>\nr0x0\n</parameter>\n</function>\n</tool_call>'
def test_native_call():
    assert parse_call(VALID,{'r0x0':{}})=='r0x0'
@pytest.mark.parametrize('text',[VALID+VALID,VALID.replace('place_piece','other'),VALID.replace('r0x0','r9x9'),VALID.replace('</tool_call>',''),'r0x0',VALID.replace('placement_id','column')])
def test_rejects_invalid_calls(text):
    with pytest.raises(ValueError): parse_call(text,{'r0x0':{}})


def test_direct_land_tool_name_is_strict():
    from backend.tool_call import parse_call
    text = '<tool_call><function=land_at_target><parameter=placement_id>p1</parameter></function></tool_call>'
    assert parse_call(text, {'p1': {}}, 'land_at_target') == 'p1'
    import pytest
    with pytest.raises(ValueError):
        parse_call(text, {'p1': {}})
