@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/playthrough_log/campaign_finalization.dart';
import 'package:lcs_new_age/playthrough_log/campaign_history_archive.dart';
import 'package:lcs_new_age/playthrough_log/terminal_save.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/saveload/storage/game_storage.dart';
import 'package:lcs_new_age/saveload/storage/sembast_storage.dart';
import 'package:lcs_new_age/scores/score_book.dart';
import 'package:lcs_new_age/scores/score_repository.dart';
import 'package:lcs_new_age/title_screen/game_over.dart';
import 'package:lcs_new_age/title_screen/launch_game.dart'
    show EndGameException;
import 'package:shared_preferences/shared_preferences.dart';

import 'archive_test_support.dart';
import 'test_support.dart';

void main() {
  setUpAll(ensureGameDataLoaded);
  late FinalizationStorage storage;
  late ScoreRepository scores;
  late GameState state;
  setUp(() async {
    final directory = await Directory.systemTemp.createTemp(
      'lcs_finalization_',
    );
    addTearDown(() => directory.delete(recursive: true));
    storage = FinalizationStorage('${directory.path}/game.db');
    await storage.init();
    addTearDown(storage.close);
    SharedPreferences.setMockInitialValues({});
    scores = ScoreRepository(storage);
    await scores.initialize(await SharedPreferences.getInstance());
    storage.operations.clear();
    final raw =
        jsonDecode(await File('test/saves/moe_1_5.json').readAsString())
            as Map<String, dynamic>;
    gameState = state = GameState.fromJson(SaveFile.fromJson(raw).saveData)
      ..uniqueGameId = 123
      ..date = DateTime(2023, 2, 2)
      ..playthroughEvents = archiveEvents()
      ..playthroughSequence = 8;
    state.stats.recruits = 2;
  });

  Future<CampaignFinalizationResult> finish({
    Ending ending = Ending.policeSiege,
  }) => finalizeCampaign(
    state: state,
    storage: storage,
    scores: scores,
    outcome: CampaignOutcome.defeat,
    route: CampaignEndRoute.noQualifyingMembers,
    presentationEnding: ending,
    terminalContext: {'siegeType': 'police'},
  );

  test(
    'first finalization orders save archive score delete and returns accepted ending',
    () async {
      final result = await finish();
      expect(storage.operations, ['save', 'archive', 'score', 'delete']);
      expect(result.receipt.score.endType, Ending.policeSiege);
      expect(result.receipt.completionId, result.archive.archiveId);
      expect(
        result.archive.events.last.data['presentationEnding'],
        'police_siege',
      );
      expect(result.archive.terminalResult, {
        'outcome': 'defeat',
        'route': 'no_qualifying_members',
        'context': {'siegeType': 'police'},
      });
      expect(await storage.loadGame('123'), isNull);
      expect((await scores.load()).completed.universalLosses, 1);
    },
  );

  test(
    'identical finalization retry with absent active save is harmless',
    () async {
      final first = await finish();
      final event = state.playthroughEvents.last.toJson();
      final book = (await scores.load()).toJson();
      final retry = await finish();
      expect(retry.archive.toJson(), first.archive.toJson());
      expect(retry.receipt.toJson(), first.receipt.toJson());
      expect(state.playthroughEvents.last.toJson(), event);
      expect(state.playthroughSequence, 9);
      expect(await storage.listArchiveIds(), [first.archive.archiveId]);
      expect((await scores.load()).toJson(), book);
      expect(await storage.loadGame('123'), isNull);
      // Existing storage deletion also accepts an already absent key.
      await storage.deleteGame('123');
    },
  );

  for (final stage in ['save', 'archive', 'score']) {
    test('$stage failure prevents all later writes and deletion', () async {
      final before = SaveFile(
        version: '1.5.6',
        gameId: '123',
        saveData: state.toJson(),
        lastPlayed: null,
      );
      await storage.saveGame(before);
      storage.operations.clear();
      storage.failStage = stage;
      await expectLater(finish(), throwsStateError);
      expect(
        storage.operations,
        [
          'save',
          'archive',
          'score',
        ].take(['save', 'archive', 'score'].indexOf(stage) + 1).toList(),
      );
      final saved = (await storage.loadGame('123'))!;
      final restored = GameState.fromJson(saved.saveData);
      expect(
        inspectTerminalSave(restored),
        stage == 'save' ? isA<OrdinarySave>() : isA<TerminalCompletion>(),
      );
      expect((await scores.load()).completed.universalLosses, 0);
      expect(
        await storage.listArchiveIds(),
        stage == 'score' ? hasLength(1) : isEmpty,
      );
    });
  }

  test(
    'delete failure leaves receipt and archive; retry does not account again',
    () async {
      storage.failStage = 'delete';
      await expectLater(finish(), throwsStateError);
      expect(await storage.loadGame('123'), isNotNull);
      expect(await storage.listArchiveIds(), hasLength(1));
      final book = (await scores.load()).toJson();
      storage.failStage = null;
      await finish();
      expect((await scores.load()).toJson(), book);
      expect(await storage.loadGame('123'), isNull);
    },
  );

  test(
    'lost score acknowledgement preserves save and retry reuses committed receipt',
    () async {
      storage.loseScoreAcknowledgement = true;
      await expectLater(finish(), throwsStateError);
      expect(storage.operations, ['save', 'archive', 'score']);
      expect(await storage.loadGame('123'), isNotNull);
      final book = (await scores.load()).toJson();
      storage.loseScoreAcknowledgement = false;
      await finish();
      expect((await scores.load()).toJson(), book);
    },
  );

  test(
    'score comes from saved terminal snapshot despite later live mutation',
    () async {
      storage.afterArchive = () => state.stats.recruits = 999;
      final result = await finish();
      expect(result.receipt.score.statRecruits, 2);
      expect((await scores.load()).completed.universalRecruits, 2);
    },
  );

  test(
    'load recovery uses persisted metadata before any gameplay repair and never resumes',
    () async {
      storage.failStage = 'score';
      await expectLater(finish(ending: Ending.prison), throwsStateError);
      final saved = (await storage.loadGame('123'))!;
      final terminalJson = state.playthroughEvents.last.toJson();
      storage.failStage = null;
      await storage.close();
      await storage.init();
      for (int attempt = 0; attempt < 2; attempt++) {
        CampaignFinalizationResult? recovered;
        await expectLater(
          loadGameFromSave(
            saved,
            repair: (_) =>
                fail('Terminal recovery must precede gameplay repair'),
            recoveryError: (error) async =>
                fail('Unexpected recovery failure: $error'),
            terminalRecovery: (loaded, id) async {
              recovered = await recoverCampaignCompletion(
                state: loaded,
                saveGameId: id,
                storage: storage,
                scores: scores,
              );
            },
          ),
          throwsA(isA<EndGameException>()),
        );
        expect(recovered!.archive.events.last.toJson(), terminalJson);
        expect(recovered!.receipt.score.endType, Ending.prison);
        expect(recovered!.receipt.completionId, terminalJson['archiveId']);
        expect(gameState.playthroughSequence, 9);
        expect((await scores.load()).completed.universalLosses, 1);
        expect((await scores.load()).completed.scoreList, hasLength(1));
      }
    },
  );

  test(
    'invalid marker blocks load, reports error and preserves durable save',
    () async {
      storage.failStage = 'score';
      await expectLater(finish(), throwsStateError);
      final saved = (await storage.loadGame('123'))!;
      final events = saved.saveData['playthroughEvents'] as List;
      (events.last as Map).remove('presentationEnding');
      await storage.saveGame(saved);
      storage.operations.clear();
      Object? reported;
      await expectLater(
        loadGameFromSave(
          saved,
          repair: (_) => fail('Invalid terminal save repaired'),
          terminalRecovery: (_, __) async =>
              fail('Invalid terminal save finalized'),
          recoveryError: (error) async {
            reported = error;
          },
        ),
        throwsA(isA<EndGameException>()),
      );
      expect(reported, isNotNull);
      expect(storage.operations, isEmpty);
      expect(await storage.loadGame('123'), isNotNull);
    },
  );

  test(
    'malformed serialized envelope also blocks load before gameplay repair',
    () async {
      final saved = SaveFile(
        version: '1.5.6',
        gameId: '123',
        lastPlayed: null,
        saveData: {
          'playthroughEvents': [
            {'type': 'campaign_ended', 'seq': 'broken'},
          ],
        },
      );
      Object? reported;
      await expectLater(
        loadGameFromSave(
          saved,
          repair: (_) => fail('Malformed terminal save repaired'),
          recoveryError: (error) async {
            reported = error;
          },
        ),
        throwsA(isA<EndGameException>()),
      );
      expect(reported, isNotNull);
      expect(storage.operations, isEmpty);
    },
  );

  test(
    'ordinary save follows existing repair and playable return path',
    () async {
      final saved = SaveFile(
        version: '1.5.0',
        gameId: '123',
        lastPlayed: null,
        saveData:
            jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
      );
      bool repaired = false;
      expect(
        await loadGameFromSave(
          saved,
          terminalRecovery: (_, __) async => fail('Ordinary save finalized'),
          repair: (version) {
            repaired = true;
            applyBugFixes(version);
          },
        ),
        isTrue,
      );
      expect(repaired, isTrue);
      expect(storage.operations, isEmpty);
      expect(gameState.cities, isNotEmpty);
    },
  );
}

class FinalizationStorage extends SembastStorage {
  FinalizationStorage(String path) : super(databasePath: path);
  final List<String> operations = [];
  String? failStage;
  bool loseScoreAcknowledgement = false;
  void Function()? afterArchive;
  void step(String name) {
    operations.add(name);
    if (failStage == name) throw StateError('Injected $name failure');
  }

  @override
  Future<void> saveGame(SaveFile save) async {
    step('save');
    await super.saveGame(save);
  }

  @override
  Future<ArchiveWriteResult> saveArchive(CampaignHistoryArchive archive) async {
    step('archive');
    final result = await super.saveArchive(archive);
    afterArchive?.call();
    return result;
  }

  @override
  Future<void> updateScoreBook(ScoreBook Function(ScoreBook?) update) async {
    step('score');
    await super.updateScoreBook(update);
    if (loseScoreAcknowledgement) {
      throw StateError('Lost score acknowledgement');
    }
  }

  @override
  Future<void> deleteGame(String id) async {
    step('delete');
    await super.deleteGame(id);
  }
}
