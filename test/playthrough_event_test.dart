import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';

void main() {
  test('PlaythroughEvent survives JSON round trip', () {
    final original = PlaythroughEvent(
      gameId: 123,
      sequence: 7,
      realTime: DateTime.parse('2026-09-11T00:30:00.000'),
      gameDate: DateTime(2026, 6, 15),
      type: PlaythroughEventType.recruitJoined,
      data: {
        'recruitId': 42,
        'recruitName': 'Test Recruit',
        'sleeperAgent': false,
      },
    );

    final json = original.toJson();
    expect(json['type'], 'recruit_joined');
    final restored = PlaythroughEvent.fromJson(json);

    expect(restored.gameId, original.gameId);
    expect(restored.sequence, original.sequence);
    expect(restored.realTime, original.realTime);
    expect(restored.gameDate, original.gameDate);
    expect(restored.type, original.type);
    expect(restored.data, original.data);
  });

  test('sleeperReportedIn uses stable wire name', () {
    expect(
      PlaythroughEventType.sleeperReportedIn.wireName,
      'sleeper_reported_in',
    );

    expect(
      PlaythroughEventType.fromWireName('sleeper_reported_in'),
      PlaythroughEventType.sleeperReportedIn,
    );
  });

  test('campaignFounded uses stable wire name', () {
    expect(PlaythroughEventType.campaignFounded.wireName, 'campaign_founded');

    expect(
      PlaythroughEventType.fromWireName('campaign_founded'),
      PlaythroughEventType.campaignFounded,
    );
  });
}
