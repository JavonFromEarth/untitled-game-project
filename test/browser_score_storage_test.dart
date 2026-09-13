@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_browser.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/saveload/storage/web_storage.dart';
import 'package:lcs_new_age/scores/score_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'archive_test_support.dart';
import 'score_storage_contract.dart';
import 'score_test_support.dart';

void main() {
  late String databaseName;
  int counter = 0;
  setUp(() {
    databaseName =
        'lcs_scores_${DateTime.now().microsecondsSinceEpoch}_${counter++}';
    addTearDown(() => getIdbFactory()!.deleteDatabase(databaseName));
  });
  group('browser score contract', () {
    scoreStorageContract(() async {
      final storage = WebStorage(databaseName: databaseName);
      await storage.init();
      return storage;
    });
  });

  test(
    'version 2 upgrade preserves active saves and archives while adding scores',
    () async {
      final factory = getIdbFactory()!;
      final old = await factory.open(
        databaseName,
        version: 2,
        onUpgradeNeeded: (event) {
          event.database.createObjectStore('saves');
          event.database.createObjectStore('campaignArchives');
        },
      );
      final save = SaveFile(
        version: '1.5.6',
        gameId: '123',
        saveData: {'untouched': true},
        lastPlayed: null,
      );
      final archive = exampleArchive();
      final txn = old.transaction([
        'saves',
        'campaignArchives',
      ], idbModeReadWrite);
      await txn.objectStore('saves').put(jsonEncode(save.toJson()), '123');
      await txn
          .objectStore('campaignArchives')
          .put(jsonEncode(archive.toJson()), archive.archiveId);
      await txn.completed;
      old.close();

      final storage = WebStorage(databaseName: databaseName);
      await storage.init();
      addTearDown(storage.close);
      SharedPreferences.setMockInitialValues({});
      final repository = ScoreRepository(storage);
      await repository.initialize(await SharedPreferences.getInstance());
      await repository.record(exampleReceipt());
      expect((await storage.loadGame('123'))!.toJson(), save.toJson());
      expect(
        (await storage.loadArchive(archive.archiveId))!.toJson(),
        archive.toJson(),
      );
      expect(await storage.listGameIds(), ['123']);
      expect(await storage.listArchiveIds(), [archive.archiveId]);
      await storage.deleteGame('123');
      expect((await repository.load()).receipt('completion-123'), isNotNull);
    },
  );
}
