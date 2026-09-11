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
      type: json['type'] as String,
      data: data,
    );
  }

  final int gameId;
  final int sequence;
  final DateTime realTime;
  final DateTime gameDate;
  final String type;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
        ...data,
        'gameId': gameId,
        'seq': sequence,
        'realTime': realTime.toIso8601String(),
        'gameDate': gameDate.toIso8601String(),
        'type': type,
      };
}
