import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/playthrough_log/campaign_finalization.dart';
import 'package:lcs_new_age/playthrough_log/campaign_history_archive.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/scores/score_repository.dart';
import 'package:lcs_new_age/title_screen/game_over.dart';
import 'package:lcs_new_age/title_screen/high_scores.dart';
import 'package:lcs_new_age/title_screen/launch_game.dart'
    show EndGameException;

/// A resolved campaign outcome and its separate legacy score/UI category.
/// The factories describe campaign endings, never individual member fates.
class CampaignEnding {
  const CampaignEnding._(
    this.outcome,
    this.route,
    this.presentationEnding, [
    this.context = const {},
  ]);

  factory CampaignEnding.noQualifyingMembers({
    Ending possibleEnding = Ending.unspecified,
    SiegeType? siegeType,
  }) {
    if (possibleEnding != Ending.unspecified) {
      return CampaignEnding._(
        CampaignOutcome.defeat,
        CampaignEndRoute.noQualifyingMembers,
        possibleEnding,
      );
    }
    final (ending, siegeWire) = switch (siegeType) {
      SiegeType.police => (Ending.policeSiege, 'police'),
      SiegeType.cia => (Ending.ciaSiege, 'cia'),
      SiegeType.angryRuralMob => (Ending.hicksSiege, 'angry_rural_mob'),
      SiegeType.corporateMercs => (Ending.corporateSiege, 'corporate_mercs'),
      SiegeType.medicalDebtCollectors => (
        Ending.medicalSiege,
        'medical_debt_collectors',
      ),
      SiegeType.ccs => (Ending.ccsSiege, 'ccs'),
      SiegeType.none || null => (Ending.dead, null),
    };
    return CampaignEnding._(
      CampaignOutcome.defeat,
      CampaignEndRoute.noQualifyingMembers,
      ending,
      Map.unmodifiable({if (siegeWire != null) 'siegeType': siegeWire}),
    );
  }

  factory CampaignEnding.constitutionRepealed(CantSeeReason reason) =>
      CampaignEnding._(
        CampaignOutcome.defeat,
        CampaignEndRoute.constitutionRepealed,
        switch (reason) {
          CantSeeReason.dating => Ending.dating,
          CantSeeReason.hiding => Ending.hiding,
          CantSeeReason.prison => Ending.prison,
          CantSeeReason.disbanded => Ending.disbandLoss,
          CantSeeReason.hospital ||
          CantSeeReason.other ||
          CantSeeReason.none => Ending.reaganified,
        },
      );

  static const victory = CampaignEnding._(
    CampaignOutcome.victory,
    CampaignEndRoute.victoryConditions,
    Ending.victory,
  );
  static const prolongedDisbanding = CampaignEnding._(
    CampaignOutcome.defeat,
    CampaignEndRoute.prolongedDisbanding,
    Ending.disbandLoss,
  );

  final CampaignOutcome outcome;
  final CampaignEndRoute route;
  final Ending presentationEnding;
  final Map<String, dynamic> context;
}

/// Persist before any ending screens. Success and failure both unwind to title;
/// neither can return to gameplay after an ending has resolved.
/// Optional dependencies keep the persistence and console boundary testable.
Future<Never> completeCampaignEnding(
  CampaignEnding ending, {
  GameState? state,
  ScoreRepository? scores,
  Future<void> Function()? presentEnding,
  Future<void> Function(HighScore)? presentScores,
  Future<void> Function(Object)? presentFailure,
}) async {
  try {
    final repository = scores ?? scoreRepository;
    final result = await finalizeCampaign(
      state: state ?? gameState,
      storage: repository.storage,
      scores: repository,
      outcome: ending.outcome,
      route: ending.route,
      presentationEnding: ending.presentationEnding,
      terminalContext: ending.context,
    );
    if (presentEnding != null) await presentEnding();
    if (presentScores != null) {
      await presentScores(result.receipt.score);
    } else {
      await viewHighScores(result.receipt.score);
    }
  } catch (error) {
    await (presentFailure ?? showCampaignCompletionError)(error);
  } finally {
    // Even a failed error screen must not allow normal gameplay to continue.
    throw EndGameException();
  }
}
