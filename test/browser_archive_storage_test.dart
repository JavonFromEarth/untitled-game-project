@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_browser.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/saveload/storage/web_storage.dart';

import 'archive_storage_contract.dart';
import 'archive_test_support.dart';

void main() {
  late String databaseName;
  var nextDatabase = 0;
  setUp(() {
    databaseName =
        'lcs_archive_test_${DateTime.now().microsecondsSinceEpoch}_${nextDatabase++}';
    addTearDown(() => getIdbFactory()!.deleteDatabase(databaseName));
  });
  group('archive storage', () {
    archiveStorageContract(() async {
      final storage = WebStorage(databaseName: databaseName);
      await storage.init();
      return storage;
    });
  });

  test('version 1 database upgrades without altering playable saves', () async {
    final factory = getIdbFactory()!;
    final legacy = await factory.open(
      databaseName,
      version: 1,
      onUpgradeNeeded: (event) {
        event.database.createObjectStore('saves');
      },
    );
    final save = SaveFile(
      version: '1.5.0',
      gameId: '123',
      saveData: {'legacy': true},
      lastPlayed: null,
    );
    final txn = legacy.transaction('saves', idbModeReadWrite);
    await txn.objectStore('saves').put(jsonEncode(save.toJson()), save.gameId);
    await txn.completed;
    legacy.close();

    final storage = WebStorage(databaseName: databaseName);
    await storage.init();
    addTearDown(storage.close);
    expect((await storage.loadGame('123'))!.toJson(), save.toJson());
    expect(await storage.listGameIds(), ['123']);
    expect(await storage.listArchiveIds(), isEmpty);
    await storage.saveArchive(exampleArchive());
    expect((await storage.loadGame('123'))!.toJson(), save.toJson());
  });
}
