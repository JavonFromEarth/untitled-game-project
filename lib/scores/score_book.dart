import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:lcs_new_age/scores/high_score.dart';
import 'package:lcs_new_age/title_screen/game_over.dart';

/// An immutable score snapshot, separate from factual Campaign History.
class CompletedScoreReceipt {
  factory CompletedScoreReceipt({
    required String completionId,
    required int gameId,
    required HighScore score,
  }) => CompletedScoreReceipt.fromJson({
    'schemaVersion': 1,
    'completionId': completionId,
    'gameId': gameId,
    'score': score.toJson(),
  });

  factory CompletedScoreReceipt.fromJson(Map<String, dynamic> json) {
    final copy = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
    if (copy['schemaVersion'] != 1 ||
        copy['completionId'] is! String ||
        (copy['completionId'] as String).trim().isEmpty ||
        copy['gameId'] is! int ||
        copy['score'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid completed score receipt');
    }
    final score = copy['score'] as Map<String, dynamic>;
    if (score['ending'] is! String ||
        score['slogan'] is! String ||
        [
          'month',
          'year',
          'statRecruits',
          'statMartyrs',
          'statKills',
          'statKidnappings',
          'statFunds',
          'statSpent',
          'statBuys',
          'statBurns',
        ].any((key) => score[key] is! int)) {
      throw const FormatException('Invalid completed score snapshot');
    }
    HighScore.fromJson(score);
    return CompletedScoreReceipt._(jsonEncode(copy));
  }

  CompletedScoreReceipt._(this._json);
  final String _json;
  Map<String, dynamic> toJson() => jsonDecode(_json) as Map<String, dynamic>;
  String get completionId => toJson()['completionId'] as String;
  int get gameId => toJson()['gameId'] as int;
  HighScore get score =>
      HighScore.fromJson(toJson()['score'] as Map<String, dynamic>);
}

class CompletedScoreConflict implements Exception {
  CompletedScoreConflict(this.completionId);
  final String completionId;
  @override
  String toString() =>
      'Completion $completionId already has different score data';
}

/// One transactional record keeps receipts, completed totals and top five atomic.
/// Instances are detached working copies, never shared live database objects.
class ScoreBook {
  ScoreBook(HighScores baseline)
    : completed = HighScores.fromJson(baseline.toJson());

  factory ScoreBook.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unknown score book schema');
    }
    final book = ScoreBook(
      HighScores.fromJson(json['completed'] as Map<String, dynamic>),
    );
    for (final entry in (json['receipts'] as Map<String, dynamic>).entries) {
      final receipt = CompletedScoreReceipt.fromJson(
        entry.value as Map<String, dynamic>,
      );
      if (entry.key != receipt.completionId) {
        throw const FormatException('Receipt key mismatch');
      }
      book._receipts[entry.key] = receipt;
    }
    return book;
  }

  final HighScores completed;
  final Map<String, CompletedScoreReceipt> _receipts = {};
  CompletedScoreReceipt? receipt(String id) => _receipts[id];

  CompletedScoreReceipt record(CompletedScoreReceipt receipt) {
    final existing = _receipts[receipt.completionId];
    if (existing != null) {
      if (!const DeepCollectionEquality().equals(
        existing.toJson(),
        receipt.toJson(),
      )) {
        throw CompletedScoreConflict(receipt.completionId);
      }
      return existing;
    }
    addScore(receipt.score);
    _receipts[receipt.completionId] = receipt;
    return receipt;
  }

  /// Also used by the old ending API, whose calls have no completion identity.
  void addScore(HighScore score) {
    addStatistics(completed, score);
    if (score.endType == Ending.victory) {
      completed.universalVictories++;
    } else {
      completed.universalLosses++;
    }
    completed.scoreList.add(HighScore.fromJson(score.toJson()));
    rankScores(completed);
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'completed': completed.toJson(),
    'receipts': _receipts.map((id, receipt) => MapEntry(id, receipt.toJson())),
  };
}

void addStatistics(HighScores totals, HighScore score) {
  totals.universalRecruits += score.statRecruits;
  totals.universalMartyrs += score.statMartyrs;
  totals.universalKills += score.statKills;
  totals.universalKidnappings += score.statKidnappings;
  totals.universalFunds += score.statFunds;
  totals.universalSpent += score.statSpent;
  totals.universalFlagBuys += score.statBuys;
  totals.universalFlagBurns += score.statBurns;
}

void rankScores(HighScores scores) {
  scores.scoreList.sort((a, b) => a.compareTo(b));
  scores.scoreList = scores.scoreList.sublist(
    0,
    min(5, scores.scoreList.length),
  );
}
