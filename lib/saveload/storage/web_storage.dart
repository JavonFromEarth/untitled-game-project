import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:idb_shim/idb_browser.dart';
import 'package:lcs_new_age/playthrough_log/campaign_history_archive.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/saveload/storage/game_storage.dart';
import 'package:lcs_new_age/scores/score_book.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// IndexedDB database with separate stores for playable saves and completed archives.
class WebStorage implements GameStorage {
  WebStorage({this.databaseName = _dbName});

  final String databaseName;
  static const String _dbName = 'lcs_new_age';
  static const String _storeName = 'saves';
  static const String _archiveStoreName = 'campaignArchives';
  static const String _scoreStoreName = 'scores';
  static const int _version = 3;

  Database? _db;

  Database get _database => _db!;

  @override
  Future<ScoreBook?> loadScoreBook() async {
    final txn = _database.transaction(_scoreStoreName, idbModeReadOnly);
    final raw = await txn.objectStore(_scoreStoreName).getObject('book');
    await txn.completed;
    return raw == null
        ? null
        : ScoreBook.fromJson(jsonDecode(raw as String) as Map<String, dynamic>);
  }

  @override
  Future<void> updateScoreBook(
    ScoreBook Function(ScoreBook? existing) update,
  ) async {
    final txn = _database.transaction(_scoreStoreName, idbModeReadWrite);
    final store = txn.objectStore(_scoreStoreName);
    try {
      final raw = await store.getObject('book');
      final book = raw == null
          ? null
          : ScoreBook.fromJson(
              jsonDecode(raw as String) as Map<String, dynamic>,
            );
      await store.put(jsonEncode(update(book).toJson()), 'book');
    } catch (_) {
      txn.abort();
      try {
        await txn.completed;
      } catch (_) {
        // Preserve the original parse, conflict or write error.
      }
      rethrow;
    }
    await txn.completed;
  }

  @override
  Future<void> init() async {
    final idbFactory = getIdbFactory()!;
    _db = await idbFactory.open(
      databaseName,
      version: _version,
      onUpgradeNeeded: (event) {
        final Database db = event.database;
        if (!db.objectStoreNames.contains(_storeName)) {
          db.createObjectStore(_storeName);
        }
        if (!db.objectStoreNames.contains(_archiveStoreName)) {
          db.createObjectStore(_archiveStoreName);
        }
        if (!db.objectStoreNames.contains(_scoreStoreName)) {
          db.createObjectStore(_scoreStoreName);
        }
      },
    );
    _database.onVersionChange.listen((_) => _db?.close());
  }

  @override
  Future<void> saveGame(SaveFile saveFile) async {
    final txn = _database.transaction(_storeName, idbModeReadWrite);
    final store = txn.objectStore(_storeName);
    await store.put(jsonEncode(saveFile.toJson()), saveFile.gameId);
    await txn.completed;
  }

  @override
  Future<SaveFile?> loadGame(String gameId) async {
    final txn = _database.transaction(_storeName, idbModeReadOnly);
    final store = txn.objectStore(_storeName);
    final dynamic data = await store.getObject(gameId);
    if (data == null) return null;

    try {
      return SaveFile.fromJson(
        jsonDecode(data as String) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('Error loading save game $gameId: $e');
      return null;
    }
  }

  @override
  Future<List<String>> listGameIds() async {
    final txn = _database.transaction(_storeName, idbModeReadOnly);
    final store = txn.objectStore(_storeName);
    final keys = await store.getAllKeys();
    return keys.map((k) => k.toString()).toList();
  }

  @override
  Future<void> deleteGame(String gameId) async {
    final txn = _database.transaction(_storeName, idbModeReadWrite);
    final store = txn.objectStore(_storeName);
    await store.delete(gameId);
    await txn.completed;
  }

  @override
  Future<ArchiveWriteResult> saveArchive(CampaignHistoryArchive archive) async {
    final serialized = jsonEncode(archive.toJson());
    final txn = _database.transaction(_archiveStoreName, idbModeReadWrite);
    final store = txn.objectStore(_archiveStoreName);
    final existing = await store.getObject(archive.archiveId);
    if (existing != null) {
      await txn.completed;
      verifyExistingArchive(existing as String, archive);
      return ArchiveWriteResult.alreadyExists;
    }
    // add (not put) also enforces insert-only behavior at the database boundary.
    await store.add(serialized, archive.archiveId);
    await txn.completed;
    return ArchiveWriteResult.created;
  }

  @override
  Future<CampaignHistoryArchive?> loadArchive(String archiveId) async {
    final txn = _database.transaction(_archiveStoreName, idbModeReadOnly);
    final data = await txn.objectStore(_archiveStoreName).getObject(archiveId);
    await txn.completed;
    if (data == null) return null;
    return CampaignHistoryArchive.fromJson(
      jsonDecode(data as String) as Map<String, dynamic>,
    );
  }

  @override
  Future<List<String>> listArchiveIds() async {
    final txn = _database.transaction(_archiveStoreName, idbModeReadOnly);
    final keys = await txn.objectStore(_archiveStoreName).getAllKeys();
    await txn.completed;
    return keys.cast<String>();
  }

  @override
  Future<void> close() async {
    _db?.close();
    _db = null;
  }

  @override
  Future<void> updateLastGameId(String gameId) async {
    final int? id = int.tryParse(gameId);
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastGameId', id);
  }
}
