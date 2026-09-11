import 'package:collection/collection.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/common_display/common_display.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_log.dart';

Future<void> doActivitySleeperJoinLCS(List<Creature> people) async {
  List<Site> viableSafehouses = sites
      .where((s) => s.controller == SiteController.lcs && !s.siege.underSiege)
      .toList();
  for (Creature p in people) {
    Site? location =
        viableSafehouses.firstWhereOrNull(
          (s) => s.city == p.site?.city && s.numberEating > 0,
        ) ??
        viableSafehouses.firstWhereOrNull((s) => s.city == p.site?.city) ??
        viableSafehouses.firstOrNull;
    if (location == null) continue;
    p.activity = Activity.none();
    p.sleeperAgent = false;
    p.location = p.base = location;

    logPlaythroughEvent(
      gameDate: date,
      type: PlaythroughEventType.sleeperReportedIn,
      data: {
        'operativeId': p.id,
        'operativeName': p.name,
        'safehouseId': location.id,
        'safehouseName': location.name,
      },
    );

    await showMessage("${p.name} is reporting in at the ${location.name}.");
  }
}
