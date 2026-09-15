import 'dart:convert';

import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/playthrough_log/member_history.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_log.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';

enum MemberDeathCause {
  combatInjury('combat_injury'),
  fire('fire'),
  bleeding('bleeding'),
  chaseViolence('chase_violence'),
  vehicleCrash('vehicle_crash'),
  injuries('injuries'),
  oldAge('old_age'),
  carBomb('car_bomb'),
  starvation('starvation'),
  sniperFire('sniper_fire'),
  airStrike('air_strike'),
  massacre('massacre'),
  execution('execution'),
  prisonDeath('prison_death');

  const MemberDeathCause(this.wireName);
  final String wireName;
}

/// For the instrumented resolvers, pre-death pool presence is necessary but
/// insufficient: affiliation also needs history or an organizational anchor.
/// Legacy fallback requires an organizational anchor and excludes unresolved
/// captives/prospects. A bare hireId (or a command cycle) is not an anchor.
bool hasMemberHistoryEvidence(Creature person) {
  final visited = <int>{};
  bool established(Creature candidate) {
    if (!pool.contains(candidate)) return false;
    if (!visited.add(candidate.id)) return false;
    if (gameState.playthroughEvents.any(
      (event) =>
          event.gameId == gameState.uniqueGameId &&
          switch (event.type) {
            PlaythroughEventType.campaignFounded =>
              event.data['founderId'] == candidate.id,
            PlaythroughEventType.memberJoined =>
              event.data['memberId'] == candidate.id,
            PlaythroughEventType.recruitJoined =>
              event.data['recruitId'] == candidate.id,
            _ => false,
          },
    )) {
      return true;
    }
    if (candidate.missing ||
        candidate.kidnapped ||
        interrogationSessions.any((s) => s.hostageId == candidate.id) ||
        datingSessions.any((s) => s.dates.any((p) => p.id == candidate.id)) ||
        recruitmentSessions.any((s) => s.recruit.id == candidate.id)) {
      return false;
    }
    // Squad membership requires both sides of the relationship, not a stale ID.
    if (candidate.sleeperAgent ||
        squads.any(
          (s) => s.id == candidate.squadId && s.members.contains(candidate),
        )) {
      return true;
    }
    final boss = candidate.boss;
    return boss != null && established(boss);
  }

  return established(person);
}

bool _hasDeath(int memberId) => gameState.playthroughEvents.any(
  (event) =>
      event.gameId == gameState.uniqueGameId &&
      event.type == PlaythroughEventType.memberDied &&
      event.data['memberId'] == memberId,
);

/// Capture only at a proved lethal resolver, before its death mutation. This
/// object never kills anyone: the caller confirms its resolved death via record.
class MemberDeathRecord {
  MemberDeathRecord._(this._member, this._state, this._data);

  static MemberDeathRecord? capture(
    Creature member,
    MemberDeathCause cause, {
    Site? sourceSite,
    Creature? actor,
    Vehicle? vehicle,
    Map<String, dynamic>? context,
  }) {
    if (!member.alive || !hasMemberHistoryEvidence(member)) return null;
    // No resurrection model exists. Refuse duplicate history without changing
    // or interrupting gameplay, even if its life flag is inconsistent.
    if (_hasDeath(member.id)) return null;
    final site = historySiteSnapshot(sourceSite);
    final data = <String, dynamic>{
      'memberId': member.id,
      'memberName': member.name,
      'memberTypeId': member.typeId,
      'memberTypeName': member.type.name,
      'cause': cause.wireName,
      if (site != null) 'sourceSite': site,
      if (context != null) 'context': context,
      if (actor != null &&
          (cause == MemberDeathCause.combatInjury ||
              cause == MemberDeathCause.chaseViolence ||
              cause == MemberDeathCause.execution))
        'actor': {
          'actorId': actor.id,
          'actorName': actor.name,
          'actorTypeId': actor.typeId,
          'actorTypeName': actor.type.name,
          'role': switch (cause) {
            MemberDeathCause.combatInjury => 'attacker',
            MemberDeathCause.chaseViolence => 'pursuer',
            _ => 'executioner',
          },
        },
      if (vehicle != null && cause == MemberDeathCause.vehicleCrash)
        'vehicle': {
          'vehicleId': vehicle.id,
          'vehicleType': vehicle.typeName,
          'vehicleName': vehicle.fullName(),
        },
    };
    return MemberDeathRecord._(
      member,
      gameState,
      jsonDecode(jsonEncode(data)) as Map<String, dynamic>,
    );
  }

  final Creature _member;
  final GameState _state;
  final Map<String, dynamic> _data;

  void record() {
    if (!identical(gameState, _state)) return;
    if (_member.alive || _hasDeath(_member.id)) return;
    logPlaythroughEvent(
      gameDate: date,
      type: PlaythroughEventType.memberDied,
      data: _data,
    );
  }
}
