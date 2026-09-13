import 'package:collection/collection.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/playthrough_log/campaign_completion.dart';
import 'package:lcs_new_age/playthrough_log/campaign_history_archive.dart';
import 'package:lcs_new_age/playthrough_log/terminal_save.dart';
import 'package:lcs_new_age/saveload/storage/game_storage.dart';
import 'package:lcs_new_age/scores/score_book.dart';
import 'package:lcs_new_age/scores/score_repository.dart';
import 'package:lcs_new_age/title_screen/game_over.dart';

class CampaignFinalizationResult {
  CampaignFinalizationResult(this.archive, this.receipt);
  final CampaignHistoryArchive archive;
  final CompletedScoreReceipt receipt;
}

/// Call only for a resolved ending. Gameplay must remain paused until this
/// finishes. Failures propagate with the recovery save retained before deletion.
Future<CampaignFinalizationResult> finalizeCampaign({
  required GameState state,
  required GameStorage storage,
  required ScoreRepository scores,
  required CampaignOutcome outcome,
  required CampaignEndRoute route,
  required Ending presentationEnding,
  Map<String, dynamic> terminalContext = const {},
}) async {
  if (!identical(scores.storage, storage)) {
    throw ArgumentError('Finalization and scoring must use the same storage');
  }
  final archive = await prepareCampaignCompletion(
    state: state,
    storage: storage,
    outcome: outcome,
    route: route,
    presentationEnding: presentationEnding,
    terminalContext: terminalContext,
  );
  // Score the persisted terminal snapshot, not possibly mutated live objects.
  final saved = await storage.loadGame(archive.gameId.toString());
  if (saved == null) {
    throw StateError('Terminal save unavailable for score accounting');
  }
  final persisted = GameState.fromJson(saved.saveData);
  final terminal = inspectTerminalSave(persisted, saveGameId: saved.gameId);
  if (terminal is! TerminalCompletion ||
      terminal.archiveId != archive.archiveId ||
      !const DeepCollectionEquality().equals(
        persisted.playthroughEvents.map((e) => e.toJson()).toList(),
        archive.toJson()['events'],
      )) {
    throw CampaignCompletionConflict(
      'Persisted terminal history changed during finalization',
    );
  }
  final receipt = await scores.record(
    CompletedScoreReceipt(
      completionId: terminal.archiveId,
      gameId: persisted.uniqueGameId,
      score: scoreFromState(persisted, terminal.presentationEnding),
    ),
  );
  await storage.deleteGame(saved.gameId);
  return CampaignFinalizationResult(archive, receipt);
}

Future<CampaignFinalizationResult> recoverCampaignCompletion({
  required GameState state,
  required String saveGameId,
  required GameStorage storage,
  required ScoreRepository scores,
}) async {
  final terminal = inspectTerminalSave(state, saveGameId: saveGameId);
  if (terminal is! TerminalCompletion) {
    throw CampaignCompletionConflict(
      terminal is InvalidTerminalSave
          ? terminal.message
          : 'No terminal event to recover',
    );
  }
  return finalizeCampaign(
    state: state,
    storage: storage,
    scores: scores,
    outcome: terminal.outcome,
    route: terminal.route,
    presentationEnding: terminal.presentationEnding,
    terminalContext: terminal.context,
  );
}
