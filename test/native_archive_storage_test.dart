@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/saveload/storage/sembast_storage.dart';

import 'archive_storage_contract.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lcs_archive_test_');
    addTearDown(() => directory.delete(recursive: true));
  });
  archiveStorageContract(() async {
    final storage = SembastStorage(databasePath: '${directory.path}/game.db');
    await storage.init();
    return storage;
  });
}
