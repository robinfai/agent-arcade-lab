import 'dart:convert';
import 'game.dart';
import 'assisted_planner.dart';
import 'jev_client.dart';
import 'tetris_assist.dart';

/// Model chooses once per piece; subsequent eight-step batches retain that plan.
class AssistedPlayer {
  final JevClient api;
  final String? instructions;
  final bool uniformAssistance, correctChoices;
  List<String> _pending = [];
  String? _expected;
  Map<String, dynamic> _response = {};
  AssistedPlayer(
    this.api, {
    this.instructions,
    this.uniformAssistance = false,
    this.correctChoices = true,
  });
  String _state(StepTetris g) => jsonEncode(g.actionRequest()['state']);
  void reset() {
    _pending = [];
    _expected = null;
  }

  Future<Map<String, dynamic>> decide(StepTetris g) async {
    if (_pending.isNotEmpty && _expected == _state(g)) {
      return {
        ..._response,
        'actions': _pending.take(8).toList(),
        'continued_plan': true,
        '_http_ms': 0.0,
      };
    }
    reset();
    final plans = reachablePlans(g);
    if (plans.isEmpty) throw StateError('No reachable plan');
    final request = uniformAssistance
        ? uniformTetrisRequest(plans)
        : assistedRequest(g, plans);
    if (instructions != null) {
      request['questions']['move']['instructions'] = instructions;
    }
    final raw = await api.decide(request);
    final result = uniformAssistance
        ? correctPlacement(plans, raw, enabled: correctChoices)
        : raw;
    if (result['error'] != null) return result;
    final chosen = plans.where((p) => p.id == result['choice']).firstOrNull;
    if (chosen == null) throw StateError('Model selected unknown plan');
    _pending = List.of(chosen.actions);
    _response = {
      ...result,
      'assisted': true,
      'thinking': false,
      'predicted_outcome': chosen.outcome,
      'full_plan': chosen.actions,
    };
    return {
      ..._response,
      'actions': _pending.take(8).toList(),
      'continued_plan': false,
    };
  }

  void observe(StepTetris g, TurnExecutor execution) {
    if (execution.stopReason != 'plan_complete') {
      reset();
      return;
    }
    _pending = _pending.skip(execution.executed).toList();
    _expected = _state(g);
  }
}
