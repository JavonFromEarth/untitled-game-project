import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:lcs_new_age/playthrough_log/campaign_history_archive.dart';
import 'package:lcs_new_age/saveload/save_load.dart';

enum ArchiveWriteResult { created, alreadyExists }

class CampaignArchiveConflict implements Exception {
  CampaignArchiveConflict(this.archiveId);
  final String archiveId;

  @override
  String toString() =>
      'Campaign archive $archiveId already has different contents';
}

/// Compare complete JSON values, ignoring object key order, never list order.
void verifyExistingArchive(String storedJson, CampaignHistoryArchive archive) {
  if (!const DeepCollectionEquality().equals(
    jsonDecode(storedJson),
    archive.toJson(),
  )) {
    throw CampaignArchiveConflict(archive.archiveId);
  }
}

abstract class GameStorage {
  /// Insert only. An identical retry succeeds; different contents conflict.
  Future<ArchiveWriteResult> saveArchive(CampaignHistoryArchive archive);

  Future<CampaignHistoryArchive?> loadArchive(String archiveId);

  Future<List<String>> listArchiveIds();

  /// Initialize the storage system
  Future<void> init();

  /// Save a game file
  Future<void> saveGame(SaveFile saveFile);

  /// Load a game file by ID
  Future<SaveFile?> loadGame(String gameId);

  /// List all available game IDs
  Future<List<String>> listGameIds();

  /// Delete a game by ID
  Future<void> deleteGame(String gameId);

  /// Close any open connections/resources
  Future<void> close();

  /// Update the last played game ID
  Future<void> updateLastGameId(String gameId);
}
