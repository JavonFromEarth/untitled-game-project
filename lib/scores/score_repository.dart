import 'dart:convert';

import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';
import 'package:lcs_new_age/saveload/storage/game_storage.dart';
import 'package:lcs_new_age/scores/high_score.dart';
import 'package:lcs_new_age/scores/score_book.dart';
import 'package:lcs_new_age/title_screen/game_over.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScoreRepository {
  ScoreRepository(this.storage);
  final GameStorage storage;

  /// The database record itself is the migration marker. Preferences remain intact.
  Future<void> initialize(SharedPreferences preferences) async {
    if (await storage.loadScoreBook() != null) return;
    final version = preferences.getInt('scoreVersion') ?? -1;
    if (version != -1 && version != 1) {
      throw FormatException('Unsupported legacy score version', version);
    }
    final raw = version == 1 ? preferences.getString('score') : null;
    final baseline = raw == null || raw.isEmpty
        ? HighScores()
        : HighScores.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    await storage.updateScoreBook(
      (existing) => existing ?? ScoreBook(baseline),
    );
  }

  Future<ScoreBook> load() async =>
      await storage.loadScoreBook() ??
      (throw StateError('Scores not initialized'));

  Future<CompletedScoreReceipt> record(CompletedScoreReceipt receipt) async {
    late CompletedScoreReceipt accepted;
    await storage.updateScoreBook((book) {
      if (book == null) throw StateError('Scores not initialized');
      accepted = book.record(receipt);
      return book;
    });
    return accepted;
  }

  Future<void> recordAnonymous(HighScore score) async {
    // Snapshot before any await; legacy gameplay callers still use this API.
    final snapshot = HighScore.fromJson(score.toJson());
    await storage.updateScoreBook((book) {
      if (book == null) throw StateError('Scores not initialized');
      book.addScore(snapshot);
      return book;
    });
  }

  Future<HighScores> loadForDisplay(Iterable<GameState> activeStates) async {
    final book = await load();
    final display = HighScores.fromJson(book.completed.toJson());
    for (final state in activeStates) {
      final terminal = state.playthroughEvents.lastOrNull;
      if (terminal?.type == PlaythroughEventType.campaignEnded &&
          terminal!.gameId == state.uniqueGameId &&
          terminal.sequence == state.playthroughSequence) {
        final id = terminal.data['archiveId'];
        if (id is String && book.receipt(id)?.gameId == state.uniqueGameId) {
          continue;
        }
      }
      addStatistics(display, scoreFromState(state, Ending.unspecified));
    }
    rankScores(display);
    return display;
  }
}

HighScore scoreFromState(GameState state, Ending ending) => HighScore(
  slogan: state.lcs.slogan,
  month: state.date.month,
  year: state.date.year,
  statRecruits: state.stats.recruits,
  statMartyrs: state.stats.martyrs,
  statKills: state.stats.kills,
  statKidnappings: state.stats.kidnappings,
  statFunds: state.ledger.totalIncome,
  statSpent: state.ledger.totalExpense,
  statBuys: state.stats.flagsBought,
  statBurns: state.stats.flagsBurned,
  endType: ending,
);
