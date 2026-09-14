@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/disbanding.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/daily/activities/bury_dead.dart';
import 'package:lcs_new_age/daily/advance_day.dart';
import 'package:lcs_new_age/daily/dating.dart';
import 'package:lcs_new_age/daily/hostages/tend_hostage.dart';
import 'package:lcs_new_age/daily/hostages/traumatize.dart';
import 'package:lcs_new_age/daily/recruitment.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/items/attack.dart';
import 'package:lcs_new_age/justice/prison.dart';
import 'package:lcs_new_age/location/city.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/newspaper/news_story.dart';
import 'package:lcs_new_age/playthrough_log/campaign_completion.dart';
import 'package:lcs_new_age/playthrough_log/campaign_history_archive.dart';
import 'package:lcs_new_age/playthrough_log/member_death_history.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_log.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/saveload/storage/sembast_storage.dart';
import 'package:lcs_new_age/scores/score_repository.dart';
import 'package:lcs_new_age/sitemode/advance.dart';
import 'package:lcs_new_age/sitemode/chase_sequence.dart';
import 'package:lcs_new_age/sitemode/fight.dart';
import 'package:lcs_new_age/sitemode/haul_kidnap.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/title_screen/campaign_ending.dart';
import 'package:lcs_new_age/title_screen/game_over.dart';
import 'package:lcs_new_age/title_screen/launch_game.dart'
    show EndGameException;
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

class _Input extends Console {
  int count = 0;
  @override
  Future<String> getkey() async {
    if (++count > 200) throw StateError('Unexpected input loop');
    return String.fromCharCode(Key.enter);
  }
}

void main() {
  setUpAll(ensureGameDataLoaded);
  late GameState previousState;
  late Console previousConsole;
  late Creature member;
  late Creature attacker;

  Creature person([Alignment align = Alignment.liberal]) {
    final p = Creature.fromId(CreatureTypeIds.lawyer, align: align);
    p.nameCreature();
    p.location = activeSite;
    p.base = activeSite;
    return p;
  }

  void evidence(
    Creature p, [
    PlaythroughEventType type = PlaythroughEventType.memberJoined,
  ]) {
    logPlaythroughEvent(
      gameDate: date,
      type: type,
      data: {
        switch (type) {
          PlaythroughEventType.campaignFounded => 'founderId',
          PlaythroughEventType.recruitJoined => 'recruitId',
          _ => 'memberId',
        }: p.id,
      },
    );
  }

  List<PlaythroughEvent> deaths() => gameState.playthroughEvents
      .where((e) => e.type == PlaythroughEventType.memberDied)
      .toList();

  setUp(() {
    previousState = gameState;
    previousConsole = console;
    gameState = GameState();
    console = _Input();
    reseedRNG(seed: 42);
    final city = City('City', 'City', '');
    cities.add(city);
    city.addDistrict('District', '').addSites([
      SiteType.warehouse,
      SiteType.whiteHouse,
      SiteType.ceoHouse,
      SiteType.policeStation,
      SiteType.prison,
    ]);
    activeSite = sites.first;
    activeSite!.controller = SiteController.lcs;
    mode = GameMode.site;
    currentTile.flag = 0;
    sitestory = NewsStory.unpublished(NewsStories.squadSiteAction)
      ..loc = activeSite;
    member = person();
    pool.add(member);
    squads.add(Squad()..name = 'Squad');
    activeSquad = squads.single;
    member.squad = activeSquad;
    attacker = person(Alignment.conservative);
  });

  tearDown(() {
    currentTile.flag = 0;
    gameState = previousState;
    console = previousConsole;
  });

  Future<void> strike(Creature target, {bool lethal = true}) => hit(
    attacker,
    target,
    Attack()..damage = lethal ? 100000 : 5,
    target.body.parts.firstWhere((p) => p.critical),
    false,
    false,
    1,
  );

  group('membership evidence', () {
    for (final type in [
      PlaythroughEventType.memberJoined,
      PlaythroughEventType.campaignFounded,
      PlaythroughEventType.recruitJoined,
    ]) {
      test(
        'persisted ${type.wireName} qualifies a pool member without role anchors',
        () {
          final p = person();
          pool.add(p);
          expect(p.squad, isNull);
          expect(p.hireId, isNull);
          evidence(p, type);
          expect(hasMemberHistoryEvidence(p), isTrue);
        },
      );
    }
    test('historical member outside pool cannot qualify for death history', () {
      evidence(member);
      pool.remove(member);
      expect(hasMemberHistoryEvidence(member), isFalse);
      expect(
        MemberDeathRecord.capture(member, MemberDeathCause.combatInjury),
        isNull,
      );
      expect(member.alive, isTrue);
      expect(deaths(), isEmpty);
    });
    test('other campaign history is not evidence', () {
      final p = person();
      pool.add(p);
      evidence(p);
      gameState.uniqueGameId++;
      expect(hasMemberHistoryEvidence(p), isFalse);
    });
    test('legacy squad, sleeper, and anchored command chain are supported', () {
      expect(hasMemberHistoryEvidence(member), isTrue);
      final p = person()..hireId = member.id;
      pool.add(p);
      expect(hasMemberHistoryEvidence(p), isTrue);
      member.squad = null;
      expect(hasMemberHistoryEvidence(p), isFalse);
      member.sleeperAgent = true;
      expect(hasMemberHistoryEvidence(member), isTrue);
      expect(hasMemberHistoryEvidence(p), isTrue);
    });
    test(
      'bare roster, alignment, dangling hire and command cycles are insufficient',
      () {
        member.squad = null;
        expect(hasMemberHistoryEvidence(member), isFalse);
        member.hireId = -999;
        expect(hasMemberHistoryEvidence(member), isFalse);
        final p = person()..hireId = member.id;
        pool.add(p);
        member.hireId = p.id;
        expect(hasMemberHistoryEvidence(member), isFalse);
      },
    );
    test('captives and unresolved prospects cannot use runtime fallback', () {
      member.missing = true;
      expect(hasMemberHistoryEvidence(member), isFalse);
      member.missing = false;
      member.kidnapped = true;
      expect(hasMemberHistoryEvidence(member), isFalse);
      member.kidnapped = false;
      interrogationSessions.add(InterrogationSession(member.id));
      expect(hasMemberHistoryEvidence(member), isFalse);
      interrogationSessions.clear();
      datingSessions.add(
        DatingSession(attacker.id, cities.single)..dates.add(member),
      );
      expect(hasMemberHistoryEvidence(member), isFalse);
      datingSessions.clear();
      recruitmentSessions.add(RecruitmentSession(member, attacker));
      expect(hasMemberHistoryEvidence(member), isFalse);
      evidence(member);
      expect(hasMemberHistoryEvidence(member), isTrue);
    });
  });

  group('direct combat', () {
    test(
      'legacy member lethal hit emits once; later hits do not duplicate',
      () async {
        await strike(member);
        expect(member.alive, isFalse);
        expect(pool, contains(member));
        expect(deaths().single.data['cause'], 'combat_injury');
        await strike(member);
        expect(deaths(), hasLength(1));
      },
    );
    test('nonfatal hit emits nothing', () async {
      final blood = member.blood;
      await strike(member, lethal: false);
      expect(member.alive, isTrue);
      expect(member.blood, lessThan(blood));
      expect(deaths(), isEmpty);
    });
    test(
      'persisted membership survives loss of runtime command evidence',
      () async {
        member.squad = null;
        member.hireId = null;
        evidence(member);
        await strike(member);
        expect(deaths().single.data['memberId'], member.id);
      },
    );
    test('friendly fire snapshots an attacker, not an enemy label', () async {
      attacker.align = Alignment.liberal;
      await strike(member);
      expect(deaths().single.data['actor'], {
        'actorId': attacker.id,
        'actorName': attacker.name,
        'actorTypeId': attacker.typeId,
        'actorTypeName': attacker.type.name,
        'role': 'attacker',
      });
    });
    for (final align in Alignment.values) {
      test(
        '${align.name} nonmember death emits nothing even in pool',
        () async {
          final p = person(align);
          pool.add(p);
          await strike(p);
          expect(p.alive, isFalse);
          expect(deaths(), isEmpty);
        },
      );
    }
  });

  group('fire and bleeding', () {
    Future<void> aftermath({
      bool fire = false,
      bool bleed = false,
      bool fatal = true,
      int seed = 1,
    }) async {
      currentTile.firePeak = fire;
      member.rawAttributes[Attribute.heart] = 0;
      member.blood = fatal ? 1 : member.maxBlood;
      if (bleed) member.body.parts.first.bleeding = fatal ? 20 : 1;
      reseedRNG(seed: seed);
      await advancecreature(member);
    }

    test('fatal fire', () async {
      await aftermath(fire: true, seed: 0);
      expect(member.alive, isFalse);
      expect(deaths().single.data['cause'], 'fire');
      expect(
        (deaths().single.data['sourceSite'] as Map)['siteId'],
        activeSite!.id,
      );
    });
    test('fatal bleeding has no inferred attacker', () async {
      await aftermath(bleed: true);
      expect(deaths().single.data['cause'], 'bleeding');
      expect(deaths().single.data, isNot(contains('actor')));
    });
    test(
      'fire kills before subsequent bleeding; exactly one fire event',
      () async {
        await aftermath(fire: true, bleed: true);
        expect(deaths(), hasLength(1));
        expect(deaths().single.data['cause'], 'fire');
      },
    );
    test('nonfatal fire and bleeding emit nothing', () async {
      await aftermath(fire: true, bleed: true, fatal: false);
      expect(member.alive, isTrue);
      expect(member.blood, lessThan(member.maxBlood));
      expect(deaths(), isEmpty);
    });
    test('nonfatal fire alone causes damage without a death', () async {
      await aftermath(fire: true, fatal: false, seed: 3);
      expect(member.alive, isTrue);
      expect(member.blood, lessThan(member.maxBlood));
      expect(deaths(), isEmpty);
    });
    test('nonfatal bleeding alone causes damage without a death', () async {
      await aftermath(bleed: true, fatal: false);
      expect(member.alive, isTrue);
      expect(member.blood, lessThan(member.maxBlood));
      expect(deaths(), isEmpty);
    });
    test(
      'already dead and preexisting zero blood do not invent fire death',
      () async {
        member.alive = false;
        await advancecreature(member);
        member.alive = true;
        member.blood = 0;
        currentTile.firePeak = true;
        reseedRNG(seed: 42);
        await advancecreature(member);
        expect(deaths(), isEmpty);
      },
    );
  });

  group('chase violence', () {
    Future<void> caught({bool fatal = true, bool dead = false}) async {
      mode = GameMode.footChase;
      chaseSequence = ChaseSequence(cities.single);
      member.rawAttributes[Attribute.agility] = 1;
      member.blood = fatal ? 1 : member.maxBlood;
      member.alive = !dead;
      final pursuer = Creature.fromId(CreatureTypeIds.cop);
      pursuer.rawAttributes[Attribute.agility] = 1000;
      encounter.add(pursuer);
      laws[Law.policeReform] = DeepAlignment.archConservative;
      reseedRNG(seed: 42);
      await evasiverun();
    }

    test('lethal catch records pursuer and no invented street site', () async {
      await caught();
      expect(member.alive, isFalse);
      expect(deaths().single.data['cause'], 'chase_violence');
      expect((deaths().single.data['actor'] as Map)['role'], 'pursuer');
      expect(deaths().single.data, isNot(contains('sourceSite')));
    });
    test('surviving capture emits no death', () async {
      await caught(fatal: false);
      expect(member.alive, isTrue);
      expect(member.site!.type, SiteType.policeStation);
      expect(deaths(), isEmpty);
    });
    test('already dead chase processing emits no death', () async {
      await caught(dead: true);
      expect(deaths(), isEmpty);
    });
  });

  group('vehicle crash', () {
    Future<Vehicle> crash({bool fatal = true}) async {
      mode = GameMode.carChase;
      chaseSequence = ChaseSequence(cities.single);
      final v = Vehicle(vehicleTypes.keys.first);
      vehiclePool.add(v);
      member.carId = v.id;
      if (!fatal) {
        member.rawAttributes[Attribute.heart] = 100;
      }
      member.blood = fatal ? 1 : member.maxBlood;
      reseedRNG(seed: 42);
      await crashfriendlycar(v);
      return v;
    }

    test('member occupant death snapshots vehicle', () async {
      final v = await crash();
      expect(member.alive, isFalse);
      expect(deaths().single.data['cause'], 'vehicle_crash');
      final snapshot = Map<String, dynamic>.from(
        deaths().single.data['vehicle'] as Map,
      );
      expect(snapshot['vehicleId'], v.id);
      expect(snapshot['vehicleType'], v.typeName);
      v.year++;
      vehiclePool.clear();
      expect(deaths().single.data['vehicle'], snapshot);
    });
    test(
      'living carried member is recorded independently of carrier',
      () async {
        final carried = person();
        evidence(carried);
        pool.add(carried);
        member.prisoner = carried;
        await crash(fatal: false);
        expect(member.alive, isTrue);
        expect(carried.alive, isFalse);
        expect(deaths().single.data['memberId'], carried.id);
        expect(member.prisoner, isNull);
      },
    );
    for (final corpse in [false, true]) {
      test(
        'carried ${corpse ? 'corpse' : 'nonmember captive'} emits no death',
        () async {
          final carried = person()
            ..alive = !corpse
            ..missing = true;
          pool.add(carried);
          if (corpse) evidence(carried);
          member.prisoner = carried;
          await crash(fatal: false);
          expect(deaths(), isEmpty);
        },
      );
    }
    test('already-dead occupant emits nothing', () async {
      member.alive = false;
      await crash();
      expect(deaths(), isEmpty);
    });
    test('nonfatal crash emits nothing', () async {
      await crash(fatal: false);
      expect(member.alive, isTrue);
      expect(member.blood, lessThan(member.maxBlood));
      expect(deaths(), isEmpty);
    });
  });

  group('daily injuries', () {
    test('existing injury death is recorded at actual location', () async {
      // Unrelated global site must not replace actual location.
      activeSite = sites[3];
      member.blood = -100;
      await dailyHealing();
      expect(member.alive, isFalse);
      expect(deaths().single.data['cause'], 'injuries');
      expect(deaths().single.data, isNot(contains('actor')));
      expect(
        (deaths().single.data['sourceSite'] as Map)['siteId'],
        member.site!.id,
      );
      await dailyHealing();
      expect(deaths(), hasLength(1));
    });
    test('nonfatal healing emits nothing', () async {
      member.blood = member.maxBlood - 1;
      await dailyHealing();
      expect(member.alive, isTrue);
      expect(deaths(), isEmpty);
    });
  });

  test(
    'record helper has no gameplay effects, consumes no RNG, and records once',
    () {
      final before = jsonEncode(member.toJson());
      reseedRNG(seed: 90);
      final expected = nextRngSeed;
      reseedRNG(seed: 90);
      final pending = MemberDeathRecord.capture(
        member,
        MemberDeathCause.injuries,
      )!;
      pending.record();
      expect(jsonEncode(member.toJson()), before);
      expect(nextRngSeed, expected);
      expect(deaths(), isEmpty);
      member.die();
      final martyrs = stats.martyrs;
      pending.record();
      pending.record();
      expect(deaths(), hasLength(1));
      expect(stats.martyrs, martyrs);
      expect(
        MemberDeathRecord.capture(member, MemberDeathCause.injuries),
        isNull,
      );
    },
  );

  test(
    'existing death history safely refuses an inconsistent living flag',
    () async {
      await strike(member);
      member.alive = true;
      final before = jsonEncode(gameState.toJson());
      expect(
        MemberDeathRecord.capture(member, MemberDeathCause.injuries),
        isNull,
      );
      expect(jsonEncode(gameState.toJson()), before);
      expect(deaths(), hasLength(1));
    },
  );

  test(
    'stale pending record safely leaves replacement GameState untouched',
    () {
      final pending = MemberDeathRecord.capture(
        member,
        MemberDeathCause.injuries,
      )!;
      member.die();
      final terminalState = gameState;
      final memberBefore = jsonEncode(member.toJson());
      gameState = GameState();
      final before = jsonEncode(gameState.toJson());
      pending.record();
      expect(jsonEncode(gameState.toJson()), before);
      expect(jsonEncode(member.toJson()), memberBefore);
      expect(terminalState.playthroughEvents, isEmpty);
      expect(deaths(), isEmpty);
    },
  );

  test(
    'generic death and prison corpse reprocessing are not history hooks',
    () async {
      evidence(member);
      member.die();
      // The existing monthly prison cleanup repeats this mutation.
      member.die();
      await dailyHealing();
      expect(deaths(), isEmpty);
    },
  );

  test('corpse hauling and burial do not create death history', () async {
    member.die();
    await squadHaulImmobileAllies(true);
    final burier = person();
    pool.add(burier);
    member.location = burier.location;
    burier.rawSkill[Skill.streetSmarts] = 100;
    await doActivityBury([burier]);
    expect(deaths(), isEmpty);
  });

  test(
    'recorded member corpse handling does not create a second death',
    () async {
      await strike(member);
      expect(member.alive, isFalse);
      expect(pool, contains(member));
      final recordedDeath = jsonEncode(deaths().single.toJson());
      await squadHaulImmobileAllies(true);
      final burier = person();
      pool.add(burier);
      member.location = burier.location;
      burier.rawSkill[Skill.streetSmarts] = 100;
      await doActivityBury([burier]);
      expect(deaths(), hasLength(1));
      expect(jsonEncode(deaths().single.toJson()), recordedDeath);
    },
  );

  test('disbanding attrition is not a factual death', () {
    member.hireId = attacker.id;
    member.juice = -100;
    letTheUnworthyLeave();
    expect(member.alive, isFalse);
    expect(deaths(), isEmpty);
  });

  test(
    'actual last-member death precedes durable ending and survives deletion',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lcs_death_ending_',
      );
      final storage = SembastStorage(databasePath: '${directory.path}/game.db');
      await storage.init();
      addTearDown(() async {
        await storage.close();
        await directory.delete(recursive: true);
      });
      SharedPreferences.setMockInitialValues({});
      final scores = ScoreRepository(storage);
      await scores.initialize(await SharedPreferences.getInstance());
      expect(await checkForDefeat(), isFalse);
      await strike(member);
      expect(pool.where((p) => p.alive), isEmpty);
      final failures = <Object>[];
      await expectLater(
        completeCampaignEnding(
          CampaignEnding.noQualifyingMembers(),
          scores: scores,
          presentEnding: () async {},
          presentScores: (_) async {},
          presentFailure: (error) async => failures.add(error),
        ),
        throwsA(isA<EndGameException>()),
      );
      expect(failures, isEmpty);
      expect(gameState.playthroughEvents.map((e) => e.type), [
        PlaythroughEventType.memberDied,
        PlaythroughEventType.campaignEnded,
      ]);
      final id = gameState.playthroughEvents.last.data['archiveId'] as String;
      expect(
        (await storage.loadArchive(id))!.events.first.toJson(),
        deaths().single.toJson(),
      );
      expect(await storage.loadGame(gameState.uniqueGameId.toString()), isNull);
    },
  );

  test('rehabilitation renunciation is not a factual death', () async {
    member.rawAttributes[Attribute.heart] = 0;
    member.rawAttributes[Attribute.wisdom] = 100;
    member.juice = 0;
    reseedRNG(seed: 42);
    await rehabilitation(member);
    expect(member.alive, isFalse);
    expect(deaths(), isEmpty);
  });

  test('permanent trauma abandonment is not a factual death', () async {
    // A surviving leader keeps the real dispersal resolver out of game-over UI.
    pool.add(attacker..align = Alignment.liberal);
    member.hireId = attacker.id;
    member.rawAttributes[Attribute.heart] = 0;
    member.rawAttributes[Attribute.wisdom] = 100;
    // Search deterministic independent attempts for the rare permanent branch.
    for (int seed = 0; seed < 100 && member.alive; seed++) {
      reseedRNG(seed: seed);
      await traumatize(member, 'execution', 0);
      console = _Input();
    }
    expect(member.alive, isFalse);
    expect(deaths(), isEmpty);
  });

  test(
    'death wire and detached snapshots survive save, completion and archive retry',
    () async {
      evidence(member, PlaythroughEventType.campaignFounded);
      await strike(member);
      final event = deaths().single;
      expect(event.type.wireName, 'member_died');
      final expected =
          jsonDecode(jsonEncode(event.toJson())) as Map<String, dynamic>;
      expect(PlaythroughEvent.fromJson(expected).toJson(), expected);
      member.name = 'Changed';
      attacker.name = 'Changed attacker';
      activeSite!.name = 'Changed site';
      cities.single.name = 'Changed city';
      pool.clear();
      expect(event.toJson(), expected);
      gameState = GameState.fromJson(
        jsonDecode(jsonEncode(gameState.toJson())) as Map<String, dynamic>,
      );
      expect(deaths().single.toJson(), expected);
      final directory = await Directory.systemTemp.createTemp('lcs_death_');
      final storage = SembastStorage(databasePath: '${directory.path}/game.db');
      await storage.init();
      addTearDown(() async {
        await storage.close();
        await directory.delete(recursive: true);
      });
      Future<CampaignHistoryArchive> prepare() => prepareCampaignCompletion(
        state: gameState,
        storage: storage,
        outcome: CampaignOutcome.defeat,
        route: CampaignEndRoute.noQualifyingMembers,
        presentationEnding: Ending.dead,
      );
      final archive = await prepare();
      expect(archive.events.map((e) => e.type), [
        PlaythroughEventType.campaignFounded,
        PlaythroughEventType.memberDied,
        PlaythroughEventType.campaignEnded,
      ]);
      expect(archive.events[1].toJson(), expected);
      expect((await prepare()).toJson(), archive.toJson());
      final restored = CampaignHistoryArchive.fromJson(
        jsonDecode(jsonEncode(archive.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), archive.toJson());
      expect(
        (await storage.loadArchive(archive.archiveId))!.events[1].toJson(),
        expected,
      );
      final save = (await storage.loadGame(gameState.uniqueGameId.toString()))!;
      expect(
        GameState.fromJson(save.saveData).playthroughEvents[1].toJson(),
        expected,
      );
    },
  );
}
