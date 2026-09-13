@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/playthrough_log/campaign_finalization.dart';
import 'package:lcs_new_age/playthrough_log/campaign_history_archive.dart';
import 'package:lcs_new_age/playthrough_log/terminal_save.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/scores/score_repository.dart';
import 'package:lcs_new_age/title_screen/campaign_ending.dart';
import 'package:lcs_new_age/title_screen/game_over.dart';
import 'package:lcs_new_age/title_screen/high_scores.dart';
import 'package:lcs_new_age/title_screen/launch_game.dart'
    show EndGameException;
import 'package:shared_preferences/shared_preferences.dart';

import 'campaign_finalization_test.dart' show FinalizationStorage;
import 'test_support.dart';

void main() {
  setUpAll(ensureGameDataLoaded);
  late FinalizationStorage storage;
  late ScoreRepository scores;
  late GameState state;
  late List<Object> failures;
  HighScore? presented;

  setUp(() async {
    final directory = await Directory.systemTemp.createTemp('lcs_endings_');
    addTearDown(() => directory.delete(recursive: true));
    storage = FinalizationStorage('${directory.path}/game.db');
    await storage.init();
    addTearDown(storage.close);
    SharedPreferences.setMockInitialValues({});
    scores = ScoreRepository(storage);
    await scores.initialize(await SharedPreferences.getInstance());
    storage.operations.clear();
    final raw =
        jsonDecode(await File('test/saves/moe_1_5.json').readAsString())
            as Map<String, dynamic>;
    gameState = state = GameState.fromJson(SaveFile.fromJson(raw).saveData)
      ..uniqueGameId = 123
      ..playthroughEvents = []
      ..playthroughSequence = 0;
    failures = [];
    presented = null;
  });

  Future<void> finish(CampaignEnding ending) async {
    await expectLater(
      completeCampaignEnding(
        ending,
        state: state,
        scores: scores,
        presentEnding: () async => storage.operations.add('ending screen'),
        presentScores: (score) async {
          presented = score;
          storage.operations.add('score screen');
        },
        presentFailure: (error) async => failures.add(error),
      ),
      throwsA(isA<EndGameException>()),
    );
  }

  Future<void> verifyCompletion({
    required CampaignOutcome outcome,
    required CampaignEndRoute route,
    required Ending presentation,
    Map<String, dynamic> context = const {},
  }) async {
    expect(failures, isEmpty);
    expect(storage.operations, [
      'save',
      'archive',
      'score',
      'delete',
      'ending screen',
      'score screen',
    ]);
    expect(await storage.loadGame('123'), isNull);
    final terminal = inspectTerminalSave(state) as TerminalCompletion;
    final archive = (await storage.loadArchive(terminal.archiveId))!;
    final book = await scores.load();
    final receipt = book.receipt(terminal.archiveId)!;
    expect(terminal.outcome, outcome);
    expect(terminal.route, route);
    expect(terminal.presentationEnding, presentation);
    expect(terminal.context, context);
    expect(archive.terminalResult, {
      'outcome': outcome.wireName,
      'route': route.wireName,
      'context': context,
    });
    expect(receipt.score.endType, presentation);
    expect(presented!.toJson(), receipt.score.toJson());
    expect(
      book.completed.universalVictories,
      outcome == CampaignOutcome.victory ? 1 : 0,
    );
    expect(
      book.completed.universalLosses,
      outcome == CampaignOutcome.defeat ? 1 : 0,
    );
    expect(book.completed.scoreList, hasLength(1));
  }

  test(
    'victory finalizes before presentation and retries without another accounting',
    () async {
      await finish(CampaignEnding.victory);
      await verifyCompletion(
        outcome: CampaignOutcome.victory,
        route: CampaignEndRoute.victoryConditions,
        presentation: Ending.victory,
      );
      final first = (await scores.load()).toJson();
      final event = state.playthroughEvents.single.toJson();
      await finish(CampaignEnding.victory);
      expect(failures, isEmpty);
      expect((await scores.load()).toJson(), first);
      expect(state.playthroughEvents.single.toJson(), event);
      expect(await storage.listArchiveIds(), hasLength(1));
    },
  );

  for (final presentation in [
    Ending.executed,
    Ending.dispersed,
    Ending.ciaSiege,
  ]) {
    test(
      'general defeat preserves explicit $presentation over active siege',
      () async {
        await finish(
          CampaignEnding.noQualifyingMembers(
            possibleEnding: presentation,
            siegeType: SiegeType.police,
          ),
        );
        await verifyCompletion(
          outcome: CampaignOutcome.defeat,
          route: CampaignEndRoute.noQualifyingMembers,
          presentation: presentation,
        );
      },
    );
  }

  final siegeCases = <SiegeType?, (Ending, String?)>{
    SiegeType.police: (Ending.policeSiege, 'police'),
    SiegeType.cia: (Ending.ciaSiege, 'cia'),
    SiegeType.angryRuralMob: (Ending.hicksSiege, 'angry_rural_mob'),
    SiegeType.corporateMercs: (Ending.corporateSiege, 'corporate_mercs'),
    SiegeType.medicalDebtCollectors: (
      Ending.medicalSiege,
      'medical_debt_collectors',
    ),
    SiegeType.ccs: (Ending.ccsSiege, 'ccs'),
    SiegeType.none: (Ending.dead, null),
    null: (Ending.dead, null),
  };
  for (final entry in siegeCases.entries) {
    test(
      'general defeat resolves siege ${entry.key} without inventing individual fate',
      () async {
        await finish(CampaignEnding.noQualifyingMembers(siegeType: entry.key));
        await verifyCompletion(
          outcome: CampaignOutcome.defeat,
          route: CampaignEndRoute.noQualifyingMembers,
          presentation: entry.value.$1,
          context: {if (entry.value.$2 != null) 'siegeType': entry.value.$2},
        );
      },
    );
  }

  final constitutionCases = {
    CantSeeReason.none: Ending.reaganified,
    CantSeeReason.dating: Ending.dating,
    CantSeeReason.hiding: Ending.hiding,
    CantSeeReason.prison: Ending.prison,
    CantSeeReason.disbanded: Ending.disbandLoss,
    CantSeeReason.hospital: Ending.reaganified,
    CantSeeReason.other: Ending.reaganified,
  };
  for (final entry in constitutionCases.entries) {
    test(
      'constitutional repeal preserves ${entry.key} presentation on the same factual route',
      () async {
        await finish(CampaignEnding.constitutionRepealed(entry.key));
        await verifyCompletion(
          outcome: CampaignOutcome.defeat,
          route: CampaignEndRoute.constitutionRepealed,
          presentation: entry.value,
        );
      },
    );
  }

  test(
    'prolonged disbanding has its own route and disband loss presentation',
    () async {
      await finish(CampaignEnding.prolongedDisbanding);
      await verifyCompletion(
        outcome: CampaignOutcome.defeat,
        route: CampaignEndRoute.prolongedDisbanding,
        presentation: Ending.disbandLoss,
      );
    },
  );

  test(
    'score failure blocks gameplay and screens; persisted completion recovers once',
    () async {
      storage.failStage = 'score';
      await finish(CampaignEnding.constitutionRepealed(CantSeeReason.prison));
      expect(failures.single, isA<StateError>());
      expect(presented, isNull);
      expect(storage.operations, ['save', 'archive', 'score']);
      final saved = (await storage.loadGame('123'))!;
      final terminal = state.playthroughEvents.single.toJson();
      storage.failStage = null;
      for (int retry = 0; retry < 2; retry++) {
        final recovered = await recoverCampaignCompletion(
          state: GameState.fromJson(saved.saveData),
          saveGameId: saved.gameId,
          storage: storage,
          scores: scores,
        );
        expect(recovered.archive.events.single.toJson(), terminal);
        expect(recovered.receipt.score.endType, Ending.prison);
      }
      expect((await scores.load()).completed.universalLosses, 1);
      expect(await storage.loadGame('123'), isNull);
    },
  );

  test(
    'a failed error screen still unwinds instead of continuing gameplay',
    () async {
      storage.failStage = 'save';
      bool reported = false;
      await expectLater(
        completeCampaignEnding(
          CampaignEnding.victory,
          state: state,
          scores: scores,
          presentFailure: (_) async {
            reported = true;
            throw StateError('Console unavailable');
          },
        ),
        throwsA(isA<EndGameException>()),
      );
      expect(reported, isTrue);
      expect(storage.operations, ['save']);
    },
  );

  test(
    'qualifying Liberal leaves the existing defeat check non-terminal',
    () async {
      state.lcs.pool.clear();
      state.lcs.pool.add(Creature()..align = Alignment.liberal);
      expect(await checkForDefeat(Ending.executed), isFalse);
      expect(state.playthroughEvents, isEmpty);
      expect(storage.operations, isEmpty);
    },
  );
}
