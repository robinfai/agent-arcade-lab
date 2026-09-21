import 'dart:convert';
import 'dart:io';
import 'decision_trial_core.dart';
import 'benchmark_assistance.dart' show requestToolOutput;

void main(List<String> args) {
  if (args.length != 1) throw ArgumentError('Provide run root');
  var runs = 0, actions = 0;
  for (final file
      in Directory(args.single)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('/summary.json'))) {
    final summary = jsonDecode(file.readAsStringSync());
    if (summary['schema'] != 'decision-v1') {
      throw StateError('Wrong experiment schema');
    }
    final trial = DecisionTrial(
      summary['game'],
      summary['seed'],
      summary['order_seed'],
    );
    final cap = summary['max_steps'] as int;
    if (cap < 1 || summary['requests'] > summary['max_requests']) {
      throw StateError('Invalid budget');
    }
    void same(dynamic a, dynamic b, String name) {
      if (jsonEncode(a) != jsonEncode(b)) {
        throw StateError('${file.path}: $name at ${trial.steps}');
      }
    }

    same(summary['candidate_evaluations'], false, 'no evaluations');
    same(summary['execution_correction'], false, 'no correction');
    same(summary['corrections'], 0, 'correction count');
    same(
      jsonDecode(File('${file.parent.path}/initial.json').readAsStringSync()),
      trial.snapshot(),
      'initial',
    );
    var requests = 0;
    for (final line in File(
      '${file.parent.path}/trace.jsonl',
    ).readAsLinesSync()) {
      final row = jsonDecode(line);
      same(row['before'], trial.snapshot(), 'before');
      final options = trial.options();
      if (summary['required_tool'] == true) {
        requestToolOutput(options.request, summary['tool_name']);
        options.request['tool_choice'] = 'required';
      }
      same(row['request'], options.request, 'unranked request');
      same(row['candidate_mapping'], options.canonical, 'candidate mapping');
      same(row['corrected'], false, 'no shield');
      same(row['proposed'], row['response']['choice'], 'original choice');
      if (summary['policy'] == 'model') {
        requests++;
      } else {
        same(
          row['proposed'],
          trial.baseline(options, summary['policy']),
          'baseline policy',
        );
      }
      final recorded = List<String>.from(row['executed_actions']);
      if (recorded.isNotEmpty) {
        same(row['executed_choice'], row['proposed'], 'no replacement');
        same(row['response']['error'], null, 'successful response');
        same(row['error'], null, 'no execution error');
        if (summary['required_tool'] == true) {
          same(
            row['response']['constrained_decoding'],
            true,
            'constrained format',
          );
        }
        same(
          recorded,
          trial.execute(options, row['proposed'], cap),
          'exact path',
        );
      } else {
        same(row['executed_choice'], null, 'nothing executed');
        if (row['error'] == null) throw StateError('Unexplained empty action');
      }
      same(row['after'], trial.snapshot(), 'after');
      if (trial.steps > cap) throw StateError('Cap exceeded');
    }
    same(summary['requests'], requests, 'requests');
    same(summary['decisions'], trial.decisions, 'decisions');
    same(summary['steps'], trial.steps, 'steps');
    same(summary['score'], trial.score, 'score');
    same(summary['final_state'], trial.snapshot(), 'final state');
    if (summary['end_reason'] == 'step_cap') {
      same(trial.steps, cap, 'exact cap');
    }
    if (summary['end_reason'] == 'no_legal_actions') {
      same(trial.options().paths.isEmpty, true, 'terminal legal set');
    }
    runs++;
    actions += trial.steps;
  }
  if (runs == 0) throw StateError('No runs found');
  stdout.writeln(
    'Verified $runs decision-v1 runs, $actions actual actions; no strategy correction, all within recorded caps.',
  );
}
