import 'dart:convert';

import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/playthrough_log/campaign_history_archive.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';
import 'package:lcs_new_age/scores/high_score.dart';
import 'package:lcs_new_age/title_screen/game_over.dart';

sealed class TerminalSaveInspection {}

class OrdinarySave extends TerminalSaveInspection {}

class InvalidTerminalSave extends TerminalSaveInspection {
  InvalidTerminalSave(this.message);
  final String message;
}

class TerminalCompletion extends TerminalSaveInspection {
  TerminalCompletion(
    this.event,
    this.outcome,
    this.route,
    this.presentationEnding,
  );
  final PlaythroughEvent event;
  final CampaignOutcome outcome;
  final CampaignEndRoute route;
  final Ending presentationEnding;
  String get archiveId => event.data['archiveId'] as String;
  Map<String, dynamic> get context =>
      event.data['context'] as Map<String, dynamic>;
}

/// A marker that fails validation is never an ordinary playable save.
TerminalSaveInspection inspectTerminalSave(
  GameState state, {
  String? saveGameId,
}) {
  final markers = state.playthroughEvents
      .where((e) => e.type == PlaythroughEventType.campaignEnded)
      .toList();
  if (markers.isEmpty) return OrdinarySave();
  if (markers.length != 1 ||
      !identical(markers.single, state.playthroughEvents.last)) {
    return InvalidTerminalSave(
      'Terminal event must occur exactly once, at the end of history',
    );
  }
  final terminal = markers.single;
  int previous = 0;
  for (final event in state.playthroughEvents) {
    if (event.gameId != state.uniqueGameId || event.sequence <= previous) {
      return InvalidTerminalSave('Campaign IDs or history sequences disagree');
    }
    previous = event.sequence;
  }
  if (terminal.sequence != state.playthroughSequence ||
      terminal.gameDate != state.date ||
      (saveGameId != null && saveGameId != state.uniqueGameId.toString())) {
    return InvalidTerminalSave(
      'Terminal event does not match the saved campaign',
    );
  }
  try {
    final event = PlaythroughEvent.fromJson(
      jsonDecode(jsonEncode(terminal.toJson())) as Map<String, dynamic>,
    );
    final data = event.data;
    if (data['archiveId'] is! String ||
        (data['archiveId'] as String).trim().isEmpty ||
        data['context'] is! Map<String, dynamic>) {
      return InvalidTerminalSave(
        'Missing archive ID or factual terminal context',
      );
    }
    final outcome = CampaignOutcome.values.firstWhere(
      (v) => v.wireName == data['outcome'],
    );
    final route = CampaignEndRoute.values.firstWhere(
      (v) => v.wireName == data['route'],
    );
    // No fallback from factual routes: older terminal events lack this decision.
    final presentation = ScoreEndingWire.fromWireName(
      data['presentationEnding'] as String,
    );
    return TerminalCompletion(event, outcome, route, presentation);
  } catch (error) {
    return InvalidTerminalSave('Invalid terminal metadata: $error');
  }
}

/// Also detects markers whose malformed envelope prevents GameState decoding.
bool hasSerializedTerminalMarker(Map<String, dynamic> json) {
  final history = json['playthroughEvents'];
  return history is List &&
      history.any((event) => event is Map && event['type'] == 'campaign_ended');
}
