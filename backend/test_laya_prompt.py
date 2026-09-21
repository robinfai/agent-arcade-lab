import pytest
from backend.laya_prompt import make_input


def test_preserves_all_candidates_and_order_without_ranking():
    base = dict(game_over=False, lines_cleared=0, holes_after=3, max_height=7, height_sum=22, roughness=4)
    body = {'questions': {'move': {'criteria': {'p9': base, 'p2': {**base, 'lines_cleared': 2}}}}}
    state, questions = make_input(body)
    options = questions['move']['criteria']
    assert list(options) == ['p9', 'p2']
    assert 'clear 2' in options['p2'] and 'holes 3' in options['p9']
    assert 'Examples, not current options' in state


def test_only_instructions_differ_in_control():
    o = dict(game_over=True, lines_cleared=2, holes_after=0, max_height=20, height_sum=80, roughness=4)
    body = {'questions': {'move': {'criteria': {'p0': o}}}}
    a, qa = make_input(body, 'baseline')
    b, qb = make_input(body, 'guided')
    assert a == b
    assert qa['move']['criteria'] == qb['move']['criteria']
    assert 'losing' in qa['move']['criteria']['p0']
    assert qa['move']['instructions'] != qb['move']['instructions']


def test_rejects_empty_options():
    with pytest.raises(ValueError):
        make_input({'questions': {'move': {'criteria': {}}}})


def test_community_labels_clears_before_holes_without_filtering():
    base = dict(game_over=False, lines_cleared=0, holes_after=0, max_height=3, height_sum=10, roughness=2)
    options = {'flat': base, 'clear': {**base, 'lines_cleared': 1, 'holes_after': 2}, 'lose': {**base, 'game_over': True, 'lines_cleared': 4}}
    _, q = make_input({'questions': {'move': {'criteria': options}}}, 'community')
    c = q['move']['criteria']
    assert list(c) == list(options)
    assert 'Best move' in c['clear']
    assert 'Misses' in c['flat']
    assert 'Unsafe' in c['lose']


def test_community_never_labels_terminal_as_safe_and_keeps_ties():
    base = dict(game_over=False, lines_cleared=0, holes_after=0, max_height=3, height_sum=10, roughness=2)
    body = {'questions': {'move': {'criteria': {'a': base, 'b': dict(base)}}}}
    _, q = make_input(body, 'community')
    assert all('Best progress' in t for t in q['move']['criteria'].values())
    base['game_over'] = True
    body['questions']['move']['criteria'] = {'a': base}
    state, q = make_input(body, 'community')
    assert 'available: no' in state
    assert q['move']['criteria']['a'] == 'Unsafe. Game ends.'
