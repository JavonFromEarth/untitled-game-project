@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/daily/siege.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/items/attack.dart';
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/items/weapon.dart';
import 'package:lcs_new_age/justice/crimes.dart';
import 'package:lcs_new_age/location/city.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/newspaper/news_story.dart';
import 'package:lcs_new_age/playthrough_log/campaign_history_archive.dart';
import 'package:lcs_new_age/playthrough_log/member_death_history.dart';
import 'package:lcs_new_age/playthrough_log/member_history.dart';
import 'package:lcs_new_age/playthrough_log/operation_history.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_log.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/saveload/storage/sembast_storage.dart';
import 'package:lcs_new_age/scores/score_repository.dart';
import 'package:lcs_new_age/sitemode/chase_sequence.dart';
import 'package:lcs_new_age/sitemode/fight.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/sitemode/sitemode.dart';
import 'package:lcs_new_age/title_screen/campaign_ending.dart';
import 'package:lcs_new_age/title_screen/launch_game.dart'
    show EndGameException;
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

class _Input extends Console {
  _Input(this.onKey);
  final Future<int> Function() onKey;
  int count = 0;
  @override
  Future<String> getkey() async {
    if (++count > 300) throw StateError('Unexpected input loop in $mode');
    return String.fromCharCode(await onKey());
  }
}

void main() {
  setUpAll(ensureGameDataLoaded);
  late GameState previousState;
  late Console previousConsole;
  late Site site;
  late List<Creature> members;
  late Creature attacker;

  setUp(() {
    previousState = gameState;
    previousConsole = console;
    gameState = GameState();
    reseedRNG(seed: 42);
    final city = City('Bronx', 'Bronx', '');
    cities.add(city);
    city.addDistrict('District', '').addSites([
      SiteType.warehouse,
      SiteType.homelessEncampment,
      SiteType.publicPark,
      SiteType.policeStation,
      SiteType.drugHouse,
      SiteType.whiteHouse,
      SiteType.ceoHouse,
    ]);
    site = sites.first;
    site.controller = SiteController.unaligned;
    site.mapseed = 42;
    activeSite = site;
    activeSafehouse = site;
    squads.add(Squad()..name = 'Squad');
    activeSquad = squads.single;
    members = List.generate(3, (i) {
      final p =
          Creature.fromId(CreatureTypeIds.lawyer, align: Alignment.liberal)
            ..name = 'Member $i'
            ..birthDate = DateTime(1990)
            ..location = site
            ..base = sites[1]
            ..equippedWeapon = (i == 2 ? null : Weapon('WEAPON_COMBATKNIFE'))
            ..equippedClothing = (i == 2 ? null : Clothing('CLOTHING_CLOTHES'));
      pool.add(p);
      p.squad = activeSquad;
      return p;
    });
    members.first.equippedClothing!
      ..bloody = true
      ..damaged = true;
    attacker = Creature.fromId(
      CreatureTypeIds.lawyer,
      align: Alignment.conservative,
    )..name = 'Attacker';
    sitestory = NewsStory.unpublished(NewsStories.squadSiteAction)..loc = site;
    console = _Input(() async => Key.enter);
    reseedRNG(seed: 42);
  });

  tearDown(() {
    gameState = previousState;
    console = previousConsole;
  });

  List<PlaythroughEvent> events(PlaythroughEventType type) =>
      gameState.playthroughEvents.where((e) => e.type == type).toList();

  Future<void> kill(Creature member) => hit(
    attacker,
    member,
    Attack()..damage = 100000,
    member.body.parts.firstWhere((part) => part.critical),
    false,
    false,
    1,
  );

  CampaignHistoryArchive archive(GameState state) => CampaignHistoryArchive(
    archiveId: 'test-archive',
    gameId: state.uniqueGameId,
    finalGameDate: state.date,
    completedAt: DateTime.utc(2026),
    finalSequence: state.playthroughSequence,
    outcome: CampaignOutcome.defeat,
    route: CampaignEndRoute.noQualifyingMembers,
    events: state.playthroughEvents,
  );

  test('logger returns the identical appended event and actual sequence', () {
    gameState.playthroughSequence = 30;
    final event = logPlaythroughEvent(
      gameDate: date,
      type: PlaythroughEventType.memberJoined,
    );
    expect(identical(event, gameState.playthroughEvents.single), isTrue);
    expect(event.sequence, 31);
    expect(event.sequence, gameState.playthroughSequence);
  });

  test(
    'start snapshots site, controller, squad, living participants and real equipped gear',
    () {
      final dead = Creature.fromId(CreatureTypeIds.lawyer)..alive = false;
      pool.add(dead);
      dead.squad = activeSquad;
      final operation = beginOperation(site, OperationKind.siteAction)!;
      final start = events(PlaythroughEventType.operationStarted).single;
      expect(start.type.wireName, 'operation_started');
      expect(operation.startSequence, start.sequence);
      expect(gameState.activeOperationStartSequence, start.sequence);
      expect(start.data['operationKind'], 'site_action');
      expect(start.data['site'], historySiteSnapshot(site));
      expect(start.data['controller'], 'unaligned');
      expect(start.data['squadId'], activeSquad!.id);
      expect(start.data['squadName'], 'Squad');
      final participants = start.data['participants'] as List;
      expect(participants, hasLength(3));
      final first = participants.first as Map;
      expect(first['memberId'], members.first.id);
      expect(first['memberName'], members.first.name);
      expect(first['memberTypeId'], members.first.typeId);
      expect(first['memberTypeName'], members.first.type.name);
      expect(first['weapon'], {
        'weaponTypeId': 'WEAPON_COMBATKNIFE',
        'weaponTypeName': members.first.equippedWeapon!.type.name,
      });
      expect(first['clothing'], {
        'clothingTypeId': 'CLOTHING_CLOTHES',
        'clothingTypeName': members.first.equippedClothing!.type.name,
        'bloody': true,
        'damaged': true,
      });
      expect(participants.last, isNot(contains('weapon')));
      expect(participants.last, isNot(contains('clothing')));
      final original = jsonEncode(start.toJson());
      members.first.name = 'Renamed';
      members.first.equippedClothing!.bloody = false;
      members.first.equippedWeapon = null;
      activeSquad!.name = 'Renamed squad';
      site.name = 'Renamed site';
      cities.single.name = 'Renamed city';
      pool.clear();
      expect(jsonEncode(start.toJson()), original);
    },
  );

  test(
    'invalid and nested starts refuse safely; clearing does not fabricate resolution',
    () {
      expect(beginOperation(site, OperationKind.siege), isNull);
      activeSquad = null;
      expect(beginOperation(site, OperationKind.siteAction), isNull);
      activeSquad = squads.single;
      for (final m in members) {
        m.alive = false;
      }
      expect(beginOperation(site, OperationKind.siteAction), isNull);
      members.first.alive = true;
      final op = beginOperation(site, OperationKind.siteAction)!;
      expect(beginOperation(site, OperationKind.siteAction), isNull);
      expect(events(PlaythroughEventType.operationStarted), hasLength(1));
      expect(gameState.activeOperationStartSequence, op.startSequence);
      op.clear();
      op.clear();
      expect(op.resolve(OperationResolutionPath.siteExit), isNull);
      expect(events(PlaythroughEventType.operationResolved), isEmpty);
    },
  );

  for (final outcome in ChaseOutcome.values) {
    test('exact ${outcome.name} chase outcome survives resolution', () {
      final op = beginOperation(site, OperationKind.siteAction)!;
      site.controller = SiteController.lcs;
      final result = op.resolve(
        OperationResolutionPath.siteExit,
        chaseOutcome: outcome,
        siteCrime: 100,
        siteAlarmed: true,
      )!;
      expect(result.type.wireName, 'operation_resolved');
      expect(result.data, {
        'operationStartSequence': op.startSequence,
        'resolutionPath': 'site_exit',
        'chaseOutcome': switch (outcome) {
          ChaseOutcome.victory => 'victory',
          ChaseOutcome.escape => 'escape',
          ChaseOutcome.capture => 'capture',
          ChaseOutcome.death => 'death',
        },
        'controllerBefore': 'unaligned',
        'controllerAfter': 'lcs',
        'siteCrime': 100,
        'siteAlarmed': true,
      });
      expect(
        outcome.won,
        outcome == ChaseOutcome.victory || outcome == ChaseOutcome.escape,
      );
      expect(gameState.activeOperationStartSequence, isNull);
      expect(op.resolve(OperationResolutionPath.siteExit), isNull);
      expect(events(PlaythroughEventType.operationResolved), hasLength(1));
    });
  }

  test('CCS to LCS transition preserves the starting controller', () {
    site.controller = SiteController.ccs;
    final op = beginOperation(site, OperationKind.siteAction)!;
    site.controller = SiteController.lcs;
    final result = op.resolve(OperationResolutionPath.ccsTakeover)!;
    expect(gameState.playthroughEvents.first.data['controller'], 'ccs');
    expect(result.data['controllerBefore'], 'ccs');
    expect(result.data['controllerAfter'], 'lcs');
  });

  test(
    'all siege and escalation wires are explicit and entry facts are detached',
    () {
      const siegeWires = {
        SiegeType.police: 'police',
        SiegeType.cia: 'cia',
        SiegeType.angryRuralMob: 'angry_rural_mob',
        SiegeType.corporateMercs: 'corporate_mercs',
        SiegeType.medicalDebtCollectors: 'medical_debt_collectors',
        SiegeType.ccs: 'ccs',
      };
      const escalationWires = {
        SiegeEscalation.police: 'police',
        SiegeEscalation.nationalGuard: 'national_guard',
        SiegeEscalation.tanks: 'tanks',
        SiegeEscalation.bombers: 'bombers',
      };
      for (final siege in siegeWires.entries) {
        for (final escalation in escalationWires.entries) {
          site.siege.activeSiegeType = siege.key;
          site.siege.underAttack = true;
          site.siege.escalationState = escalation.key;
          final op = beginOperation(site, OperationKind.siege)!;
          final start = gameState.playthroughEvents.last;
          site.siege.activeSiegeType = SiegeType.none;
          site.siege.escalationState = SiegeEscalation.police;
          expect(start.data['siege'], {
            'siegeType': siege.value,
            'underAttack': true,
            'escalation': escalation.value,
          });
          op.resolve(OperationResolutionPath.siegeVictory);
        }
      }
    },
  );

  test(
    'three separate sites get separate start sequences without mission inference',
    () {
      final sequences = <int>[];
      for (final type in [
        SiteType.publicPark,
        SiteType.policeStation,
        SiteType.drugHouse,
      ]) {
        final loc = sites.firstWhere((s) => s.type == type);
        final op = beginOperation(loc, OperationKind.siteAction)!;
        sequences.add(op.startSequence);
        op.resolve(
          OperationResolutionPath.siteExit,
          chaseOutcome: ChaseOutcome.escape,
        );
        op.clear();
      }
      expect(sequences.toSet(), hasLength(3));
      expect(
        events(
          PlaythroughEventType.operationStarted,
        ).map((e) => (e.data['site'] as Map)['siteType']),
        ['public_park', 'police_station', 'drug_house'],
      );
      expect(gameState.activeOperationStartSequence, isNull);
    },
  );

  test(
    'member death snapshots correlation at capture; outside deaths omit it',
    () async {
      mode = GameMode.site;
      final op = beginOperation(site, OperationKind.siteAction)!;
      final pending = MemberDeathRecord.capture(
        members.first,
        MemberDeathCause.injuries,
      )!;
      op.resolve(OperationResolutionPath.siteExit);
      members.first.die();
      pending.record();
      expect(
        events(
          PlaythroughEventType.memberDied,
        ).single.data['operationStartSequence'],
        op.startSequence,
      );
      await kill(members[1]);
      expect(
        events(PlaythroughEventType.memberDied).last.data,
        isNot(contains('operationStartSequence')),
      );
    },
  );

  test(
    'state and archive round trips preserve events but exclude active routing context',
    () async {
      mode = GameMode.site;
      final op = beginOperation(site, OperationKind.siteAction)!;
      await kill(members.first);
      final during =
          jsonDecode(jsonEncode(gameState.toJson())) as Map<String, dynamic>;
      expect(during, isNot(contains('activeOperationStartSequence')));
      during['activeOperationStartSequence'] =
          999; // Must not be restored even if supplied.
      expect(GameState.fromJson(during).activeOperationStartSequence, isNull);
      op.resolve(
        OperationResolutionPath.siteExit,
        chaseOutcome: ChaseOutcome.escape,
      );
      final expected = gameState.playthroughEvents
          .map((e) => e.toJson())
          .toList();
      final restored = GameState.fromJson(
        jsonDecode(jsonEncode(gameState.toJson())) as Map<String, dynamic>,
      );
      expect(
        restored.playthroughEvents.map((e) => e.toJson()).toList(),
        expected,
      );
      final completed = CampaignHistoryArchive.fromJson(
        jsonDecode(jsonEncode(archive(restored).toJson()))
            as Map<String, dynamic>,
      );
      expect(completed.events.map((e) => e.toJson()).toList(), expected);
      final legacy =
          (jsonDecode(jsonEncode(gameState.toJson())) as Map<String, dynamic>)
            ..remove('playthroughEvents')
            ..remove('playthroughSequence');
      expect(GameState.fromJson(legacy).activeOperationStartSequence, isNull);
      expect(GameState().activeOperationStartSequence, isNull);
    },
  );

  test('stale handle cannot resolve into or clear a replacement state', () {
    final previous = gameState;
    final old = beginOperation(site, OperationKind.siteAction)!;
    gameState = GameState()..activeOperationStartSequence = old.startSequence;
    expect(old.resolve(OperationResolutionPath.siteExit), isNull);
    old.clear();
    expect(gameState.activeOperationStartSequence, old.startSequence);
    expect(gameState.playthroughEvents, isEmpty);
    expect(previous.activeOperationStartSequence, isNull);
  });

  test('an old handle cannot clear or resolve the next operation', () {
    final first = beginOperation(site, OperationKind.siteAction)!;
    first.resolve(OperationResolutionPath.siteExit);
    final second = beginOperation(site, OperationKind.siteAction)!;
    first.clear();
    expect(first.resolve(OperationResolutionPath.siteExit), isNull);
    expect(gameState.activeOperationStartSequence, second.startSequence);
    second.resolve(OperationResolutionPath.siteExit);
    expect(events(PlaythroughEventType.operationResolved), hasLength(2));
  });

  test(
    'real siteMode squad-destroyed return resolves if another member survives elsewhere',
    () async {
      final reserve =
          Creature.fromId(CreatureTypeIds.lawyer, align: Alignment.liberal)
            ..location = sites[1]
            ..base = sites[1];
      pool.add(reserve);
      bool killed = false;
      console = _Input(() async {
        if (!killed) {
          killed = true;
          for (final member in members) {
            await kill(member);
          }
        }
        return Key.c;
      });
      await siteMode(site);
      expect(events(PlaythroughEventType.operationStarted), hasLength(1));
      expect(events(PlaythroughEventType.memberDied), hasLength(3));
      expect(
        events(
          PlaythroughEventType.operationResolved,
        ).single.data['resolutionPath'],
        'squad_destroyed',
      );
      expect(gameState.activeOperationStartSequence, isNull);
    },
  );

  test(
    'real siteMode CCS takeover records the changed controller after resolution',
    () async {
      site.controller = SiteController.ccs;
      bool triggered = false;
      console = _Input(() async {
        if (!triggered) {
          triggered = true;
          ccsBossKills = 1;
          currentTile.exit = false;
          return Key.s;
        }
        return Key.c;
      });
      await siteMode(site);
      final resolved = events(PlaythroughEventType.operationResolved).single;
      expect(resolved.data['resolutionPath'], 'ccs_takeover');
      expect(resolved.data['controllerBefore'], 'ccs');
      expect(resolved.data['controllerAfter'], 'lcs');
      expect(gameState.activeOperationStartSequence, isNull);
    },
  );

  test(
    'real siteMode siege victory resolves after the siege is broken',
    () async {
      site.controller = SiteController.lcs;
      site.siege.activeSiegeType = SiegeType.police;
      site.siege.underAttack = true;
      bool triggered = false;
      console = _Input(() async {
        if (!triggered) {
          triggered = true;
          site.siege.kills = 10;
          site.siege.tanks = 0;
          for (final tile in levelMap.all) {
            tile.siegeflag = 0;
          }
          currentTile.exit = false;
          return Key.s;
        }
        return Key.c;
      });
      await siteMode(site);
      expect(site.siege.underSiege, isFalse);
      expect(
        events(
          PlaythroughEventType.operationStarted,
        ).single.data['operationKind'],
        'siege',
      );
      final resolved = events(PlaythroughEventType.operationResolved).single;
      expect(resolved.data['resolutionPath'], 'siege_victory');
      expect(resolved.data, isNot(contains('chaseOutcome')));
      expect(gameState.activeOperationStartSequence, isNull);
    },
  );

  for (final outcome in [
    ChaseOutcome.victory,
    ChaseOutcome.capture,
    ChaseOutcome.death,
  ]) {
    test(
      'real sallyForthPart3 preserves ${outcome.name} at its switch branch',
      () async {
        site.controller = SiteController.lcs;
        site.siege.activeSiegeType = SiegeType.police;
        final reserve =
            Creature.fromId(CreatureTypeIds.lawyer, align: Alignment.liberal)
              ..location = sites[1]
              ..base = sites[1];
        pool.add(reserve);
        bool arranged = false;
        console = _Input(() async {
          if (!arranged && mode == GameMode.footChase) {
            arranged = true;
            switch (outcome) {
              case ChaseOutcome.victory:
                // Set the encounter's resolved state; run the actual chase exit
                // and all siege/world resolution below it.
                encounter.clear();
              case ChaseOutcome.capture:
                chaseSequence!.canpullover = true;
                return Key.g;
              case ChaseOutcome.death:
                for (final member in members) {
                  await kill(member);
                }
              case ChaseOutcome.escape:
                fail('Escape is covered by the real pursuit test');
            }
          }
          return Key.c;
        });
        final result = await sallyForthPart3(site);
        expect(
          result,
          outcome == ChaseOutcome.victory
              ? SallyForthResult.brokeSiege
              : SallyForthResult.defeated,
        );
        final resolved = events(PlaythroughEventType.operationResolved).single;
        expect(resolved.data['chaseOutcome'], outcome.name);
        expect(
          resolved.data['resolutionPath'],
          outcome == ChaseOutcome.victory ? 'siege_victory' : 'siege_defeat',
        );
        expect(gameState.activeOperationStartSequence, isNull);
      },
    );
  }

  test('real siteMode with no active squad creates no operation', () async {
    activeSquad = null;
    await siteMode(site);
    expect(gameState.playthroughEvents, isEmpty);
    expect(gameState.activeOperationStartSequence, isNull);
  });

  test(
    'real siteMode: three enter, one dies, two escape through chase and site changes controller',
    () async {
      for (final m in members) {
        m.rawAttributes[Attribute.agility] = 1000;
      }
      bool injected = false;
      bool sawPursuit = false;
      console = _Input(() async {
        if (!injected && mode == GameMode.site) {
          injected = true;
          expect(events(PlaythroughEventType.operationStarted), hasLength(1));
          await kill(members.first);
          currentTile.exit = true;
          siteAlarm = true;
          siteCrime = 1000;
          postAlarmTimer = 100;
          members[1].wantedForCrimes[Crime.murder] = 1;
          return Key.s;
        }
        if (mode == GameMode.footChase) {
          sawPursuit |= encounter.isNotEmpty;
          return Key.d;
        }
        return Key.enter;
      });
      await siteMode(site);
      expect(sawPursuit, isTrue);
      expect(gameState.playthroughEvents.map((e) => e.type), [
        PlaythroughEventType.operationStarted,
        PlaythroughEventType.memberDied,
        PlaythroughEventType.operationResolved,
      ]);
      final start = gameState.playthroughEvents.first;
      final death = gameState.playthroughEvents[1];
      final resolved = gameState.playthroughEvents.last;
      expect(start.data['participants'] as List, hasLength(3));
      expect(death.data['operationStartSequence'], start.sequence);
      expect(resolved.data['operationStartSequence'], start.sequence);
      expect(resolved.data['chaseOutcome'], 'escape');
      expect(resolved.data['resolutionPath'], 'site_exit');
      expect(resolved.data['controllerBefore'], 'unaligned');
      expect(resolved.data['controllerAfter'], 'lcs');
      expect(resolved.data['siteAlarmed'], isTrue);
      expect(members.where((m) => m.alive), hasLength(2));
      expect(gameState.activeOperationStartSequence, isNull);
    },
  );

  test('real sallyForthPart3 escape uses the same operation family', () async {
    site.controller = SiteController.lcs;
    site.siege.activeSiegeType = SiegeType.police;
    site.siege.underAttack = true;
    for (final m in members) {
      m.rawAttributes[Attribute.agility] = 1000;
    }
    console = _Input(
      () async => mode == GameMode.footChase ? Key.d : Key.enter,
    );
    expect(await sallyForthPart3(site), SallyForthResult.escaped);
    expect(gameState.playthroughEvents.map((e) => e.type), [
      PlaythroughEventType.operationStarted,
      PlaythroughEventType.operationResolved,
    ]);
    final start = gameState.playthroughEvents.first;
    final resolved = gameState.playthroughEvents.last;
    expect(start.data['operationKind'], 'siege');
    expect(start.data['participants'] as List, hasLength(3));
    expect(resolved.data['resolutionPath'], 'siege_escape');
    expect(resolved.data['chaseOutcome'], 'escape');
    expect(resolved.data['operationStartSequence'], start.sequence);
    expect(gameState.activeOperationStartSequence, isNull);
  });

  test(
    'exception leaving siteMode clears routing without inventing a resolution',
    () async {
      console = _Input(() async => throw StateError('interrupted input'));
      await expectLater(siteMode(site), throwsStateError);
      expect(events(PlaythroughEventType.operationStarted), hasLength(1));
      expect(events(PlaythroughEventType.operationResolved), isEmpty);
      expect(gameState.activeOperationStartSequence, isNull);
    },
  );

  test(
    'terminal campaign archives an open operation with linked deaths',
    () async {
      final directory = await Directory.systemTemp.createTemp('lcs_operation_');
      final storage = SembastStorage(databasePath: '${directory.path}/game.db');
      await storage.init();
      addTearDown(() async {
        await storage.close();
        await directory.delete(recursive: true);
      });
      SharedPreferences.setMockInitialValues({});
      final scores = ScoreRepository(storage);
      await scores.initialize(await SharedPreferences.getInstance());
      bool ending = false;
      final failures = <Object>[];
      final state = gameState;
      console = _Input(() async {
        if (!ending) {
          ending = true;
          for (final member in members) {
            await kill(member);
          }
          await completeCampaignEnding(
            CampaignEnding.noQualifyingMembers(),
            scores: scores,
            presentEnding: () async {},
            presentScores: (_) async {},
            presentFailure: (e) async => failures.add(e),
          );
        }
        return Key.enter;
      });
      await expectLater(siteMode(site), throwsA(isA<EndGameException>()));
      expect(failures, isEmpty);
      expect(state.activeOperationStartSequence, isNull);
      expect(state.playthroughEvents.map((e) => e.type), [
        PlaythroughEventType.operationStarted,
        ...List.filled(3, PlaythroughEventType.memberDied),
        PlaythroughEventType.campaignEnded,
      ]);
      final id = state.playthroughEvents.last.data['archiveId'] as String;
      final completed = (await storage.loadArchive(id))!;
      for (final death in completed.events.where(
        (e) => e.type == PlaythroughEventType.memberDied,
      )) {
        expect(
          death.data['operationStartSequence'],
          completed.events.first.sequence,
        );
      }
      expect(completed.events.last.type, PlaythroughEventType.campaignEnded);
      expect(
        completed.events.any(
          (e) => e.type == PlaythroughEventType.operationResolved,
        ),
        isFalse,
      );
    },
  );
}
