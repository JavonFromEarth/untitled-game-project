import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/playthrough_log/founder_background.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';

void main() {
  late GameState previousState;
  setUp(() {
    previousState = gameState;
    gameState = GameState()..uniqueGameId = 123;
  });
  tearDown(() => gameState = previousState);

  PlaythroughEvent record(
    FounderBackgroundStage stage, {
    bool manual = true,
    String choiceId = 'example_choice',
  }) {
    recordFounderBackgroundChoice(
      founderId: 42,
      stage: stage,
      choiceId: choiceId,
      stageOrder: 1,
      questionText: 'Authored question',
      answerText: 'Rendered answer',
      manual: manual,
      birthDate: DateTime(2004, 6, 5),
    );
    return gameState.playthroughEvents.last;
  }

  test('founder background uses stable event and stage wire names', () {
    expect(
      PlaythroughEventType.founderBackgroundChoice.wireName,
      'founder_background_choice',
    );
    expect(
      PlaythroughEventType.fromWireName('founder_background_choice'),
      PlaythroughEventType.founderBackgroundChoice,
    );
    expect(FounderBackgroundStage.values.map((stage) => stage.wireName), [
      'birth',
      'childhood_discipline',
      'elementary_school',
      'parents_divorce',
      'middle_school',
      'things_getting_bad',
      'crescendo',
      'ran_away',
      'eighteenth_birthday',
      'recent_life',
    ]);
  });

  for (final manual in [true, false]) {
    test('${manual ? 'manual' : 'random'} background event round-trips', () {
      final event = record(
        FounderBackgroundStage.birth,
        manual: manual,
        choiceId: 'reagan_died',
      );
      final json =
          jsonDecode(jsonEncode(event.toJson())) as Map<String, dynamic>;
      final restored = PlaythroughEvent.fromJson(json);
      expect(restored.type, PlaythroughEventType.founderBackgroundChoice);
      expect(restored.gameId, 123);
      expect(restored.sequence, 1);
      expect(restored.realTime, event.realTime);
      expect(restored.gameDate, DateTime(2023, 1, 1));
      expect(restored.data, {
        'founderId': 42,
        'stageId': 'birth',
        'choiceId': 'reagan_died',
        'stageOrder': 1,
        'questionText': 'Authored question',
        'answerText': 'Rendered answer',
        'selectionMethod': manual ? 'manual' : 'random',
        'temporalContext': {
          'period': 'pre_campaign',
          'wording': 'Authored question',
          'precision': 'date',
          'date': '2004-06-05',
        },
      });
      expect(restored.toJson(), json);
      expect(gameState.playthroughSequence, 1);
    });
  }

  test(
    'stated ages and birthday preserve precision without invented dates',
    () {
      for (final (stage, age, precision) in [
        (FounderBackgroundStage.parentsDivorce, 10, 'age'),
        (FounderBackgroundStage.ranAway, 15, 'age'),
        (FounderBackgroundStage.eighteenthBirthday, 18, 'birthday'),
      ]) {
        expect(record(stage).data['temporalContext'], {
          'period': 'pre_campaign',
          'wording': 'Authored question',
          'precision': precision,
          'age': age,
        });
      }
    },
  );

  test('age 14 belongs only to the police-car answer', () {
    expect(
      record(
        FounderBackgroundStage.crescendo,
        choiceId: 'stole_police_car',
      ).data['temporalContext'],
      {
        'period': 'pre_campaign',
        'wording': 'Authored question',
        'precision': 'age',
        'age': 14,
      },
    );
    expect(
      record(
        FounderBackgroundStage.crescendo,
        choiceId: 'hacked_grades',
      ).data['temporalContext'],
      {
        'period': 'pre_campaign',
        'wording': 'Authored question',
        'precision': 'authored_wording',
      },
    );
  });

  test('undated stages retain authored wording without ages or dates', () {
    for (final stage in [
      FounderBackgroundStage.childhoodDiscipline,
      FounderBackgroundStage.elementarySchool,
      FounderBackgroundStage.middleSchool,
      FounderBackgroundStage.thingsGettingBad,
      FounderBackgroundStage.recentLife,
    ]) {
      expect(record(stage).data['temporalContext'], {
        'period': 'pre_campaign',
        'wording': 'Authored question',
        'precision': 'authored_wording',
      });
    }
  });
}
