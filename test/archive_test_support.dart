import 'package:lcs_new_age/playthrough_log/campaign_history_archive.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';

List<PlaythroughEvent> archiveEvents() => [
  PlaythroughEvent(
    gameId: 123,
    sequence: 1,
    realTime: DateTime.utc(2026, 9, 12),
    gameDate: DateTime(2023, 1, 1),
    type: PlaythroughEventType.campaignFounded,
    data: {'founderId': 42, 'founderName': 'Founder'},
  ),
  PlaythroughEvent(
    gameId: 123,
    sequence: 8,
    realTime: DateTime.utc(2026, 9, 12, 1),
    gameDate: DateTime(2023, 2, 1),
    type: PlaythroughEventType.leadershipSucceeded,
    data: {
      'previousLeaderId': 42,
      'newLeaderId': 43,
      'reason': 'death', // Legacy payloads must remain intact.
      'nested': {
        'names': ['Founder', 'Successor'],
      },
    },
  ),
];

CampaignHistoryArchive exampleArchive({
  String archiveId = 'completion-123',
  int finalSequence = 8,
  List<PlaythroughEvent>? events,
  Map<String, dynamic> context = const {},
}) => CampaignHistoryArchive(
  archiveId: archiveId,
  gameId: 123,
  finalGameDate: DateTime(2023, 2, 2),
  completedAt: DateTime.utc(2026, 9, 12, 2),
  finalSequence: finalSequence,
  outcome: CampaignOutcome.defeat,
  route: CampaignEndRoute.noQualifyingMembers,
  terminalContext: context,
  events: events ?? archiveEvents(),
);
