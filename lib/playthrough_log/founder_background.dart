import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_log.dart';

// These IDs are persisted; wording and questionnaire order may change.
enum FounderBackgroundStage {
  birth('birth'),
  childhoodDiscipline('childhood_discipline'),
  elementarySchool('elementary_school'),
  parentsDivorce('parents_divorce'),
  middleSchool('middle_school'),
  thingsGettingBad('things_getting_bad'),
  crescendo('crescendo'),
  ranAway('ran_away'),
  eighteenthBirthday('eighteenth_birthday'),
  recentLife('recent_life');

  const FounderBackgroundStage(this.wireName);
  final String wireName;
}

/// Records a resolved authored background choice, not its mechanical effects.
/// gameDate is when initialization establishes the fact, not when it occurred.
void recordFounderBackgroundChoice({
  required int founderId,
  required FounderBackgroundStage stage,
  required String choiceId,
  required int stageOrder,
  required String questionText,
  required String answerText,
  required bool manual,
  required DateTime birthDate,
}) {
  final timing = switch (stage) {
    FounderBackgroundStage.birth => <String, dynamic>{
      'precision': 'date',
      'date': birthDate.toIso8601String().split('T').first,
    },
    FounderBackgroundStage.parentsDivorce => <String, dynamic>{
      'precision': 'age',
      'age': 10,
    },
    FounderBackgroundStage.ranAway => <String, dynamic>{
      'precision': 'age',
      'age': 15,
    },
    FounderBackgroundStage.eighteenthBirthday => <String, dynamic>{
      'precision': 'birthday',
      'age': 18,
    },
    FounderBackgroundStage.crescendo when choiceId == 'stole_police_car' =>
      <String, dynamic>{'precision': 'age', 'age': 14},
    _ => <String, dynamic>{'precision': 'authored_wording'},
  };

  logPlaythroughEvent(
    gameDate: date,
    type: PlaythroughEventType.founderBackgroundChoice,
    data: {
      'founderId': founderId,
      'stageId': stage.wireName,
      'choiceId': choiceId,
      'stageOrder': stageOrder,
      'questionText': questionText,
      'answerText': answerText,
      'selectionMethod': manual ? 'manual' : 'random',
      'temporalContext': {
        'period': 'pre_campaign',
        'wording': questionText,
        ...timing,
      },
    },
  );
}
