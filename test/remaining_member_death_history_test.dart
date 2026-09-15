@TestOn('vm')
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/review_mode.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/daily/advance_day.dart';
import 'package:lcs_new_age/daily/siege.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/justice/prison.dart';
import 'package:lcs_new_age/location/city.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/playthrough_log/campaign_history_archive.dart';
import 'package:lcs_new_age/playthrough_log/member_death_history.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_log.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

class _Input extends Console {
  _Input([this.keys = const []]);
  final List<int> keys;
  int count = 0;
  @override
  Future<String> getkey() async {
    if (count > 200) throw StateError('Unexpected input loop');
    final key = count < keys.length ? keys[count] : Key.enter;
    count++;
    return String.fromCharCode(key);
  }
}

void main() {
  setUpAll(ensureGameDataLoaded);
  late GameState previousState;
  late Console previousConsole;
  late Creature member;
  late Creature survivor;
  late Site site;

  void fixture() {
    gameState = GameState();
    console = _Input();
    reseedRNG(seed: 42);
    final city = City('City', 'City', '');
    cities.add(city);
    city.addDistrict('District', '').addSites([
      SiteType.warehouse,
      SiteType.homelessEncampment,
      SiteType.policeStation,
      SiteType.prison,
      SiteType.whiteHouse,
      SiteType.ceoHouse,
    ]);
    site = sites.first;
    site.controller = SiteController.lcs;
    activeSite = site;
    activeSafehouse = site;
    member = Creature.fromId(CreatureTypeIds.lawyer, align: Alignment.liberal)
      ..name = 'Member'
      ..birthDate = DateTime(1990)
      ..location = site
      ..base = site;
    survivor = Creature.fromId(CreatureTypeIds.lawyer, align: Alignment.liberal)
      ..name = 'Survivor'
      ..birthDate = DateTime(1990)
      ..location = sites[1]
      ..base = sites[1];
    pool.addAll([member, survivor]);
    squads.add(Squad()..name = 'Squad');
    activeSquad = squads.single;
    member.squad = activeSquad;
    reseedRNG(seed: 42);
  }

  setUp(() {
    previousState = gameState;
    previousConsole = console;
    fixture();
  });
  tearDown(() {
    gameState = previousState;
    console = previousConsole;
  });

  void membership(Creature p) => logPlaythroughEvent(
    gameDate: date,
    type: PlaythroughEventType.memberJoined,
    data: {'memberId': p.id},
  );

  List<PlaythroughEvent> deaths() => gameState.playthroughEvents
      .where((e) => e.type == PlaythroughEventType.memberDied)
      .toList();

  void expectDeath(String cause) {
    expect(member.alive, isFalse);
    expect(deaths(), hasLength(1));
    expect(deaths().single.data['memberId'], member.id);
    expect(deaths().single.data['cause'], cause);
    expect((deaths().single.data['sourceSite'] as Map)['siteId'], site.id);
  }

  void besiege({bool food = true, bool fortified = true}) {
    site.siege.activeSiegeType = SiegeType.police;
    site.siege.lightsOff = true;
    site.compound.fortified = fortified;
    site.compound.rations = food ? 100 : 0;
  }

  Future<void> carBomb({bool lethal = true}) async {
    ccsState = CCSStrength.active;
    site.siege.timeuntilccs = 0;
    if (!lethal) member.juice = 1000;
    member.blood = lethal ? 1 : member.maxBlood;
    reseedRNG(seed: 13);
    await siegeCheck();
  }

  Future<void> sniper({bool lethal = true}) async {
    besiege(fortified: false);
    member.juice = lethal ? -100 : 1000;
    reseedRNG(seed: 5);
    await siegeTurn();
  }

  Future<void> airStrike({bool lethal = true}) async {
    besiege();
    site.siege.escalationState = SiegeEscalation.bombers;
    member.juice = lethal ? -100 : 1000;
    reseedRNG(seed: 5);
    await siegeTurn();
  }

  Future<void> campDeath() async {
    site = sites.firstWhere((s) => s.type == SiteType.prison);
    member.location = site;
    member.squad = null;
    member.hireId = survivor.id;
    member.permanentHealthDamage = 1000;
    reseedRNG(seed: 3);
    await laborCamp(member);
  }

  test(
    'old age records once, including repeated processing of the corpse',
    () async {
      member.birthDate = DateTime(1960);
      member.permanentHealthDamage = 1000;
      final seed = Iterable<int>.generate(
        10000,
      ).firstWhere((s) => Random(s).nextInt(1825) == 0);
      reseedRNG(seed: seed);
      await ageThings();
      expectDeath('old_age');
      reseedRNG(seed: seed);
      await ageThings();
      expect(deaths(), hasLength(1));
    },
  );

  test('old age of a pool captive is not a member death', () async {
    member.squad = null;
    member.missing = true;
    member.birthDate = DateTime(1960);
    member.permanentHealthDamage = 1000;
    final seed = Iterable<int>.generate(
      10000,
    ).firstWhere((s) => Random(s).nextInt(1825) == 0);
    reseedRNG(seed: seed);
    await ageThings();
    expect(member.alive, isFalse);
    expect(deaths(), isEmpty);
  });

  test('CCS car bombing records a member once', () async {
    await carBomb();
    expectDeath('car_bomb');
    expect(deaths().single.data['context'], {'attackerFaction': 'ccs'});
    await siegeCheck();
    expect(deaths(), hasLength(1));
  });

  test(
    'siege starvation records once; empty-site corpse cleanup adds nothing',
    () async {
      besiege(food: false);
      member.blood = 1;
      await siegeTurn();
      expectDeath('starvation');
      await siegeTurn();
      expect(pool, isNot(contains(member)));
      expect(deaths(), hasLength(1));
    },
  );

  test(
    'fed siege occupant with depleted blood is not called starvation',
    () async {
      besiege();
      member.blood = -1;
      await siegeTurn();
      expectDeath('injuries');
    },
  );

  test(
    'siege sniper records legacy squad evidence before squad clearing',
    () async {
      await sniper();
      expectDeath('sniper_fire');
      expect(member.squad, isNull);
      await siegeTurn();
      expect(deaths(), hasLength(1));
    },
  );

  test(
    'siege air strike records legacy squad evidence before squad clearing',
    () async {
      await airStrike();
      expectDeath('air_strike');
      expect(member.squad, isNull);
      await siegeTurn();
      expect(deaths(), hasLength(1));
    },
  );

  for (final surrender in [true, false]) {
    test(
      'lethal siege ${surrender ? 'surrender' : 'defeat'} records members only once',
      () async {
        site.siege.activeSiegeType = SiegeType.ccs;
        final captive =
            Creature.fromId(CreatureTypeIds.lawyer, align: Alignment.liberal)
              ..location = site
              ..missing = true;
        pool.add(captive);
        Future<void> resolve() =>
            surrender ? surrenderAndDie(site) : siegeDefeat();
        await resolve();
        expectDeath('massacre');
        expect(deaths().single.data['context'], {
          'siegeOutcome': surrender ? 'surrender' : 'defeat',
        });
        expect(captive.alive, isFalse);
        expect(member.squad, isNull);
        // Repeat the resolver on retained corpses without inventing a new death.
        member.location = site;
        captive.location = site;
        site.siege.activeSiegeType = SiegeType.ccs;
        await resolve();
        expect(deaths(), hasLength(1));
      },
    );
  }

  test(
    'state execution records once; the later execution cleanup cannot duplicate',
    () async {
      site = sites.firstWhere((s) => s.type == SiteType.prison);
      member.location = site;
      member.squad = null;
      membership(member);
      member.deathPenalty = true;
      member.sentence = 1;
      laws[Law.deathPenalty] = DeepAlignment.moderate;
      await prison(member);
      expectDeath('execution');
      expect(deaths().single.data['context'], {'executionAuthority': 'state'});
      expect(deaths().single.data, isNot(contains('actor')));
      member.die(); // Existing monthly execution cleanup's repeated mutation.
      member.sentence = 1;
      await prison(member);
      expect(deaths(), hasLength(1));
    },
  );

  test(
    'literal labor camp death snapshots prison before location is cleared',
    () async {
      membership(member);
      await campDeath();
      expectDeath('prison_death');
      expect(member.location, isNull);
      await laborCamp(member);
      expect(deaths(), hasLength(1));
    },
  );

  test('confirmed player execution records the factual executioner', () async {
    survivor.location = site;
    survivor.rawAttributes[Attribute.heart] = 100;
    member.hireId = survivor.id;
    console = _Input([Key.a, Key.k, Key.c]);
    await reviewMode(ReviewMode.liberals);
    expectDeath('execution');
    expect(deaths().single.data['context'], {'executionAuthority': 'lcs'});
    expect((deaths().single.data['actor'] as Map)['actorId'], survivor.id);
    expect((deaths().single.data['actor'] as Map)['role'], 'executioner');
  });

  test('canceled player execution changes no life or death history', () async {
    survivor.location = site;
    member.hireId = survivor.id;
    console = _Input([Key.a, Key.k, Key.enter]);
    await reviewMode(ReviewMode.liberals);
    expect(member.alive, isTrue);
    expect(deaths(), isEmpty);
  });

  for (final route in [
    'car_bomb',
    'starvation',
    'sniper_fire',
    'air_strike',
    'execution',
    'prison_death',
  ]) {
    test('$route rejects a Liberal captive despite pool presence', () async {
      member.squad = null;
      member.missing = true;
      switch (route) {
        case 'car_bomb':
          await carBomb();
        case 'starvation':
          besiege(food: false);
          member.blood = 1;
          await siegeTurn();
        case 'sniper_fire':
          await sniper();
        case 'air_strike':
          await airStrike();
        case 'execution':
          member.location = sites.firstWhere((s) => s.type == SiteType.prison);
          member.deathPenalty = true;
          member.sentence = 1;
          laws[Law.deathPenalty] = DeepAlignment.moderate;
          await prison(member);
        case 'prison_death':
          await campDeath();
      }
      expect(member.alive, isFalse);
      expect(deaths(), isEmpty);
    });
  }

  for (final route in ['car_bomb', 'starvation', 'sniper_fire', 'air_strike']) {
    test('nonfatal $route emits no death', () async {
      switch (route) {
        case 'car_bomb':
          await carBomb(lethal: false);
        case 'starvation':
          besiege(food: false);
          await siegeTurn();
        case 'sniper_fire':
          await sniper(lethal: false);
        case 'air_strike':
          await airStrike(lethal: false);
      }
      expect(member.alive, isTrue);
      expect(deaths(), isEmpty);
    });
  }

  test('commuted death sentence is not an execution', () async {
    member.location = sites.firstWhere((s) => s.type == SiteType.prison);
    member.deathPenalty = true;
    member.sentence = 1;
    laws[Law.deathPenalty] = DeepAlignment.eliteLiberal;
    await prison(member);
    expect(member.alive, isTrue);
    expect(member.deathPenalty, isFalse);
    expect(deaths(), isEmpty);
  });

  for (final siegeType in [SiegeType.police, SiegeType.medicalDebtCollectors]) {
    for (final surrender in [true, false]) {
      test(
        'nonlethal $siegeType ${surrender ? 'surrender' : 'defeat'} emits no death',
        () async {
          site.siege.activeSiegeType = siegeType;
          console = _Input([Key.c]);
          if (surrender) {
            await giveUp(site);
          } else {
            await siegeDefeat();
          }
          expect(member.alive, isTrue);
          expect(deaths(), isEmpty);
        },
      );
    }
  }

  test(
    'new cause wires and detached context survive state and archive JSON',
    () {
      const causes = {
        MemberDeathCause.oldAge: 'old_age',
        MemberDeathCause.carBomb: 'car_bomb',
        MemberDeathCause.starvation: 'starvation',
        MemberDeathCause.sniperFire: 'sniper_fire',
        MemberDeathCause.airStrike: 'air_strike',
        MemberDeathCause.massacre: 'massacre',
        MemberDeathCause.execution: 'execution',
        MemberDeathCause.prisonDeath: 'prison_death',
      };
      for (final entry in causes.entries) {
        expect(entry.key.wireName, entry.value);
        final p = Creature.fromId(CreatureTypeIds.lawyer);
        pool.add(p);
        membership(p);
        final context = <String, dynamic>{
          'details': {'route': 'test'},
        };
        final pending = MemberDeathRecord.capture(
          p,
          entry.key,
          context: context,
        )!;
        p.die();
        pending.record();
        (context['details'] as Map)['route'] = 'changed';
        expect((deaths().last.data['context'] as Map)['details'], {
          'route': 'test',
        });
      }
      final expected = jsonDecode(jsonEncode(gameState.toJson()));
      final restored = GameState.fromJson(expected as Map<String, dynamic>);
      expect(
        restored.playthroughEvents.map((e) => e.toJson()),
        gameState.playthroughEvents.map((e) => e.toJson()),
      );
      final archive = CampaignHistoryArchive(
        archiveId: 'death-causes',
        gameId: restored.uniqueGameId,
        finalGameDate: restored.date,
        completedAt: DateTime.utc(2026),
        finalSequence: restored.playthroughSequence,
        outcome: CampaignOutcome.defeat,
        route: CampaignEndRoute.noQualifyingMembers,
        events: restored.playthroughEvents,
      );
      expect(
        CampaignHistoryArchive.fromJson(
          jsonDecode(jsonEncode(archive.toJson())) as Map<String, dynamic>,
        ).toJson(),
        archive.toJson(),
      );
    },
  );
}
