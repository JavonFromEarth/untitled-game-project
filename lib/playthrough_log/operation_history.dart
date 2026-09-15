import 'dart:convert';

import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/playthrough_log/member_history.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_log.dart';
import 'package:lcs_new_age/sitemode/chase_sequence.dart';

enum OperationKind {
  siteAction('site_action'),
  siege('siege');

  const OperationKind(this.wireName);
  final String wireName;
}

enum OperationResolutionPath {
  squadDestroyed('squad_destroyed'),
  siteExit('site_exit'),
  ccsTakeover('ccs_takeover'),
  siegeEscape('siege_escape'),
  siegeDefeat('siege_defeat'),
  siegeVictory('siege_victory');

  const OperationResolutionPath(this.wireName);
  final String wireName;
}

String _controllerWire(SiteController controller) => switch (controller) {
  SiteController.lcs => 'lcs',
  SiteController.ccs => 'ccs',
  SiteController.unaligned => 'unaligned',
};

String _siegeWire(SiegeType type) => switch (type) {
  SiegeType.none => 'none',
  SiegeType.police => 'police',
  SiegeType.cia => 'cia',
  SiegeType.angryRuralMob => 'angry_rural_mob',
  SiegeType.corporateMercs => 'corporate_mercs',
  SiegeType.medicalDebtCollectors => 'medical_debt_collectors',
  SiegeType.ccs => 'ccs',
};

String _escalationWire(SiegeEscalation escalation) => switch (escalation) {
  SiegeEscalation.police => 'police',
  SiegeEscalation.nationalGuard => 'national_guard',
  SiegeEscalation.tanks => 'tanks',
  SiegeEscalation.bombers => 'bombers',
};

String _chaseWire(ChaseOutcome outcome) => switch (outcome) {
  ChaseOutcome.victory => 'victory',
  ChaseOutcome.escape => 'escape',
  ChaseOutcome.capture => 'capture',
  ChaseOutcome.death => 'death',
};

Map<String, dynamic> _participant(Creature member) {
  final weapon = member.equippedWeapon;
  final clothing = member.equippedClothing;
  return {
    'memberId': member.id,
    'memberName': member.name,
    'memberTypeId': member.typeId,
    'memberTypeName': member.type.name,
    if (weapon != null)
      'weapon': {
        'weaponTypeId': weapon.type.idName,
        'weaponTypeName': weapon.type.name,
      },
    if (clothing != null)
      'clothing': {
        'clothingTypeId': clothing.type.idName,
        'clothingTypeName': clothing.type.name,
        'bloody': clothing.bloody,
        'damaged': clothing.damaged,
      },
  };
}

/// Refuse invalid or overlapping starts without interrupting gameplay.
/// This is routing context for one invocation, not a resumable saved operation.
OperationHistory? beginOperation(Site site, OperationKind kind) {
  final state = gameState;
  final squad = state.activeSquad;
  if (state.activeOperationStartSequence != null ||
      squad == null ||
      squad.livingMembers.isEmpty ||
      (kind == OperationKind.siege && !site.siege.underSiege) ||
      _campaignEnded(state)) {
    return null;
  }
  final siteSnapshot = historySiteSnapshot(site);
  if (siteSnapshot == null) return null;
  final controller = _controllerWire(site.controller);
  final start = logPlaythroughEvent(
    gameDate: state.date,
    type: PlaythroughEventType.operationStarted,
    data:
        jsonDecode(
              jsonEncode({
                'operationKind': kind.wireName,
                'site': siteSnapshot,
                'controller': controller,
                'squadId': squad.id,
                'squadName': squad.name,
                'participants': squad.livingMembers.map(_participant).toList(),
                if (kind == OperationKind.siege)
                  'siege': {
                    'siegeType': _siegeWire(site.siege.activeSiegeType),
                    'underAttack': site.siege.underAttack,
                    'escalation': _escalationWire(site.siege.escalationState),
                  },
              }),
            )
            as Map<String, dynamic>,
  );
  state.activeOperationStartSequence = start.sequence;
  return OperationHistory._(state, site, kind, start.sequence, controller);
}

bool _campaignEnded(GameState state) => state.playthroughEvents.any(
  (event) =>
      event.gameId == state.uniqueGameId &&
      event.type == PlaythroughEventType.campaignEnded,
);

/// Owned by the invoking resolver. The persisted start sequence is its only ID.
class OperationHistory {
  OperationHistory._(
    this._state,
    this._site,
    this.kind,
    this.startSequence,
    this._controllerBefore,
  );

  final GameState _state;
  final Site _site;
  final OperationKind kind;
  final int startSequence;
  final String _controllerBefore;

  PlaythroughEvent? resolve(
    OperationResolutionPath path, {
    ChaseOutcome? chaseOutcome,
    int? siteCrime,
    bool? siteAlarmed,
  }) {
    if (!identical(gameState, _state) ||
        _state.activeOperationStartSequence != startSequence) {
      return null;
    }
    try {
      // Terminal history is already complete. Leave this episode open.
      if (_campaignEnded(_state)) return null;
      return logPlaythroughEvent(
        gameDate: _state.date,
        type: PlaythroughEventType.operationResolved,
        data: {
          'operationStartSequence': startSequence,
          'resolutionPath': path.wireName,
          'controllerBefore': _controllerBefore,
          'controllerAfter': _controllerWire(_site.controller),
          if (chaseOutcome != null) 'chaseOutcome': _chaseWire(chaseOutcome),
          if (kind == OperationKind.siteAction && siteCrime != null)
            'siteCrime': siteCrime,
          if (kind == OperationKind.siteAction && siteAlarmed != null)
            'siteAlarmed': siteAlarmed,
        },
      );
    } finally {
      clear();
    }
  }

  /// Call from finally even when no semantic resolution was reached. Never
  /// creates a historical outcome or clears a newer/different operation.
  void clear() {
    if (_state.activeOperationStartSequence == startSequence) {
      _state.activeOperationStartSequence = null;
    }
  }
}
