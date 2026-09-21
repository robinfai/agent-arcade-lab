import 'dart:convert';
import 'dart:io';
import 'resume_decision.dart';

void main(List<String> args) {
  final expected = [1, 2, 4, 8, 16, 32, 60, 60, 60];
  for (var i = 0; i < expected.length; i++) {
    if (retryDelaySeconds(i + 1) != expected[i]) throw StateError('Backoff $i');
  }
  if (retryDelaySeconds(100000) != 60) throw StateError('Backoff cap');
  for (final path in args) {
    final dir = Directory(path);
    final summary = Map<String, dynamic>.from(
      jsonDecode(File('$path/summary.json').readAsStringSync()),
    );
    final trial = restoreTrial(dir, summary);
    final last = jsonDecode(File('$path/trace.jsonl').readAsLinesSync().last);
    if (last['executed_actions'].isEmpty &&
        jsonEncode(trial.options().request) != jsonEncode(last['request'])) {
      throw StateError('Retry would change failed payload');
    }
    stdout.writeln(
      'Restored ${trial.steps} steps, ${trial.decisions} decisions; failed payload unchanged: $path',
    );
  }
  stdout.writeln('Backoff sequence and 60-second cap passed.');
}
