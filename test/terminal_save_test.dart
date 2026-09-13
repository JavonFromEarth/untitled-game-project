import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';
import 'package:lcs_new_age/playthrough_log/terminal_save.dart';
import 'package:lcs_new_age/title_screen/game_over.dart';

GameState terminalState() => GameState()
  ..uniqueGameId = 123
  ..playthroughSequence = 1
  ..playthroughEvents = [
    PlaythroughEvent(
      gameId: 123,
      sequence: 1,
      realTime: DateTime.utc(2026, 9, 13),
      gameDate: DateTime(2023, 1, 1),
      type: PlaythroughEventType.campaignEnded,
      data: {
        'archiveId': 'completion-test',
        'outcome': 'defeat',
        'route': 'constitution_repealed',
        'context': {},
        'presentationEnding': 'prison',
      },
    ),
  ];

void main() {
  test('ordinary and valid terminal states are distinguished', () {
    expect(inspectTerminalSave(GameState()), isA<OrdinarySave>());
    final state = terminalState();
    final result =
        inspectTerminalSave(state, saveGameId: '123') as TerminalCompletion;
    expect(result.archiveId, 'completion-test');
    expect(result.presentationEnding, Ending.prison);
    expect(
      PlaythroughEvent.fromJson(result.event.toJson()).toJson(),
      state.playthroughEvents.single.toJson(),
    );
  });
  test(
    'missing or unknown presentation is invalid without inventing a fallback',
    () {
      for (final value in [null, 3, 'future']) {
        final state = terminalState();
        state.playthroughEvents.single.data['presentationEnding'] = value;
        expect(inspectTerminalSave(state), isA<InvalidTerminalSave>());
      }
    },
  );
  test('malformed terminal metadata is invalid', () {
    for (final entry in {
      'archiveId': '',
      'outcome': 'future',
      'route': 'future',
      'context': [],
    }.entries) {
      final state = terminalState();
      state.playthroughEvents.single.data[entry.key] = entry.value;
      expect(inspectTerminalSave(state), isA<InvalidTerminalSave>());
    }
  });
  test(
    'duplicate, non-final, sequence, date and campaign mismatches are invalid',
    () {
      final state = terminalState();
      expect(
        inspectTerminalSave(state, saveGameId: '999'),
        isA<InvalidTerminalSave>(),
      );
      state.playthroughEvents.add(state.playthroughEvents.single);
      expect(inspectTerminalSave(state), isA<InvalidTerminalSave>());
      state.playthroughEvents.removeLast();
      state.playthroughEvents.add(
        PlaythroughEvent(
          gameId: 123,
          sequence: 2,
          realTime: DateTime.now(),
          gameDate: state.date,
          type: PlaythroughEventType.memberJoined,
        ),
      );
      expect(inspectTerminalSave(state), isA<InvalidTerminalSave>());
      state.playthroughEvents.removeLast();
      state.playthroughSequence = 2;
      expect(inspectTerminalSave(state), isA<InvalidTerminalSave>());
      state.playthroughSequence = 1;
      state.date = DateTime(2024);
      expect(inspectTerminalSave(state), isA<InvalidTerminalSave>());
      state.date = DateTime(2023);
      state.uniqueGameId = 999;
      expect(inspectTerminalSave(state), isA<InvalidTerminalSave>());
    },
  );
}
