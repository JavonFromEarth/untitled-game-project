import 'dart:convert';

import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';

enum CampaignOutcome {
  victory('victory'),
  defeat('defeat');

  const CampaignOutcome(this.wireName);
  final String wireName;
}

/// Routes describe the terminal resolver, not individual members' fates.
enum CampaignEndRoute {
  victoryConditions('victory_conditions'),
  noQualifyingMembers('no_qualifying_members'),
  constitutionRepealed('constitution_repealed'),
  prolongedDisbanding('prolonged_disbanding');

  const CampaignEndRoute(this.wireName);
  final String wireName;
}

/// Immutable, detached JSON history. No live GameState or Creature references.
class CampaignHistoryArchive {
  factory CampaignHistoryArchive({
    required String archiveId,
    required int gameId,
    required DateTime finalGameDate,
    required DateTime completedAt,
    required int finalSequence,
    required CampaignOutcome outcome,
    required CampaignEndRoute route,
    Map<String, dynamic> terminalContext = const {},
    required List<PlaythroughEvent> events,
  }) => CampaignHistoryArchive.fromJson({
    'schemaVersion': currentSchemaVersion,
    'archiveId': archiveId,
    'gameId': gameId,
    'finalGameDate': finalGameDate.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'finalSequence': finalSequence,
    'terminalResult': {
      'outcome': outcome.wireName,
      'route': route.wireName,
      'context': terminalContext,
    },
    'events': events.map((event) => event.toJson()).toList(),
  });

  factory CampaignHistoryArchive.fromJson(Map<String, dynamic> json) {
    // JSON encoding detaches every nested value and rejects non-JSON payloads.
    final copy = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
    if (copy['schemaVersion'] is! int ||
        copy['schemaVersion'] != currentSchemaVersion) {
      throw FormatException(
        'Unsupported campaign archive schema',
        copy['schemaVersion'],
      );
    }
    try {
      if ((copy['archiveId'] as String).trim().isEmpty) {
        throw const FormatException('Archive ID must not be empty');
      }
      final gameId = copy['gameId'] as int;
      DateTime.parse(copy['finalGameDate'] as String);
      DateTime.parse(copy['completedAt'] as String);
      final finalSequence = copy['finalSequence'] as int;
      if (finalSequence < 0) {
        throw const FormatException('Final sequence must not be negative');
      }
      final result = copy['terminalResult'] as Map<String, dynamic>;
      _outcome(result['outcome']);
      _route(result['route']);
      if (result['context'] is! Map<String, dynamic>) {
        throw const FormatException('Terminal context must be an object');
      }
      int previousSequence = 0;
      for (final raw in copy['events'] as List<dynamic>) {
        final event = PlaythroughEvent.fromJson(raw as Map<String, dynamic>);
        if (event.gameId != gameId ||
            event.sequence <= previousSequence ||
            event.sequence > finalSequence) {
          throw const FormatException(
            'Inconsistent campaign history sequence or game ID',
          );
        }
        previousSequence = event.sequence;
      }
    } on TypeError catch (error) {
      throw FormatException('Malformed campaign archive: $error');
    } on StateError catch (error) {
      throw FormatException('Unknown campaign event type: $error');
    }
    // Retain additional JSON fields for lossless compatible-schema round trips.
    return CampaignHistoryArchive._(_freeze(copy) as Map<String, dynamic>);
  }

  CampaignHistoryArchive._(this._json);

  static const int currentSchemaVersion = 1;
  final Map<String, dynamic> _json;

  int get schemaVersion => _json['schemaVersion'] as int;
  String get archiveId => _json['archiveId'] as String;
  int get gameId => _json['gameId'] as int;
  DateTime get finalGameDate =>
      DateTime.parse(_json['finalGameDate'] as String);
  DateTime get completedAt => DateTime.parse(_json['completedAt'] as String);
  int get finalSequence => _json['finalSequence'] as int;
  Map<String, dynamic> get terminalResult =>
      _json['terminalResult'] as Map<String, dynamic>;
  CampaignOutcome get outcome => _outcome(terminalResult['outcome']);
  CampaignEndRoute get route => _route(terminalResult['route']);

  List<PlaythroughEvent> get events => List.unmodifiable(
    (_json['events'] as List<dynamic>).map((raw) {
      final event = PlaythroughEvent.fromJson(raw as Map<String, dynamic>);
      return PlaythroughEvent(
        gameId: event.gameId,
        sequence: event.sequence,
        realTime: event.realTime,
        gameDate: event.gameDate,
        type: event.type,
        data: Map.unmodifiable(event.data),
      );
    }),
  );

  /// Callers may mutate exported JSON without changing this archive.
  Map<String, dynamic> toJson() =>
      jsonDecode(jsonEncode(_json)) as Map<String, dynamic>;
}

CampaignOutcome _outcome(dynamic wireName) => CampaignOutcome.values.firstWhere(
  (value) => value.wireName == wireName,
  orElse: () => throw FormatException('Unknown campaign outcome', wireName),
);

CampaignEndRoute _route(dynamic wireName) => CampaignEndRoute.values.firstWhere(
  (value) => value.wireName == wireName,
  orElse: () =>
      throw FormatException('Unknown campaign ending route', wireName),
);

dynamic _freeze(dynamic value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.unmodifiable(
      value.map((key, nested) => MapEntry(key, _freeze(nested))),
    );
  }
  if (value is List) return List<dynamic>.unmodifiable(value.map(_freeze));
  return value;
}
