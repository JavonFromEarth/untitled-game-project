enum PlaythroughEventType {
  recruitJoined('recruit_joined');

  const PlaythroughEventType(this.wireName);

  final String wireName;

  static PlaythroughEventType fromWireName(String value) {
    return PlaythroughEventType.values.firstWhere(
      (type) => type.wireName == value,
    );
  }
}

class PlaythroughEvent {
  PlaythroughEvent({
    required this.gameId,
    required this.sequence,
    required this.realTime,
    required this.gameDate,
    required this.type,
    this.data = const {},
  });

  factory PlaythroughEvent.fromJson(Map<String, dynamic> json) {
    final data = Map<String, dynamic>.from(json)
      ..remove('gameId')
      ..remove('seq')
      ..remove('realTime')
      ..remove('gameDate')
      ..remove('type');

    return PlaythroughEvent(
      gameId: json['gameId'] as int,
      sequence: json['seq'] as int,
      realTime: DateTime.parse(json['realTime'] as String),
      gameDate: DateTime.parse(json['gameDate'] as String),
      type: PlaythroughEventType.fromWireName(json['type'] as String),
      data: data,
    );
  }

  final int gameId;
  final int sequence;
  final DateTime realTime;
  final DateTime gameDate;
  final PlaythroughEventType type;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
        ...data,
        'gameId': gameId,
        'seq': sequence,
        'realTime': realTime.toIso8601String(),
        'gameDate': gameDate.toIso8601String(),
        'type': type.wireName,
      };
}
