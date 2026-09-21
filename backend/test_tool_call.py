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


def test_tool_choice_contract():
    from backend.tool_call import require_tool
    assert not require_tool('auto', 'snake_move')
    assert require_tool('required', 'snake_move')
    assert require_tool({'type': 'function', 'function': {'name': 'snake_move'}}, 'snake_move')
    for value in ['none', None, {}, {'type': 'function', 'function': {'name': 'wrong'}}]:
        with pytest.raises(ValueError):
            require_tool(value, 'snake_move')


class CharacterTokenizer:
    eos_token_ids = {0}

    def encode(self, text, **kwargs):
        return list(text.encode())

    def decode(self, tokens):
        return bytes(tokens).decode()


@pytest.mark.parametrize('chosen', ['UP', 'DOWN', 'LEFT', 'RIGHT'])
def test_constraints_preserve_every_direction_despite_invalid_token_preference(chosen):
    import mlx.core as mx
    from backend.tool_call import ToolCallSampler
    tokenizer = CharacterTokenizer()
    choices = {'UP': 'unsafe', 'DOWN': 'best', 'LEFT': 'collision', 'RIGHT': 'safe'}
    sampler = ToolCallSampler(tokenizer, choices, 'snake_move', mx, max_tokens=256)
    expected = f'<tool_call>\n<function=snake_move>\n<parameter=placement_id>\n{chosen}\n</parameter>\n</function>\n</tool_call>'
    output = []
    for token in [*expected.encode(), 0]:
        scores = mx.zeros((1, 256))
        scores[0, 255] = 100  # Invalid output must never win.
        scores[0, token] = 10
        actual = sampler(scores).item()
        assert actual == token
        if actual: output.append(actual)
    assert parse_call(tokenizer.decode(output), choices, 'snake_move') == chosen
    assert sampler(mx.zeros((1, 256))).item() == 0  # MLX lookahead after EOS


def test_constraint_rejects_unrepresentable_or_overbudget_labels():
    import mlx.core as mx
    from backend.tool_call import ToolCallSampler
    for label in ['<bad>', '', ' DOWN ', 'x' * 300]:
        with pytest.raises(ValueError):
            ToolCallSampler(CharacterTokenizer(), {label: ''}, 'snake_move', mx)
