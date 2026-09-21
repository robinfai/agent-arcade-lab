"""Compact typed-choice input; all legal candidates remain in original order."""

BASELINE = "Choose the best Tetris placement to score points and survive."
GUIDED = (
    "Choose a placement. First avoid losing. Then maximize cleared rows. "
    "For equal clears minimize holes, then peak height, total height, and unevenness. "
    "A full 10-cell row disappears and scores. Losing is failure, not victory."
)
EXAMPLES = (
    "Examples, not current options: "
    "1) Horizontal I fills four bottom gaps: clear 1 row, score 100. "
    "2) O fills a two-column gap in two rows: clear 2, score 300. "
    "3) Rotate I into a one-column four-row well: clear 4, score 800. "
    "4) With equal clears, choose 0 holes over 3 holes. "
    "5) A safe placement beats a losing placement. "
    "Holes are empty cells trapped under blocks. All listed placements are reachable. "
    "Options are not ranked. Choose using their predicted results."
)


def make_input(body, variant="guided"):
    if variant not in ("baseline", "guided", "community"):
        raise ValueError("Unknown prompt variant")
    candidates = body["questions"]["move"]["criteria"]
    if not isinstance(candidates, dict) or not candidates:
        raise ValueError("Expected nonempty placement candidates")
    if variant == "community":
        return community_input(candidates)
    criteria = {}
    for label, o in candidates.items():
        # Describe outcomes, never score, rank, filter, or select them in code.
        criteria[label] = (
            f"{'losing' if o['game_over'] else 'safe'}; "
            f"clear {o['lines_cleared']}; holes {o['holes_after']}; "
            f"peak {o['max_height']}; total height {o['height_sum']}; "
            f"unevenness {o['roughness']}"
        )
    state = body.get("state", {})
    state = f"Tetris. Current piece {state.get('piece', '?')}; next {state.get('next_piece', '?')}. " + EXAMPLES
    questions = {"move": {"type": "choice", "instructions": GUIDED if variant == "guided" else BASELINE, "criteria": criteria}}
    return state, questions


def placement_priority(o):
    return (bool(o['game_over']), -o['lines_cleared'], o['holes_after'],
            o['max_height'], o['height_sum'], o['roughness'])


def community_input(candidates):
    # Explicit planner assistance: label best results but leave every choice to the model.
    safe = [o for o in candidates.values() if not o['game_over']]
    best = min(map(placement_priority, safe)) if safe else None
    max_clear = max((o['lines_cleared'] for o in safe), default=0)
    min_holes = min((o['holes_after'] for o in safe if o['lines_cleared'] == max_clear), default=0)
    descriptions = {}
    for label, o in candidates.items():
        if o['game_over']:
            text = 'Unsafe. Game ends.'
        elif placement_priority(o) == best:
            text = f"Safe. Best move. Clear {o['lines_cleared']} rows now." if o['lines_cleared'] else 'Safe. Best progress. Fewest holes, then lowest stack.'
        elif o['lines_cleared'] < max_clear:
            text = 'Safe now. Misses a better immediate row clear.'
        elif o['holes_after'] > min_holes:
            text = 'Safe now. More trapped holes than a better option.'
        else:
            text = 'Safe now. Less progress. Taller or less even stack.'
        descriptions[label] = text
    state = ('Tetris. Fill all 10 cells in a row to clear it and score. '
             'Program labels compare survival, immediate clears, holes, then stack height. '
             'Best means best predicted one-piece result, not guaranteed future survival. '
             'No execution correction. Safe move available: ' + ('yes.' if safe else 'no.'))
    return state, {'move': {'type': 'choice', 'instructions': 'Choose the best safe move. Clear rows and avoid trapped holes. Avoid game over.', 'criteria': descriptions}}


def set_complete_budget(agent, state, questions):
    """Detect Laya's per-option 48-token cap and prevent all other truncation."""
    from laya_mlx.common import render_options, serialize_state
    q = agent._to_internal(questions["move"])
    encode = lambda s: agent.tok(s, add_special_tokens=False)["input_ids"]
    option_lengths = [len(encode(" " + s)) for s in render_options(q)]
    if max(option_lengths) > 48:
        raise ValueError("A candidate exceeds Laya's 48-token option cap")
    instruction_length = len(encode("choice question: " + q["ins"]))
    head = sum(n + 1 for n in option_lengths) + max(16, instruction_length)
    state_length = len(encode(serialize_state(state)))
    maximum = head + state_length + 4
    if maximum > min(4096, agent.encoder_cfg["max_position_embeddings"]):
        raise ValueError("Complete input exceeds the configured 4096-token safety limit")
    agent.cfg.update(head_max_len=head, max_len=maximum)
    items, _ = agent.prepare(state, questions)
    expected = sum(n + 1 for n in option_lengths) + instruction_length + state_length + 4
    if len(items[0]["ids"]) != expected or len(items[0]["markers"]) != len(option_lengths):
        raise ValueError("Input was truncated")
    return {"input_tokens": expected, "options": len(option_lengths), "max_option_tokens": max(option_lengths), "head_max_len": head, "max_len": maximum, "truncated": False}
