import 'package:lcs_new_age/scores/high_score.dart';
import 'package:lcs_new_age/scores/score_book.dart';
import 'package:lcs_new_age/title_screen/game_over.dart';

HighScore exampleScore({
  Ending ending = Ending.policeSiege,
  int recruits = 2,
}) => HighScore(
  slogan: 'Test campaign',
  month: 2,
  year: 2024,
  statRecruits: recruits,
  statMartyrs: 3,
  statKills: 4,
  statKidnappings: 5,
  statFunds: 6,
  statSpent: 7,
  statBuys: 8,
  statBurns: 9,
  endType: ending,
);

CompletedScoreReceipt exampleReceipt({
  String id = 'completion-123',
  int gameId = 123,
  HighScore? score,
}) => CompletedScoreReceipt(
  completionId: id,
  gameId: gameId,
  score: score ?? exampleScore(),
);
