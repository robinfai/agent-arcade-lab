import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/game.dart';
import 'package:agent_arcade_lab/assisted_planner.dart';

void main() {
  final cases = [
    for (final piece in shapes.keys)
      (() {
        final g = StepTetris(20260923)..piece = piece;
        return {
          'piece': piece,
          'request': assistedRequest(g, reachablePlans(g)),
        };
      })(),
  ];
  File('reports/kev/initial-inputs.json').writeAsStringSync(jsonEncode(cases));
}
