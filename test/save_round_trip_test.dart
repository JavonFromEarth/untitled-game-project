import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';
import 'package:lcs_new_age/saveload/save_load.dart';

import 'test_support.dart';

/// Test #1: a load followed by a save must be a fixed point.
///
/// The existing save_load_test proves old saves *load*. This proves a
/// load -> save -> load cycle doesn't silently drop or mutate any field: the
/// failure mode where data survives `fromJson` but is lost or changed by
/// `toJson`, which would corrupt a player's game on their very next autosave.
void main() {
  setUpAll(ensureGameDataLoaded);

  const saveFixtures = <String>[
    'felix_1_0.json',
    'EQ_1_1.json',
    'ebony_1_2_9.json',
    'eevee_1_4_5.json',
    'moe_1_5.json',
  ];

  group('Save round-trip is stable', () {
    test('populated Campaign History survives GameState round trip', () async {
      final raw =
          jsonDecode(await File('test/saves/moe_1_5.json').readAsString())
              as Map<String, dynamic>;
      gameState = GameState.fromJson(SaveFile.fromJson(raw).saveData);
      final event = PlaythroughEvent(
        gameId: gameState.uniqueGameId,
        sequence: 8,
        realTime: DateTime.utc(2026, 9, 12, 1, 30),
        gameDate: DateTime(2026, 6, 15),
        type: PlaythroughEventType.leadershipSucceeded,
        data: {
          'previousLeaderId': 42,
          'previousLeaderName': 'Previous Leader',
          'newLeaderId': 43,
          'newLeaderName': 'New Leader',
        },
      );
      gameState.playthroughEvents = [event];
      gameState.playthroughSequence = 8;

      // Encode nested objects just as the save storage does before loading.
      final originalJson =
          jsonDecode(jsonEncode(gameState.toJson())) as Map<String, dynamic>;
      gameState = GameState.fromJson(originalJson);

      expect(gameState.playthroughEvents, hasLength(1));
      final restored = gameState.playthroughEvents.single;
      expect(restored.type, event.type);
      expect(restored.gameId, event.gameId);
      expect(restored.sequence, event.sequence);
      expect(restored.realTime, event.realTime);
      expect(restored.gameDate, event.gameDate);
      expect(restored.data, event.data);
      expect(gameState.playthroughSequence, 8);

      final restoredJson =
          jsonDecode(jsonEncode(gameState.toJson())) as Map<String, dynamic>;
      expect(
        restoredJson['playthroughEvents'],
        originalJson['playthroughEvents'],
      );
      expect(
        restoredJson['playthroughSequence'],
        originalJson['playthroughSequence'],
      );
    });

    for (final fileName in saveFixtures) {
      test('round-trips $fileName', () async {
        final Map<String, dynamic> raw =
            jsonDecode(await File('test/saves/$fileName').readAsString())
                as Map<String, dynamic>;
        final Map<String, dynamic> saveData = SaveFile.fromJson(raw).saveData;

        // Mirror autoSaveGame, which serializes the global gameState. Assigning
        // the global keeps any serialization that reads global getters
        // consistent across both passes.
        gameState = GameState.fromJson(saveData);
        final String json1 = jsonEncode(gameState.toJson());

        gameState = GameState.fromJson(
          jsonDecode(json1) as Map<String, dynamic>,
        );
        final String json2 = jsonEncode(gameState.toJson());

        expect(
          json2,
          equals(json1),
          reason:
              'A load/save cycle changed the serialized data for '
              '$fileName — a field is being dropped or mutated on save.',
        );
      });
    }
  });
}
