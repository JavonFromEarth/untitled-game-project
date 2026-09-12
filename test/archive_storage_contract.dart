import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/playthrough_log/campaign_history_archive.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/saveload/storage/game_storage.dart';

import 'archive_test_support.dart';

/// Runs unchanged against real native and browser backends.
void archiveStorageContract(Future<GameStorage> Function() openStorage) {
  late GameStorage storage;
  final save = SaveFile(
    version: '1.5.0',
    gameId: 'completion-123',
    saveData: {'untouched': true},
    lastPlayed: DateTime.utc(2026, 9, 12),
  );
  setUp(() async {
    storage = await openStorage();
  });
  tearDown(() async {
    await storage.close();
  });

  test(
    'archive survives reopening and stays separate from active saves',
    () async {
      final archive = exampleArchive();
      await storage.saveGame(save);
      expect(await storage.saveArchive(archive), ArchiveWriteResult.created);
      await storage.close();
      storage = await openStorage();
      expect(await storage.listGameIds(), [save.gameId]);
      expect(await storage.listArchiveIds(), [archive.archiveId]);
      expect((await storage.loadGame(save.gameId))!.toJson(), save.toJson());
      final restored = (await storage.loadArchive(archive.archiveId))!;
      expect(
        restored.events.map((e) => e.toJson()),
        archive.events.map((e) => e.toJson()),
      );
      expect(restored.finalSequence, 8);
      expect(restored.toJson(), archive.toJson());
      // Same key in both stores: deletion must affect only the playable save.
      await storage.deleteGame(save.gameId);
      expect(await storage.listGameIds(), isEmpty);
      expect(
        (await storage.loadArchive(archive.archiveId))!.toJson(),
        archive.toJson(),
      );
      expect(await storage.loadArchive('absent'), isNull);
    },
  );

  test(
    'identical retries, including reordered JSON keys, are idempotent',
    () async {
      final archive = exampleArchive();
      expect(await storage.saveArchive(archive), ArchiveWriteResult.created);
      final json = archive.toJson();
      final reordered = CampaignHistoryArchive.fromJson(
        Map.fromEntries(json.entries.toList().reversed),
      );
      expect(
        await storage.saveArchive(reordered),
        ArchiveWriteResult.alreadyExists,
      );
      expect(await storage.listArchiveIds(), [archive.archiveId]);
    },
  );

  test('conflicting retry preserves archive and active save', () async {
    final archive = exampleArchive();
    await storage.saveGame(save);
    await storage.saveArchive(archive);
    await expectLater(
      storage.saveArchive(exampleArchive(finalSequence: 9)),
      throwsA(isA<CampaignArchiveConflict>()),
    );
    expect(
      (await storage.loadArchive(archive.archiveId))!.toJson(),
      archive.toJson(),
    );
    expect((await storage.loadGame(save.gameId))!.toJson(), save.toJson());
  });

  test('concurrent identical writes create exactly one archive', () async {
    final results = await Future.wait([
      storage.saveArchive(exampleArchive()),
      storage.saveArchive(exampleArchive()),
    ]);
    expect(
      results,
      unorderedEquals([
        ArchiveWriteResult.created,
        ArchiveWriteResult.alreadyExists,
      ]),
    );
  });

  test('concurrent conflicting writes never overwrite the winner', () async {
    final first = exampleArchive();
    final second = exampleArchive(finalSequence: 9);
    Future<Object> attempt(CampaignHistoryArchive archive) async {
      try {
        return await storage.saveArchive(archive);
      } on CampaignArchiveConflict catch (error) {
        return error;
      }
    }

    final results = await Future.wait([attempt(first), attempt(second)]);
    expect(results.whereType<ArchiveWriteResult>(), [
      ArchiveWriteResult.created,
    ]);
    expect(results.whereType<CampaignArchiveConflict>(), hasLength(1));
    final winner = results[0] is ArchiveWriteResult ? first : second;
    expect(
      (await storage.loadArchive(first.archiveId))!.toJson(),
      winner.toJson(),
    );
  });

  test(
    'mutating source or returned JSON cannot corrupt stored archive',
    () async {
      final json = exampleArchive().toJson();
      final archive = CampaignHistoryArchive.fromJson(json);
      await storage.saveArchive(archive);
      final event = (json['events'] as List)[1] as Map<String, dynamic>;
      final nested = event['nested'] as Map<String, dynamic>;
      (nested['names'] as List).clear();
      final loaded = (await storage.loadArchive(archive.archiveId))!;
      (loaded.toJson()['events'] as List).clear();
      expect(
        (await storage.loadArchive(archive.archiveId))!.toJson(),
        archive.toJson(),
      );
    },
  );

  test(
    'unavailable database write leaves durable active save untouched',
    () async {
      await storage.saveGame(save);
      await storage.close();
      await expectLater(
        storage.saveArchive(exampleArchive()),
        throwsA(anything),
      );
      storage = await openStorage();
      expect((await storage.loadGame(save.gameId))!.toJson(), save.toJson());
      expect(await storage.listArchiveIds(), isEmpty);
    },
  );
}
