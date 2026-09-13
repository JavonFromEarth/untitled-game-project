import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/scores/high_score.dart';
import 'package:lcs_new_age/scores/score_book.dart';
import 'package:lcs_new_age/title_screen/game_over.dart';

import 'score_test_support.dart';

void main() {
  test(
    'all presentation wire names and legacy indexes retain their meaning',
    () {
      const wires = [
        'victory',
        'hicks_siege',
        'cia_siege',
        'police_siege',
        'corporate_siege',
        'medical_siege',
        'ccs_siege',
        'reaganified',
        'dead',
        'prison',
        'executed',
        'dating',
        'hiding',
        'disband_loss',
        'dispersed',
        'unspecified',
      ];
      for (int i = 0; i < wires.length; i++) {
        final legacy = exampleScore().toJson()
          ..remove('ending')
          ..['endType'] = i;
        final restored = HighScore.fromJson(legacy);
        expect(restored.endType.scoreWireName, wires[i]);
        expect(restored.toJson()['ending'], wires[i]);
        expect(restored.toJson().containsKey('endType'), isFalse);
        expect(ScoreEndingWire.fromWireName(wires[i]), restored.endType);
      }
    },
  );

  test(
    'receipt round trip is detached from score, JSON and returned score',
    () {
      final score = exampleScore();
      final receipt = exampleReceipt(score: score);
      final expected = receipt.toJson();
      score.statFunds = 999;
      final source = jsonDecode(jsonEncode(expected)) as Map<String, dynamic>;
      final restored = CompletedScoreReceipt.fromJson(source);
      (source['score'] as Map<String, dynamic>)['statFunds'] = 999;
      restored.score.statFunds = 888;
      (restored.toJson()['score'] as Map<String, dynamic>).clear();
      expect(receipt.toJson(), expected);
      expect(restored.toJson(), expected);
      expect(restored.completionId, 'completion-123');
      expect(restored.gameId, 123);
    },
  );

  test(
    'new receipt schemas and presentation names fail explicitly when unknown',
    () {
      final json = exampleReceipt().toJson()..['schemaVersion'] = 2;
      expect(() => CompletedScoreReceipt.fromJson(json), throwsFormatException);
      json['schemaVersion'] = 1;
      (json['score'] as Map<String, dynamic>)['ending'] = 'future';
      expect(() => CompletedScoreReceipt.fromJson(json), throwsFormatException);
    },
  );

  test('existing score formula and ranking remain unchanged', () {
    expect(exampleScore().score, 2463);
    final defeat = exampleScore(recruits: 99999);
    final earlyWin = exampleScore(ending: Ending.victory)..year = 2023;
    final lateWin = exampleScore(ending: Ending.victory)..year = 2025;
    final scores = HighScores()
      ..scoreList = [defeat, lateWin, exampleScore(), earlyWin];
    rankScores(scores);
    expect(scores.scoreList, [
      earlyWin,
      lateWin,
      defeat,
      scores.scoreList.last,
    ]);
    expect(scores.scoreList.last.statRecruits, 2);
  });
}
