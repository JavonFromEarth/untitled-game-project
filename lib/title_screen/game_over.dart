import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/title_screen/campaign_ending.dart';
import 'package:lcs_new_age/title_screen/launch_game.dart';

Future<bool> checkForDefeat([
  Ending possibleEnding = Ending.unspecified,
]) async {
  if (pool.any(
    (p) =>
        p.alive &&
        p.align == Alignment.liberal &&
        !(p.sleeperAgent && p.hireId != null),
  )) {
    return false;
  }

  await completeCampaignEnding(
    CampaignEnding.noQualifyingMembers(
      possibleEnding: possibleEnding,
      siegeType: activeSite?.siege.activeSiegeType,
    ),
  );
}

enum EndTypes {
  other,
  won,
  hicks,
  cia,
  police,
  corp,
  reagan,
  dead,
  prison,
  executed,
  dating,
  hiding,
  disbandLoss,
  dispersed,
  ccs,
}

void endGame() {
  throw EndGameException();
}

enum Ending {
  victory,
  hicksSiege,
  ciaSiege,
  policeSiege,
  corporateSiege,
  medicalSiege,
  ccsSiege,
  reaganified,
  dead,
  prison,
  executed,
  dating,
  hiding,
  disbandLoss,
  dispersed,
  unspecified,
}
