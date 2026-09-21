import json
import pytest
from backend.tool_call import parse_turn

def call(actions):
    return '<tool_call><function=play_turn><parameter=actions>'+json.dumps(actions)+'</parameter></function></tool_call>'

def test_sequence_order():
    assert parse_turn(call(['left','rotate','down'])) == ['left','rotate','down']

@pytest.mark.parametrize('actions',[[],['down']*9,['drop'],[1],{'action':'left'}])
def test_rejects_bad_plans(actions):
    with pytest.raises(ValueError):parse_turn(call(actions))

def test_rejects_multiple_or_truncated_calls():
    with pytest.raises(ValueError):parse_turn(call(['down'])+call(['right']))
    with pytest.raises(ValueError):parse_turn(call(['down'])[:-5])

from backend.tool_call import split_thinking

def test_thoughts_never_execute_as_tool_calls():
    reasoning, final, error = split_thinking('consider '+call(['left']), True)
    assert final == '' and error and reasoning
    reasoning, final, error = split_thinking('consider '+call(['right'])+'\n</think>\n'+call(['left']), True)
    assert 'right' in reasoning and parse_turn(final)==['left'] and error is None

def test_disabled_thinking_preserves_tool_output():
    assert split_thinking(call(['down']),False)==('',call(['down']),None)


def test_hard_drop_is_an_available_action():
    assert parse_turn(call(['right','rotate','hard_drop'])) == ['right','rotate','hard_drop']
