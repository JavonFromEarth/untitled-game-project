@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/playthrough_log/campaign_completion.dart';
import 'package:lcs_new_age/playthrough_log/campaign_history_archive.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/saveload/storage/game_storage.dart';
import 'package:lcs_new_age/saveload/storage/sembast_storage.dart';
import 'package:lcs_new_age/title_screen/game_over.dart';

import 'archive_test_support.dart';
import 'test_support.dart';

void main() {
  setUpAll(ensureGameDataLoaded);
  late RecordingStorage storage;
  late GameState state;
  setUp(() async {
    final directory = await Directory.systemTemp.createTemp('lcs_completion_');
    addTearDown(() => directory.delete(recursive: true));
    storage = RecordingStorage('${directory.path}/game.db');
    await storage.init();
    addTearDown(storage.close);
    final raw =
        jsonDecode(await File('test/saves/moe_1_5.json').readAsString())
            as Map<String, dynamic>;
    gameState = state = GameState.fromJson(SaveFile.fromJson(raw).saveData)
      ..uniqueGameId = 123
      ..date = DateTime(2023, 2, 2)
      ..playthroughEvents = archiveEvents()
      ..playthroughSequence = 8;
  });
  tearDown(() => expect(storage.deleteCalls, 0));

  Future<CampaignHistoryArchive> prepare({
    CampaignOutcome outcome = CampaignOutcome.defeat,
    CampaignEndRoute route = CampaignEndRoute.noQualifyingMembers,
    Ending presentationEnding = Ending.policeSiege,
    Map<String, dynamic> context = const {},
  }) => prepareCampaignCompletion(
    state: state,
    storage: storage,
    outcome: outcome,
    route: route,
    presentationEnding: presentationEnding,
    terminalContext: context,
  );

  Future<GameState> reload() async {
    final save = (await storage.loadGame('123'))!;
    return gameState = state = GameState.fromJson(save.saveData);
  }

  test(
    'first preparation saves terminal history then matching archive',
    () async {
      final archive = await prepare(
        context: {
          'details': ['resolved'],
        },
      );
      expect(storage.operations, ['save', 'archive']);
      expect(storage.archiveResults, [ArchiveWriteResult.created]);
      expect(state.playthroughEvents, hasLength(3));
      final terminal = state.playthroughEvents.last;
      expect(terminal.type, PlaythroughEventType.campaignEnded);
      expect(terminal.data['presentationEnding'], 'police_siege');
      expect(terminal.sequence, 9);
      expect(state.playthroughSequence, 9);
      expect(archive.archiveId, terminal.data['archiveId']);
      expect(archive.archiveId, matches(r'^completion-[0-9a-f]{32}$'));
      expect(archive.finalSequence, terminal.sequence);
      expect(archive.finalGameDate, terminal.gameDate);
      expect(archive.completedAt, terminal.realTime);
      expect(archive.terminalResult, {
        'outcome': terminal.data['outcome'],
        'route': terminal.data['route'],
        'context': terminal.data['context'],
      });
      expect(archive.events.last.toJson(), terminal.toJson());
      final restored = await reload();
      expect(restored.playthroughSequence, archive.finalSequence);
      expect(
        restored.playthroughEvents.map((e) => e.toJson()),
        archive.events.map((e) => e.toJson()),
      );
      expect(
        (await storage.loadArchive(archive.archiveId))!.toJson(),
        archive.toJson(),
      );
      expect(await storage.listGameIds(), ['123']);
    },
  );

  test(
    'retry after reload reuses ID, time and sequence; identical archive succeeds',
    () async {
      final first = await prepare(context: {'a': 1, 'b': 2});
      await reload();
      final retry = await prepare(context: {'b': 2, 'a': 1});
      expect(retry.toJson(), first.toJson());
      expect(state.playthroughSequence, 9);
      expect(state.playthroughEvents, hasLength(3));
      expect(storage.archiveResults, [
        ArchiveWriteResult.created,
        ArchiveWriteResult.alreadyExists,
      ]);
    },
  );

  test(
    'outcome, route and nested context conflicts fail before persistence',
    () async {
      final first = await prepare(
        context: {
          'details': ['original'],
        },
      );
      storage.operations.clear();
      for (final request in [
        () => prepare(
          presentationEnding: Ending.executed,
          context: {
            'details': ['original'],
          },
        ),
        () => prepare(
          outcome: CampaignOutcome.victory,
          context: {
            'details': ['original'],
          },
        ),
        () => prepare(
          route: CampaignEndRoute.prolongedDisbanding,
          context: {
            'details': ['original'],
          },
        ),
        () => prepare(
          context: {
            'details': ['changed'],
          },
        ),
      ]) {
        await expectLater(
          request(),
          throwsA(isA<CampaignCompletionConflict>()),
        );
      }
      expect(storage.operations, isEmpty);
      expect(state.playthroughSequence, 9);
      expect(
        (await storage.loadArchive(first.archiveId))!.toJson(),
        first.toJson(),
      );
    },
  );

  test(
    'save failure prevents archival and retains in-memory retry identity',
    () async {
      final before =
          jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>;
      await storage.saveGame(
        SaveFile(
          version: '1.5.6',
          saveData: before,
          gameId: '123',
          lastPlayed: null,
        ),
      );
      storage.operations.clear();
      storage.failSave = true;
      await expectLater(prepare(), throwsStateError);
      final terminal = state.playthroughEvents.last;
      expect(storage.operations, ['save']);
      expect((await storage.loadGame('123'))!.saveData, before);
      expect(await storage.listArchiveIds(), isEmpty);
      storage.failSave = false;
      final retry = await prepare();
      expect(retry.archiveId, terminal.data['archiveId']);
      expect(state.playthroughSequence, 9);
    },
  );

  test(
    'archive failure leaves durable terminal save for retry after reopening',
    () async {
      storage.failArchive = true;
      await expectLater(prepare(), throwsStateError);
      final terminalJson = state.playthroughEvents.last.toJson();
      expect(storage.operations, ['save', 'archive']);
      await storage.close();
      await storage.init();
      await reload();
      expect(state.playthroughEvents.last.toJson(), terminalJson);
      expect(await storage.listArchiveIds(), isEmpty);
      storage.failArchive = false;
      final retry = await prepare();
      expect(retry.archiveId, terminalJson['archiveId']);
      expect(retry.finalSequence, 9);
      expect(await storage.listGameIds(), ['123']);
    },
  );

  test('lost archive acknowledgement is safely retried', () async {
    storage.failAfterArchive = true;
    await expectLater(prepare(), throwsStateError);
    final id = state.playthroughEvents.last.data['archiveId'] as String;
    expect(await storage.loadArchive(id), isNotNull);
    await reload();
    storage.failAfterArchive = false;
    expect((await prepare()).archiveId, id);
    expect(storage.archiveResults, [
      ArchiveWriteResult.created,
      ArchiveWriteResult.alreadyExists,
    ]);
  });

  test(
    'archive waits for saved JSON and ignores later live payload mutation',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      storage.beforeSave = () async {
        entered.complete();
        await release.future;
      };
      final context = <String, dynamic>{
        'details': ['original'],
      };
      final pending = prepare(context: context);
      await entered.future;
      expect(storage.operations, ['save']);
      expect(await storage.listArchiveIds(), isEmpty);
      (context['details'] as List).clear();
      state.playthroughEvents.first.data['founderName'] =
          'changed while saving';
      release.complete();
      final archive = await pending;
      expect(archive.events.first.data['founderName'], 'Founder');
      expect(archive.terminalResult['context'], {
        'details': ['original'],
      });
      final saved = (await storage.loadGame('123'))!;
      expect(saved.saveData['playthroughEvents'], archive.toJson()['events']);
    },
  );

  test('concurrent preparations on the same state append only once', () async {
    final results = await Future.wait([prepare(), prepare()]);
    expect(results[0].toJson(), results[1].toJson());
    expect(state.playthroughSequence, 9);
    expect(state.playthroughEvents, hasLength(3));
    expect(
      storage.archiveResults,
      containsAll([
        ArchiveWriteResult.created,
        ArchiveWriteResult.alreadyExists,
      ]),
    );
  });

  test('old state without history can be completed', () async {
    state.playthroughEvents.clear();
    state.playthroughSequence = 0;
    final archive = await prepare();
    expect(archive.events.single.type, PlaythroughEventType.campaignEnded);
    expect(archive.finalSequence, 1);
  });

  test('continued or duplicated terminal history is rejected', () async {
    await prepare();
    storage.operations.clear();
    state.playthroughEvents.add(state.playthroughEvents.last);
    await expectLater(prepare(), throwsA(isA<CampaignCompletionConflict>()));
    state.playthroughEvents.removeLast();
    state.playthroughSequence++;
    await expectLater(prepare(), throwsA(isA<CampaignCompletionConflict>()));
    state.playthroughSequence--;
    state.date = state.date.add(const Duration(days: 1));
    await expectLater(prepare(), throwsA(isA<CampaignCompletionConflict>()));
    expect(storage.operations, isEmpty);
  });
}

/// Exercise real durable storage, with failures and ordering visible to tests.
class RecordingStorage extends SembastStorage {
  RecordingStorage(String path) : super(databasePath: path);
  final List<String> operations = [];
  final List<ArchiveWriteResult> archiveResults = [];
  bool failSave = false;
  bool failArchive = false;
  bool failAfterArchive = false;
  int deleteCalls = 0;
  Future<void> Function()? beforeSave;

  @override
  Future<void> saveGame(SaveFile saveFile) async {
    operations.add('save');
    if (failSave) throw StateError('Injected save failure');
    await beforeSave?.call();
    await super.saveGame(saveFile);
  }

  @override
  Future<ArchiveWriteResult> saveArchive(CampaignHistoryArchive archive) async {
    operations.add('archive');
    final saved = (await super.loadGame(archive.gameId.toString()))!;
    expect(saved.saveData['playthroughEvents'], archive.toJson()['events']);
    expect(saved.saveData['playthroughSequence'], archive.finalSequence);
    if (failArchive) throw StateError('Injected archive failure');
    final result = await super.saveArchive(archive);
    archiveResults.add(result);
    if (failAfterArchive) throw StateError('Injected lost acknowledgement');
    return result;
  }

  @override
  Future<void> deleteGame(String gameId) async {
    deleteCalls++;
    throw StateError('Completion must never delete an active save');
  }
}
