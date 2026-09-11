import 'dart:convert';

import 'package:file_saver/file_saver.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';

void logPlaythroughEvent({
  required DateTime gameDate,
  required PlaythroughEventType type,
  Map<String, dynamic> data = const {},
}) {
  final event = PlaythroughEvent(
  gameId: gameState.uniqueGameId,
  sequence: ++gameState.playthroughSequence,
  realTime: DateTime.now(),
  gameDate: gameDate,
  type: type,
  data: data,
);

  gameState.playthroughEvents.add(event);
}

String playthroughLogAsJsonl(GameState state) {
  if (state.playthroughEvents.isEmpty) return '';

  return '${state.playthroughEvents.map((event) => jsonEncode(event.toJson())).join('\n')}\n';
}

Future<void> exportPlaythroughLog(GameState state) async {
  final jsonl = playthroughLogAsJsonl(state);
  if (jsonl.isEmpty) return;

  final now = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '_')
      .replaceAll('.', '-');

  await FileSaver.instance.saveFile(
    name: 'lcsna_playthrough_${state.uniqueGameId}_$now.jsonl',
    bytes: const Utf8Encoder().convert(jsonl),
  );
}
