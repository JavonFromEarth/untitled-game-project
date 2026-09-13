import 'package:lcs_new_age/title_screen/game_over.dart';

/// Score/UI categories only: these labels are not individual life-status facts.
extension ScoreEndingWire on Ending {
  String get scoreWireName => switch (this) {
    Ending.victory => 'victory',
    Ending.hicksSiege => 'hicks_siege',
    Ending.ciaSiege => 'cia_siege',
    Ending.policeSiege => 'police_siege',
    Ending.corporateSiege => 'corporate_siege',
    Ending.medicalSiege => 'medical_siege',
    Ending.ccsSiege => 'ccs_siege',
    Ending.reaganified => 'reaganified',
    Ending.dead => 'dead',
    Ending.prison => 'prison',
    Ending.executed => 'executed',
    Ending.dating => 'dating',
    Ending.hiding => 'hiding',
    Ending.disbandLoss => 'disband_loss',
    Ending.dispersed => 'dispersed',
    Ending.unspecified => 'unspecified',
  };

  static Ending fromWireName(String name) => Ending.values.firstWhere(
    (ending) => ending.scoreWireName == name,
    orElse: () => throw FormatException('Unknown score ending', name),
  );
}

class HighScores {
  HighScores({
    this.universalRecruits = 0,
    this.universalMartyrs = 0,
    this.universalKills = 0,
    this.universalKidnappings = 0,
    this.universalFunds = 0,
    this.universalSpent = 0,
    this.universalFlagBuys = 0,
    this.universalFlagBurns = 0,
    this.universalLosses = 0,
    this.universalVictories = 0,
  });
  HighScores.fromJson(Map<String, dynamic> json)
    : scoreList = (json['highScores'] as List<dynamic>? ?? [])
          .map<HighScore>((a) => HighScore.fromJson(a as Map<String, dynamic>))
          .toList(),
      universalRecruits = json['universalRecruits'] ?? 0,
      universalMartyrs = json['universalMartyrs'] ?? 0,
      universalKills = json['universalKills'] ?? 0,
      universalKidnappings = json['universalKidnappings'] ?? 0,
      universalFunds = json['universalFunds'] ?? 0,
      universalSpent = json['universalSpent'] ?? 0,
      universalFlagBuys = json['universalFlagBuys'] ?? 0,
      universalFlagBurns = json['universalFlagBurns'] ?? 0,
      universalLosses = json['universalLosses'] ?? 0,
      universalVictories = json['universalVictories'] ?? 0;
  Map<String, dynamic> toJson() => {
    'highScores': scoreList.map((e) => e.toJson()).toList(),
    'universalRecruits': universalRecruits,
    'universalMartyrs': universalMartyrs,
    'universalKills': universalKills,
    'universalKidnappings': universalKidnappings,
    'universalFunds': universalFunds,
    'universalSpent': universalSpent,
    'universalFlagBuys': universalFlagBuys,
    'universalFlagBurns': universalFlagBurns,
    'universalLosses': universalLosses,
    'universalVictories': universalVictories,
  };
  List<HighScore> scoreList = [];
  int universalRecruits = 0;
  int universalMartyrs = 0;
  int universalKills = 0;
  int universalKidnappings = 0;
  int universalFunds = 0;
  int universalSpent = 0;
  int universalFlagBuys = 0;
  int universalFlagBurns = 0;
  int universalLosses = 0;
  int universalVictories = 0;

  Iterable<HighScore> get wins =>
      scoreList.where((e) => e.endType == Ending.victory);
}

class HighScore {
  HighScore({
    required this.slogan,
    required this.month,
    required this.year,
    required this.statRecruits,
    required this.statMartyrs,
    required this.statKills,
    required this.statKidnappings,
    required this.statFunds,
    required this.statSpent,
    required this.statBuys,
    required this.statBurns,
    required this.endType,
  });
  HighScore.fromJson(Map<String, dynamic> json)
    : slogan = json['slogan'] ?? "",
      month = json['month'] ?? 0,
      year = json['year'] ?? 2023,
      statRecruits = json['statRecruits'] ?? 0,
      statMartyrs = json['statMartyrs'] ?? 0,
      statKills = json['statKills'] ?? 0,
      statKidnappings = json['statKidnappings'] ?? 0,
      statFunds = json['statFunds'] ?? 0,
      statSpent = json['statSpent'] ?? 0,
      statBuys = json['statBuys'] ?? 0,
      statBurns = json['statBurns'] ?? 0,
      endType = json.containsKey('ending')
          ? ScoreEndingWire.fromWireName(json['ending'] as String)
          : Ending.values[json['endType'] as int];
  Map<String, dynamic> toJson() => {
    'slogan': slogan,
    'month': month,
    'year': year,
    'statRecruits': statRecruits,
    'statMartyrs': statMartyrs,
    'statKills': statKills,
    'statKidnappings': statKidnappings,
    'statFunds': statFunds,
    'statSpent': statSpent,
    'statBuys': statBuys,
    'statBurns': statBurns,
    'ending': endType.scoreWireName,
  };
  String slogan;
  int month;
  int year;
  int statRecruits;
  int statMartyrs;
  int statKills;
  int statKidnappings;
  int statFunds;
  int statSpent;
  int statBuys;
  int statBurns;
  Ending endType;

  int compareTo(HighScore other) {
    if (endType == Ending.victory && other.endType != Ending.victory) {
      return -1;
    } else if (endType != Ending.victory && other.endType == Ending.victory) {
      return 1;
    } else if (endType == Ending.victory && other.endType == Ending.victory) {
      return daysSince2000 - other.daysSince2000;
    } else {
      return other.score - score;
    }
  }

  int get daysSince2000 =>
      DateTime(year, month, 1).difference(DateTime(2000, 1, 1)).inDays;
  int get score =>
      statRecruits * 1000 +
      statKills * 50 +
      statKidnappings * 50 +
      statFunds +
      statSpent;
}
