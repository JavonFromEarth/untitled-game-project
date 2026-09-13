import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/playthrough_log/campaign_history_archive.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/saveload/storage/game_storage.dart';
import 'package:lcs_new_age/scores/score_book.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Native database with separate stores for playable saves and completed archives.
class SembastStorage implements GameStorage {
  SembastStorage({this.databasePath});

  /// Optional location for isolated databases, including storage tests.
  final String? databasePath;
  static const String _dbName = 'lcs_new_age.db';
  static const String _storeName = 'saves';
  static const int _version = 1;

  Database? _db;
  final _store = stringMapStoreFactory.store(_storeName);
  final _archives = stringMapStoreFactory.store('campaignArchives');
  final _scores = stringMapStoreFactory.store('scores').record('book');

  Database get _database => _db!;

  @override
  Future<ScoreBook?> loadScoreBook() async {
    final record = await _scores.get(_database);
    return record == null
        ? null
        : ScoreBook.fromJson(
            jsonDecode(record['data']! as String) as Map<String, dynamic>,
          );
  }

  @override
  Future<void> updateScoreBook(
    ScoreBook Function(ScoreBook? existing) update,
  ) async {
    await _database.transaction((txn) async {
      final record = await _scores.get(txn);
      final book = record == null
          ? null
          : ScoreBook.fromJson(
              jsonDecode(record['data']! as String) as Map<String, dynamic>,
            );
      await _scores.put(txn, {'data': jsonEncode(update(book).toJson())});
    });
  }

  @override
  Future<void> init() async {
    final dbPath =
        databasePath ?? join((await _getAppDataDirectory()).path, _dbName);
    _db = await databaseFactoryIo.openDatabase(dbPath, version: _version);
  }

  Future<Directory> _getAppDataDirectory() async {
    final appData = Platform.environment['APPDATA'];
    if (Platform.isWindows && appData != null) {
      final appDir = Directory(join(appData, 'LCS New Age', 'lcs_new_age'));
      if (!appDir.existsSync()) {
        await appDir.create(recursive: true);
      }
      return appDir;
    } else {
      // Fallback to documents directory for non-Windows platforms (and for
      // Windows if APPDATA is somehow unset, rather than crashing).
      return await getApplicationDocumentsDirectory();
    }
  }

  @override
  Future<void> saveGame(SaveFile saveFile) async {
    await _store.record(saveFile.gameId).put(_database, {
      'data': jsonEncode(saveFile.toJson()),
      'lastPlayed': saveFile.lastPlayed?.toIso8601String(),
    });
  }

  @override
  Future<SaveFile?> loadGame(String gameId) async {
    final record = await _store.record(gameId).get(_database);
    if (record == null) return null;

    try {
      final data = jsonDecode(record['data']! as String);
      return SaveFile.fromJson(data as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Error loading save game $gameId: $e');
      return null;
    }
  }

  @override
  Future<List<String>> listGameIds() async {
    return _store.findKeys(_database);
  }

  @override
  Future<void> deleteGame(String gameId) async {
    await _store.record(gameId).delete(_database);
  }

  @override
  Future<ArchiveWriteResult> saveArchive(CampaignHistoryArchive archive) async {
    final serialized = jsonEncode(archive.toJson());
    return _database.transaction((txn) async {
      final record = _archives.record(archive.archiveId);
      final existing = await record.get(txn);
      if (existing != null) {
        verifyExistingArchive(existing['data']! as String, archive);
        return ArchiveWriteResult.alreadyExists;
      }
      await record.put(txn, {'data': serialized});
      return ArchiveWriteResult.created;
    });
  }

  @override
  Future<CampaignHistoryArchive?> loadArchive(String archiveId) async {
    final record = await _archives.record(archiveId).get(_database);
    if (record == null) return null;
    return CampaignHistoryArchive.fromJson(
      jsonDecode(record['data']! as String) as Map<String, dynamic>,
    );
  }

  @override
  Future<List<String>> listArchiveIds() => _archives.findKeys(_database);

  @override
  Future<void> close() async {
    await _db?.close();
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
