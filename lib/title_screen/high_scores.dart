import 'package:lcs_new_age/engine/engine.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/gamestate/time.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/scores/high_score.dart';
import 'package:lcs_new_age/scores/score_repository.dart';
import 'package:lcs_new_age/title_screen/game_over.dart';
import 'package:lcs_new_age/utils/colors.dart';

export 'package:lcs_new_age/scores/high_score.dart';

Future<void> viewHighScores([HighScore? yourScore]) async {
  HighScores? highScores = await loadHighScores();
  if (highScores.scoreList.isEmpty) return;

  erase();
  mvaddstrc(0, 0, white, "The Liberal ELITE");

  int y = 2;
  for (HighScore s in highScores.scoreList) {
    if (s.endType == Ending.victory) {
      if (s == yourScore) {
        setColor(lightGreen);
      } else {
        setColor(green);
      }
    } else {
      setColor(red);
    }
    mvaddstr(y, 0, s.slogan);
    if (s.score == yourScore?.score &&
        s.daysSince2000 == yourScore?.daysSince2000) {
      if (s.endType == Ending.victory) {
        setColor(lightGreen);
      } else {
        setColor(darkRed);
      }
    } else {
      setColor(lightGray);
    }
    move(y + 1, 0);
    switch (s.endType) {
      case Ending.victory:
        addstr("The Liberal Crime Squad liberalized the country in ");
      case Ending.policeSiege:
        addstr("The Liberal Crime Squad was brought to justice in ");
      case Ending.ciaSiege:
        addstr("The Liberal Crime Squad was blotted out in ");
      case Ending.hicksSiege:
        addstr("The Liberal Crime Squad was mobbed in ");
      case Ending.corporateSiege:
        addstr("The Liberal Crime Squad was downsized in ");
      case Ending.medicalSiege:
        addstr("The Liberal Crime Squad was billed to death in ");
      case Ending.dead:
        addstr("The Liberal Crime Squad was KIA in ");
      case Ending.reaganified:
        addstr("The country was Reaganified in ");
      case Ending.prison:
        addstr("The Liberal Crime Squad died in prison in ");
      case Ending.executed:
        addstr("The Liberal Crime Squad was executed in ");
      case Ending.dating:
        addstr("The Liberal Crime Squad was on vacation in ");
      case Ending.hiding:
        addstr("The Liberal Crime Squad was in permanent hiding in ");
      case Ending.disbandLoss:
        addstr("The Liberal Crime Squad was hunted down in ");
      case Ending.dispersed:
        addstr("The Liberal Crime Squad was scattered in ");
      case Ending.ccsSiege:
        addstr("The Liberal Crime Squad was out-Crime Squadded in ");
      case Ending.unspecified:
        addstr("The Liberal Crime Squad was defeated in ");
    }
    addstr("${getMonth(s.month)} ${s.year}.");
    mvaddstr(y + 2, 0, "Recruits: ${s.statRecruits}");
    mvaddstr(y + 3, 0, "Martyrs: ${s.statMartyrs}");
    mvaddstr(y + 2, 20, "Kills: ${s.statKills}");
    mvaddstr(y + 3, 20, "Kidnappings: ${s.statKidnappings}");
    mvaddstr(y + 2, 40, "\$ Taxed: ${s.statFunds}");
    mvaddstr(y + 3, 40, "\$ Spent: ${s.statSpent}");
    mvaddstr(y + 2, 60, "Flags Bought: ${s.statBuys}");
    mvaddstr(y + 3, 60, "Flags Burned: ${s.statBurns}");
    y += 4;
  }

  setColor(lightGreen);

  //UNIVERSAL STATS
  mvaddstr(22, 0, "Universal Liberal Statistics:");
  mvaddstr(23, 0, "Recruits: ${highScores.universalRecruits}");
  mvaddstr(24, 0, "Martyrs: ${highScores.universalMartyrs}");
  mvaddstr(23, 20, "Kills: ${highScores.universalKills}");
  mvaddstr(24, 20, "Kidnappings: ${highScores.universalKidnappings}");
  mvaddstr(23, 40, "\$ Taxed: ${highScores.universalFunds}");
  mvaddstr(24, 40, "\$ Spent: ${highScores.universalSpent}");
  mvaddstr(23, 60, "Flags Bought: ${highScores.universalFlagBuys}");
  mvaddstr(24, 60, "Flags Burned: ${highScores.universalFlagBurns}");
  await getKey();
}

Future<HighScores> loadHighScores() async {
  final saves = await loadGameList();
  return scoreRepository.loadForDisplay(
    saves.map((save) => save.gameState).whereType<GameState>(),
  );
}

/// Compatibility entry point until gameplay endings supply completion IDs.
Future<HighScore> saveHighScore(Ending ending) async {
  final score = scoreFromState(gameState, ending);
  await scoreRepository.recordAnonymous(score);
  return score;
}
