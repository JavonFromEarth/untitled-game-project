import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/playthrough_log/campaign_history_archive.dart';

import 'archive_test_support.dart';

void main() {
  test('archive round trip preserves complete event history and metadata', () {
    final archive = exampleArchive();
    final restored = CampaignHistoryArchive.fromJson(
      jsonDecode(jsonEncode(archive.toJson())) as Map<String, dynamic>,
    );
    expect(restored.schemaVersion, 1);
    expect(restored.archiveId, 'completion-123');
    expect(restored.gameId, 123);
    expect(restored.finalGameDate, DateTime(2023, 2, 2));
    expect(restored.completedAt, DateTime.utc(2026, 9, 12, 2));
    expect(restored.finalSequence, 8);
    expect(restored.outcome, CampaignOutcome.defeat);
    expect(restored.route, CampaignEndRoute.noQualifyingMembers);
    expect(restored.events, hasLength(2));
    expect(
      restored.events.map((e) => e.toJson()),
      archiveEvents().map((e) => e.toJson()),
    );
    expect(restored.toJson(), archive.toJson());
    expect(restored.toJson()['terminalResult'], {
      'outcome': 'defeat',
      'route': 'no_qualifying_members',
      'context': {},
    });
  });

  test('terminal classifications have stable string wire names', () {
    expect(CampaignOutcome.values.map((v) => v.wireName), [
      'victory',
      'defeat',
    ]);
    expect(CampaignEndRoute.values.map((v) => v.wireName), [
      'victory_conditions',
      'no_qualifying_members',
      'constitution_repealed',
      'prolonged_disbanding',
    ]);
  });

  test(
    'archive detaches GameState history, nested payloads and terminal context',
    () {
      final state = GameState()..playthroughEvents = archiveEvents();
      final context = <String, dynamic>{
        'details': ['original'],
      };
      final archive = exampleArchive(
        events: state.playthroughEvents,
        context: context,
      );
      final expected = archive.toJson();
      final nested =
          state.playthroughEvents.last.data['nested'] as Map<String, dynamic>;
      (nested['names'] as List)[0] = 'changed';
      state.playthroughEvents.first.data.clear();
      state.playthroughEvents.clear();
      (context['details'] as List).clear();
      expect(archive.toJson(), expected);
    },
  );

  test(
    'input and exported JSON cannot mutate an archive; exposed data is frozen',
    () {
      final source = exampleArchive().toJson();
      final archive = CampaignHistoryArchive.fromJson(source);
      final expected = archive.toJson();
      final sourceEvent = (source['events'] as List)[1] as Map<String, dynamic>;
      final nested = sourceEvent['nested'] as Map<String, dynamic>;
      (nested['names'] as List).clear();
      (source['terminalResult'] as Map<String, dynamic>)['outcome'] = 'victory';
      final exported = archive.toJson();
      (exported['events'] as List).clear();
      expect(archive.toJson(), expected);
      expect(() => archive.events.clear(), throwsUnsupportedError);
      expect(
        () => archive.events.last.data['reason'] = 'changed',
        throwsUnsupportedError,
      );
      final frozenNested =
          archive.events.last.data['nested'] as Map<String, dynamic>;
      expect(
        () => (frozenNested['names'] as List).clear(),
        throwsUnsupportedError,
      );
      expect(
        () =>
            (archive.terminalResult['context'] as Map<String, dynamic>)['new'] =
                1,
        throwsUnsupportedError,
      );
    },
  );

  test(
    'additional fields survive; unsupported schemas and unknown classifications fail explicitly',
    () {
      final json = exampleArchive().toJson()
        ..['extension'] = {'note': 'retain'};
      expect(CampaignHistoryArchive.fromJson(json).toJson(), json);
      json['schemaVersion'] = 2;
      expect(
        () => CampaignHistoryArchive.fromJson(json),
        throwsFormatException,
      );
      json['schemaVersion'] = 1.0;
      expect(
        () => CampaignHistoryArchive.fromJson(json),
        throwsFormatException,
      );
      json['schemaVersion'] = 1;
      final terminal = json['terminalResult'] as Map<String, dynamic>;
      terminal['route'] = 'future_route';
      expect(
        () => CampaignHistoryArchive.fromJson(json),
        throwsFormatException,
      );
      terminal['route'] = 'no_qualifying_members';
      ((json['events'] as List)[0] as Map<String, dynamic>)['type'] =
          'future_event';
      expect(
        () => CampaignHistoryArchive.fromJson(json),
        throwsFormatException,
      );
    },
  );

  test(
    'old campaigns may have empty histories; inconsistent data is rejected',
    () {
      expect(exampleArchive(events: [], finalSequence: 0).events, isEmpty);
      for (final key in ['archiveId', 'gameId', 'events', 'terminalResult']) {
        final json = exampleArchive().toJson()..remove(key);
        expect(
          () => CampaignHistoryArchive.fromJson(json),
          throwsFormatException,
        );
      }
      expect(() => exampleArchive(archiveId: ''), throwsFormatException);
      expect(() => exampleArchive(finalSequence: 1), throwsFormatException);
      final json = exampleArchive().toJson();
      ((json['events'] as List)[0] as Map<String, dynamic>)['gameId'] = 999;
      expect(
        () => CampaignHistoryArchive.fromJson(json),
        throwsFormatException,
      );
    },
  );
}
