import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/saveload/storage/game_storage.dart';
import 'package:lcs_new_age/scores/score_book.dart';
import 'package:lcs_new_age/scores/score_repository.dart';
import 'package:lcs_new_age/title_screen/game_over.dart';
import 'package:lcs_new_age/title_screen/high_scores.dart' show saveHighScore;
import 'package:shared_preferences/shared_preferences.dart';

import 'score_test_support.dart';

void scoreStorageContract(Future<GameStorage> Function() openStorage) {
  late GameStorage storage;
  late ScoreRepository repository;
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    storage = await openStorage();
    repository = ScoreRepository(storage);
  });
  tearDown(() => storage.close());

  test(
    'first completion and identical retry account every statistic once',
    () async {
      await repository.initialize(prefs);
      final receipt = exampleReceipt();
      await repository.record(receipt);
      final expected = (await repository.load()).toJson();
      final accepted = await repository.record(receipt);
      expect(accepted.toJson(), receipt.toJson());
      expect((await repository.load()).toJson(), expected);
      final totals = (await repository.load()).completed;
      expect(totals.toJson(), {
        'highScores': [receipt.score.toJson()],
        'universalRecruits': 2,
        'universalMartyrs': 3,
        'universalKills': 4,
        'universalKidnappings': 5,
        'universalFunds': 6,
        'universalSpent': 7,
        'universalFlagBuys': 8,
        'universalFlagBurns': 9,
        'universalLosses': 1,
        'universalVictories': 0,
      });
      await storage.close();
      storage = await openStorage();
      repository = ScoreRepository(storage);
      expect((await repository.load()).toJson(), expected);
      expect(await storage.listGameIds(), isEmpty);
      expect(await storage.listArchiveIds(), isEmpty);
    },
  );

  test(
    'conflicts in campaign, presentation, score or statistics change nothing',
    () async {
      await repository.initialize(prefs);
      await repository.record(exampleReceipt());
      final expected = (await repository.load()).toJson();
      for (final receipt in [
        exampleReceipt(gameId: 999),
        exampleReceipt(score: exampleScore(ending: Ending.executed)),
        exampleReceipt(score: exampleScore()..slogan = 'different'),
        exampleReceipt(score: exampleScore()..statMartyrs = 100),
      ]) {
        await expectLater(
          repository.record(receipt),
          throwsA(isA<CompletedScoreConflict>()),
        );
        expect((await repository.load()).toJson(), expected);
      }
    },
  );

  test(
    'victory count and score apply once under concurrent identical writes',
    () async {
      await repository.initialize(prefs);
      final receipt = exampleReceipt(
        score: exampleScore(ending: Ending.victory),
      );
      final results = await Future.wait([
        repository.record(receipt),
        repository.record(receipt),
      ]);
      expect(results.map((r) => r.toJson()), [
        receipt.toJson(),
        receipt.toJson(),
      ]);
      final book = await repository.load();
      expect(book.completed.universalVictories, 1);
      expect(book.completed.universalLosses, 0);
      expect(book.completed.universalRecruits, 2);
      expect(book.completed.scoreList, hasLength(1));
    },
  );

  test('concurrent different completions do not lose updates', () async {
    await repository.initialize(prefs);
    await Future.wait([
      repository.record(exampleReceipt(id: 'one')),
      repository.record(exampleReceipt(id: 'two')),
    ]);
    final book = await repository.load();
    expect(book.completed.universalLosses, 2);
    expect(book.completed.universalRecruits, 4);
    expect(book.receipt('one'), isNotNull);
    expect(book.receipt('two'), isNotNull);
  });

  test(
    'receipt survives top-five eviction and retry does not reinsert score',
    () async {
      await repository.initialize(prefs);
      final receipt = exampleReceipt();
      await repository.record(receipt);
      for (int i = 0; i < 5; i++) {
        await repository.record(
          exampleReceipt(
            id: 'better-$i',
            score: exampleScore(recruits: 10 + i),
          ),
        );
      }
      final book = await repository.load();
      expect(book.completed.scoreList, hasLength(5));
      expect(book.completed.scoreList.every((s) => s.statRecruits > 2), isTrue);
      expect(book.receipt(receipt.completionId)!.toJson(), receipt.toJson());
      await repository.record(receipt);
      expect((await repository.load()).toJson(), book.toJson());
    },
  );

  test('transaction failure changes neither receipt nor totals', () async {
    await repository.initialize(prefs);
    final before = (await repository.load()).toJson();
    await expectLater(
      storage.updateScoreBook((book) {
        book!.record(exampleReceipt());
        throw StateError('Injected transaction failure');
      }),
      throwsStateError,
    );
    expect((await repository.load()).toJson(), before);
    expect((await repository.load()).receipt('completion-123'), isNull);
  });

  test(
    'lost acknowledgement after commit retries without another application',
    () async {
      await repository.initialize(prefs);
      Future<void> lostAcknowledgement() async {
        await repository.record(exampleReceipt());
        throw StateError('Response lost after commit');
      }

      await expectLater(lostAcknowledgement(), throwsStateError);
      await storage.close();
      storage = await openStorage();
      repository = ScoreRepository(storage);
      await repository.record(exampleReceipt());
      expect((await repository.load()).completed.universalLosses, 1);
    },
  );

  test(
    'raw legacy migration preserves anonymous entries and totals exactly once',
    () async {
      final oldScore = exampleScore().toJson()
        ..remove('ending')
        ..['endType'] = 3;
      final raw = jsonEncode({
        'highScores': [oldScore],
        'universalRecruits': 100,
        'universalLosses': 7,
      });
      await prefs.setInt('scoreVersion', 1);
      await prefs.setString('score', raw);
      await Future.wait([
        repository.initialize(prefs),
        repository.initialize(prefs),
      ]);
      final book = await repository.load();
      expect(book.completed.universalRecruits, 100);
      expect(book.completed.universalLosses, 7);
      expect(book.completed.scoreList.single.endType, Ending.policeSiege);
      expect(book.toJson()['receipts'], isEmpty);
      expect(prefs.getString('score'), raw);
      await repository.record(exampleReceipt());
      await prefs.setString('score', 'not read after migration');
      await repository.initialize(prefs);
      expect((await repository.load()).completed.universalRecruits, 102);
      expect((await repository.load()).completed.universalLosses, 8);
    },
  );

  test(
    'invalid legacy data is not replaced by empty initialized data',
    () async {
      await prefs.setInt('scoreVersion', 88);
      await expectLater(repository.initialize(prefs), throwsFormatException);
      expect(await storage.loadScoreBook(), isNull);
      await prefs.setInt('scoreVersion', 1);
      await prefs.setString('score', 'malformed');
      await expectLater(repository.initialize(prefs), throwsFormatException);
      expect(await storage.loadScoreBook(), isNull);
    },
  );

  test(
    'display-only active statistics never enter completed totals through legacy writer',
    () async {
      await repository.initialize(prefs);
      final active = GameState()..uniqueGameId = 123;
      active.stats.recruits = 10;
      expect((await repository.loadForDisplay([active])).universalRecruits, 10);
      expect((await repository.load()).completed.universalRecruits, 0);
      gameState = GameState();
      gameState.stats.recruits = 2;
      scoreRepository = repository;
      await saveHighScore(Ending.policeSiege);
      expect((await repository.load()).completed.universalRecruits, 2);
      expect((await repository.loadForDisplay([active])).universalRecruits, 12);
      expect((await repository.load()).completed.universalRecruits, 2);
      expect(prefs.containsKey('score'), isFalse);
    },
  );

  test('accounted terminal save is omitted from display active totals', () async {
    await repository.initialize(prefs);
    final state = GameState()
      ..uniqueGameId = 123
      ..playthroughSequence = 4;
    state.stats.recruits = 2;
    state.playthroughEvents.add(
      PlaythroughEvent(
        gameId: 123,
        sequence: 4,
        realTime: DateTime.utc(2026),
        gameDate: state.date,
        type: PlaythroughEventType.campaignEnded,
        data: {'archiveId': 'completion-123'},
      ),
    );
    expect((await repository.loadForDisplay([state])).universalRecruits, 2);
    await repository.record(exampleReceipt());
    expect((await repository.loadForDisplay([state])).universalRecruits, 2);
    // Matching an ID from a different campaign must not suppress this campaign.
    state.uniqueGameId = 999;
    expect((await repository.loadForDisplay([state])).universalRecruits, 4);
  });
}
