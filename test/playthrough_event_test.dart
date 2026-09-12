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

  test('memberJoined uses stable wire name', () {
    expect(PlaythroughEventType.memberJoined.wireName, 'member_joined');

    expect(
      PlaythroughEventType.fromWireName('member_joined'),
      PlaythroughEventType.memberJoined,
    );
  });
  test('leadershipSucceeded uses stable wire name', () {
    expect(
      PlaythroughEventType.leadershipSucceeded.wireName,
      'leadership_succeeded',
    );

    expect(
      PlaythroughEventType.fromWireName('leadership_succeeded'),
      PlaythroughEventType.leadershipSucceeded,
    );
  });

  test('leadershipSucceeded round trip does not add a reason', () {
    final original = PlaythroughEvent(
      gameId: 123,
      sequence: 8,
      realTime: DateTime.parse('2026-09-11T00:30:00.000'),
      gameDate: DateTime(2026, 6, 15),
      type: PlaythroughEventType.leadershipSucceeded,
      data: {
        'previousLeaderId': 42,
        'previousLeaderName': 'Previous Leader',
        'newLeaderId': 43,
        'newLeaderName': 'New Leader',
      },
    );

    final json = original.toJson();
    expect(json['type'], 'leadership_succeeded');
    expect(json.containsKey('reason'), isFalse);

    final restored = PlaythroughEvent.fromJson(json);
    expect(restored.type, PlaythroughEventType.leadershipSucceeded);
    expect(restored.data, original.data);
    expect(restored.data.containsKey('reason'), isFalse);
    expect(restored.toJson(), json);
    expect(restored.toJson().containsKey('reason'), isFalse);
  });

  test('legacy leadershipSucceeded round trip preserves death reason', () {
    final json = <String, dynamic>{
      'gameId': 123,
      'seq': 8,
      'realTime': '2026-09-11T00:30:00.000',
      'gameDate': '2026-06-15T00:00:00.000',
      'type': 'leadership_succeeded',
      'previousLeaderId': 42,
      'previousLeaderName': 'Previous Leader',
      'newLeaderId': 43,
      'newLeaderName': 'New Leader',
      'reason': 'death',
    };

    final restored = PlaythroughEvent.fromJson(json);
    expect(restored.type, PlaythroughEventType.leadershipSucceeded);
    expect(restored.data['reason'], 'death');
    expect(restored.toJson(), json);
  });
}
