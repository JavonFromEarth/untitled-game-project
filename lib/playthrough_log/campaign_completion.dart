import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/playthrough_log/campaign_history_archive.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/saveload/storage/game_storage.dart';
import 'package:lcs_new_age/title_screen/title_screen.dart';

class CampaignCompletionConflict implements Exception {
  CampaignCompletionConflict(this.message);
  final String message;

  @override
  String toString() => 'Campaign completion conflict: $message';
}

/// Prepare an already-resolved ending. Callers must await this before proceeding
/// with finalization and must not resume gameplay while completion is pending.
/// The terminal event is the sole retry identity, including after save/reload.
Future<CampaignHistoryArchive> prepareCampaignCompletion({
  required GameState state,
  required GameStorage storage,
  required CampaignOutcome outcome,
  required CampaignEndRoute route,
  Map<String, dynamic> terminalContext = const {},
}) async {
  final result = <String, dynamic>{
    'outcome': outcome.wireName,
    'route': route.wireName,
    // Detach the caller's nested context before the first asynchronous step.
    'context': jsonDecode(jsonEncode(terminalContext)),
  };
  PlaythroughEvent? terminal;
  int previousSequence = 0;
  for (final event in state.playthroughEvents) {
    if (event.gameId != state.uniqueGameId ||
        event.sequence <= previousSequence ||
        event.sequence > state.playthroughSequence ||
        terminal != null) {
      throw CampaignCompletionConflict(
        'History is inconsistent or continues after completion',
      );
    }
    previousSequence = event.sequence;
    if (event.type == PlaythroughEventType.campaignEnded) terminal = event;
  }
  if (state.playthroughSequence < 0) {
    throw CampaignCompletionConflict('Negative history sequence');
  }
  if (terminal != null) {
    final recordedResult = {
      'outcome': terminal.data['outcome'],
      'route': terminal.data['route'],
      'context': terminal.data['context'],
    };
    if (!const DeepCollectionEquality().equals(recordedResult, result) ||
        terminal.sequence != state.playthroughSequence ||
        terminal.gameDate != state.date) {
      throw CampaignCompletionConflict(
        'Requested ending differs from terminal history',
      );
    }
    final archiveId = terminal.data['archiveId'];
    if (archiveId is! String || archiveId.trim().isEmpty) {
      throw CampaignCompletionConflict(
        'Terminal event has no valid archive ID',
      );
    }
  } else {
    terminal = PlaythroughEvent(
      gameId: state.uniqueGameId,
      sequence: state.playthroughSequence + 1,
      realTime: DateTime.now().toUtc(),
      gameDate: state.date,
      type: PlaythroughEventType.campaignEnded,
      data: {'archiveId': _newCompletionId(), ...result},
    );
    state.playthroughEvents.add(terminal);
    state.playthroughSequence = terminal.sequence;
  }

  // Serialize once: later in-memory mutations cannot change what gets archived.
  // A failed save leaves the event in memory for a retry, but never writes an
  // archive. Once this save succeeds, retries can recover the ID from storage.
  final snapshot =
      jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>;
  final save = SaveFile(
    version: gameVersion,
    saveData: snapshot,
    gameId: state.uniqueGameId.toString(),
    lastPlayed: terminal.realTime,
  );
  await storage.saveGame(save);

  final events = (snapshot['playthroughEvents'] as List<dynamic>)
      .map((raw) => PlaythroughEvent.fromJson(raw as Map<String, dynamic>))
      .toList();
  final persistedTerminal = events.last;
  final archive = CampaignHistoryArchive(
    archiveId: persistedTerminal.data['archiveId'] as String,
    gameId: persistedTerminal.gameId,
    finalGameDate: persistedTerminal.gameDate,
    completedAt: persistedTerminal.realTime,
    finalSequence: persistedTerminal.sequence,
    outcome: outcome,
    route: route,
    terminalContext: persistedTerminal.data['context'] as Map<String, dynamic>,
    events: events,
  );
  // Both created and alreadyExists are successful. Conflicts/failures propagate
  // with the terminal active save still present; this layer never deletes it.
  await storage.saveArchive(archive);
  return archive;
}

String _newCompletionId() {
  final random = Random.secure();
  final suffix = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'completion-$suffix';
}
