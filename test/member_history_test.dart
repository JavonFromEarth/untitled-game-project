import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/daily/dating.dart';
import 'package:lcs_new_age/daily/hostages/release.dart';
import 'package:lcs_new_age/daily/hostages/tend_hostage.dart';
import 'package:lcs_new_age/daily/recruitment.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/location/city.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/monthly/sleeper_update.dart';
import 'package:lcs_new_age/playthrough_log/campaign_history_archive.dart';
import 'package:lcs_new_age/playthrough_log/member_history.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/politics/politics.dart';
import 'package:lcs_new_age/sitemode/miscactions.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/sitemode/sitemode.dart';
import 'package:lcs_new_age/talk/drop_a_pickup_line.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

class _Input extends Console {
  _Input([this.keys = const []]);
  final List<int> keys;
  int count = 0;

  @override
  Future<String> getkey() async {
    if (count > 50) throw StateError('Unexpected input loop');
    final key = count < keys.length ? keys[count] : Key.enter;
    count++;
    return String.fromCharCode(key);
  }
}

void main() {
  setUpAll(ensureGameDataLoaded);
  late GameState previousState;
  late Console previousConsole;
  late Creature actor;

  Creature person([String type = CreatureTypeIds.liberalJudge]) {
    final cr = Creature.fromId(type, align: Alignment.liberal);
    cr.rawAttributes[Attribute.wisdom] = 1;
    cr.juice = 0;
    cr.location = activeSite;
    cr.workLocation = sites.first;
    cr.base = sites.first;
    cr.nameCreature();
    return cr;
  }

  setUp(() {
    previousState = gameState;
    previousConsole = console;
    gameState = GameState();
    reseedRNG(seed: 42);
    final city = City('Test City', 'Test', '');
    cities.add(city);
    city.addDistrict('Test District', '').addSites([
      SiteType.warehouse,
      SiteType.sweatshop,
      SiteType.publicPark,
      SiteType.whiteHouse,
      SiteType.courthouse,
      SiteType.ceoHouse,
    ]);
    activeSite = sites[1];
    actor = person(CreatureTypeIds.lawyer);
    actor.name = 'Lee Lucas';
    actor.rawSkill[Skill.seduction] = 1000;
    actor.location = sites.first;
    pool.add(actor);
    squads.add(Squad()..name = 'Liberators');
    activeSquad = squads.single;
    actor.squad = activeSquad;
    console = _Input();
  });

  tearDown(() {
    gameState = previousState;
    console = previousConsole;
  });

  List<PlaythroughEvent> getJoins() => gameState.playthroughEvents
      .where((e) => e.type == PlaythroughEventType.memberJoined)
      .toList();

  Future<void> contact(Creature prospect) async {
    encounter.add(prospect);
    console = _Input();
    await doYouComeHereOften(actor, prospect);
  }

  DatingSession session(Creature prospect) {
    final d = DatingSession(actor.id, cities.single)..dates.add(prospect);
    datingSessions.add(d);
    return d;
  }

  InterrogationSession captive({bool succeeds = true}) {
    final cr = person();
    cr.align = Alignment.conservative;
    cr.location = actor.location;
    cr.missing = true;
    cr.kidnapped = true;
    pool.add(cr);
    final intr = InterrogationSession(cr.id);
    intr.rapport[actor.id] = succeeds ? 100 : -100;
    intr.techniques[Technique.restrain] = true;
    interrogationSessions.add(intr);
    actor.activity = Activity(ActivityType.interrogation, idInt: cr.id);
    return intr;
  }

  group('dating contact', () {
    test(
      'new contact emits once, retains encounter site, and detaches snapshots',
      () async {
        final prospect = person();
        final source = activeSite!;
        await contact(prospect);
        expect(datingSessions.single.dates, contains(prospect));
        expect(prospect.seduced, isFalse);
        expect(pool, isNot(contains(prospect)));
        final event = gameState.playthroughEvents.single;
        expect(event.type.wireName, 'dating_contact_established');
        expect(event.data['actorId'], actor.id);
        expect(event.data['personId'], prospect.id);
        expect(event.data['personTypeId'], prospect.typeId);
        expect(event.data['contactKind'], 'dating');
        expect(event.data['sourceSite'], {
          'siteId': source.id,
          'siteName': source.name,
          'siteType': 'sweatshop',
          'cityId': cities.single.id,
          'cityName': cities.single.name,
        });
        await contact(prospect);
        expect(gameState.playthroughEvents, hasLength(1));
        final snapshot = jsonEncode(event.toJson());
        prospect.name = 'Later name';
        actor.name = 'Later actor';
        source.name = 'Later site';
        cities.single.name = 'Later city';
        datingSessions.clear();
        expect(jsonEncode(event.toJson()), snapshot);
      },
    );

    test(
      'second person in an existing session has their own contact event',
      () async {
        final first = person();
        final second = person();
        await contact(first);
        await contact(second);
        expect(datingSessions, hasLength(1));
        expect(datingSessions.single.dates, hasLength(2));
        expect(gameState.playthroughEvents.map((e) => e.data['personId']), [
          first.id,
          second.id,
        ]);
      },
    );

    test('rejection emits nothing', () async {
      actor.rawSkill[Skill.seduction] = -1000;
      await contact(person());
      expect(datingSessions, isEmpty);
      expect(gameState.playthroughEvents, isEmpty);
    });

    test('paid companionship does not imply romance', () async {
      await contact(person(CreatureTypeIds.sexWorker));
      expect(
        gameState.playthroughEvents.single.data['contactKind'],
        'paid_companionship',
      );
      expect(
        gameState.playthroughEvents.single.data,
        isNot(contains('relationshipKind')),
      );
    });
  });

  group('dating membership', () {
    for (final type in [
      CreatureTypeIds.liberalJudge,
      CreatureTypeIds.sexWorker,
    ]) {
      for (final role in [Key.a, Key.b]) {
        test(
          '$type joins in resolved role $role with correct relationship basis',
          () async {
            final prospect = person(type);
            await contact(prospect);
            final contactSequence = gameState.playthroughEvents.single.sequence;
            console = _Input([Key.enter, Key.enter, Key.enter, role]);
            reseedRNG(seed: 42);
            final result = await dateResult(
              100000,
              0,
              datingSessions.single,
              prospect,
              actor,
              1,
            );
            expect(result, DateResult.joined);
            expect(pool, contains(prospect));
            final event = getJoins().single;
            expect(event.data['memberName'], prospect.name);
            expect(event.data['joinMethod'], 'dating_recruitment');
            expect(
              event.data['initialRole'],
              role == Key.a ? 'active' : 'sleeper',
            );
            expect(event.data['recruiterId'], actor.id);
            expect(event.data['provenance'], {
              'relationshipKind': type == CreatureTypeIds.sexWorker
                  ? 'commercial'
                  : 'romantic',
              'contactEventSequence': contactSequence,
            });
            expect(prospect.seduced, type != CreatureTypeIds.sexWorker);
            expect(datingSessions.single.dates, isEmpty);
          },
        );
      }
    }

    test('positive dates that do not join record no new history', () async {
      final prospect = person()..rawAttributes[Attribute.wisdom] = 20;
      await contact(prospect);
      final result = await dateResult(
        100,
        0,
        datingSessions.single,
        prospect,
        actor,
        1,
      );
      expect(result, DateResult.meetTomorrow);
      expect(getJoins(), isEmpty);
      expect(gameState.playthroughEvents, hasLength(1));
      expect(prospect.seduced, isFalse);
    });

    test(
      'vacation uses the join resolver without inventing a contact for old prospects',
      () async {
        final prospect = person();
        final d = session(prospect);
        console = _Input([Key.enter, Key.enter, Key.enter, Key.b]);
        reseedRNG(seed: 42);
        expect(await completeVacation(d, actor), isTrue);
        expect(getJoins().single.data['initialRole'], 'sleeper');
        expect(getJoins().single.data['provenance'], {
          'relationshipKind': 'romantic',
        });
      },
    );

    test('contact linking requires same actor, person, and campaign', () {
      final prospect = person();
      final other = person();
      recordDatingContact(actor: other, person: prospect);
      recordDatingContact(actor: actor, person: other);
      final campaign = gameState.uniqueGameId;
      gameState.uniqueGameId++;
      recordDatingContact(actor: actor, person: prospect);
      gameState.uniqueGameId = campaign;
      expect(datingJoinProvenance(prospect, actor), {
        'relationshipKind': 'romantic',
      });
    });
  });

  group('liberation membership', () {
    for (final entry in {
      CreatureTypeIds.sweatshopWorker: 'sweatshop_worker',
      CreatureTypeIds.childLaborer: 'child_laborer',
      CreatureTypeIds.servant: 'servant',
      CreatureTypeIds.thief: 'prisoner',
    }.entries) {
      test(
        '${entry.value} preserves liberation context before naming and relocation',
        () {
          laws[Law.labor] = DeepAlignment.archConservative;
          final recruit = person(entry.key)..alreadyNamed = false;
          recruit.name = entry.value == 'prisoner'
              ? 'Prisoner'
              : 'Encounter label';
          final source = activeSite!;
          expect(recruit.workSite, isNot(source));
          expect(recruitFreedPerson(recruit), isTrue);
          final event = getJoins().single;
          expect(event.data['joinMethod'], 'site_rescue');
          expect(event.data['recruiterId'], actor.id);
          final provenance = event.data['provenance'] as Map;
          final sourceSnapshot =
              provenance['sourceSite'] as Map<String, dynamic>;
          expect(sourceSnapshot['siteId'], source.id);
          expect(provenance['liberation'], {
            'category': entry.value,
            'encounterName': entry.value == 'prisoner'
                ? 'Prisoner'
                : 'Encounter label',
            'squadId': activeSquad!.id,
            'squadName': 'Liberators',
          });
          expect(event.data, isNot(contains('rescuerId')));
          final snapshot = jsonEncode(event.toJson());
          recruit.name = 'Renamed';
          source.name = 'Renamed site';
          activeSquad!.name = 'Renamed squad';
          pool.remove(recruit);
          expect(jsonEncode(event.toJson()), snapshot);
        },
      );
    }

    test(
      'three rescued workers each join under the first member with capacity',
      () {
        actor.brainwashed = true;
        final recruiter = person()..name = 'Actual recruiter';
        pool.add(recruiter);
        recruiter.squad = activeSquad;
        for (int i = 0; i < 3; i++) {
          expect(
            recruitFreedPerson(person(CreatureTypeIds.sweatshopWorker)),
            isTrue,
          );
        }
        expect(getJoins(), hasLength(3));
        expect(
          getJoins().map((e) => e.data['recruiterId']),
          everyElement(recruiter.id),
        );
        expect(getJoins().map((e) => e.data['memberId']).toSet(), hasLength(3));
      },
    );

    test('full squad or no recruitment capacity creates no join', () {
      actor.brainwashed = true;
      expect(
        recruitFreedPerson(person(CreatureTypeIds.sweatshopWorker)),
        isFalse,
      );
      actor.brainwashed = false;
      while (squad.length < 6) {
        final member = person();
        pool.add(member);
        member.squad = activeSquad;
      }
      expect(
        recruitFreedPerson(person(CreatureTypeIds.sweatshopWorker)),
        isFalse,
      );
      expect(getJoins(), isEmpty);
    });

    test('rescue of an existing member does not recruit them again', () async {
      final existing = person();
      pool.add(existing);
      await partyrescue(TileSpecial.policeStationLockup);
      expect(existing.justEscaped, isTrue);
      expect(getJoins(), isEmpty);
      expect(recruitFreedPerson(existing), isFalse);
    });
  });

  group('hostage membership', () {
    test(
      'successful tending conversion logs once without claiming custody release',
      () async {
        final intr = captive();
        console = _Input([Key.c, Key.enter]);
        await tendHostage(intr);
        final event = getJoins().single;
        expect(event.data['joinMethod'], 'hostage_conversion');
        expect(event.data['initialRole'], 'active');
        expect(event.data['recruiterId'], actor.id);
        expect(pool.last.brainwashed, isTrue);
        expect(pool.last.missing, isTrue);
        expect(interrogationSessions, isEmpty);
      },
    );

    test('failed captive recruitment creates no history', () async {
      final intr = captive(succeeds: false);
      console = _Input([Key.c, Key.enter]);
      await tendHostage(intr);
      expect(getJoins(), isEmpty);
    });

    test('interrogation changes do not create join history', () async {
      final intr = captive();
      console = _Input([Key.d, Key.enter]);
      await tendHostage(intr);
      expect(getJoins(), isEmpty);
    });

    test('ordinary release can create one sleeper membership', () async {
      final intr = captive();
      final cr = intr.hostage;
      await handleRelease(intr, actor, 1);
      final event = getJoins().single;
      expect(event.data['joinMethod'], 'released_hostage_sleeper');
      expect(event.data['initialRole'], 'sleeper');
      expect(cr.sleeperAgent, isTrue);
      expect(cr.kidnapped, isFalse);
      expect(cr.missing, isFalse);
    });

    test('ordinary release without recruitment emits no join', () async {
      final intr = captive(succeeds: false);
      final cr = intr.hostage;
      await handleRelease(intr, actor, 1);
      expect(pool, isNot(contains(cr)));
      expect(getJoins(), isEmpty);
    });

    test(
      'siege-release presentation does not create membership history',
      () async {
        final intr = captive();
        intr.hostage.site!.siege.activeSiegeType = SiegeType.police;
        await handleRelease(intr, actor, 1);
        expect(getJoins(), isEmpty);
        expect(intr.hostage.sleeperAgent, isFalse);
      },
    );
  });

  group('sleeper recruitment', () {
    test(
      'ordinary sleeper recruitment records exactly one sleeper join',
      () async {
        actor.sleeperAgent = true;
        actor.workLocation = sites[1];
        reseedRNG(seed: 42);
        await sleeperRecruit(actor, {});
        final event = getJoins().single;
        expect(event.data['joinMethod'], 'sleeper_recruitment');
        expect(event.data['initialRole'], 'sleeper');
        expect(event.data['recruiterId'], actor.id);
        expect(
          pool.any((p) => p.id == event.data['memberId'] && p.sleeperAgent),
          isTrue,
        );
      },
    );

    test('no sleeper recruitment capacity emits nothing', () async {
      actor.brainwashed = true;
      await sleeperRecruit(actor, {});
      expect(getJoins(), isEmpty);
    });

    test('sleeper search with no accepted candidate emits nothing', () async {
      actor.sleeperAgent = true;
      actor.workLocation = sites[2];
      reseedRNG(seed: 42);
      await sleeperRecruit(actor, {});
      expect(getJoins(), isEmpty);
      expect(pool, hasLength(1));
    });

    test(
      'presidential cabinet appointment does not create membership',
      () async {
        final president = uniqueCreatures.president;
        president.align = Alignment.liberal;
        president.sleeperAgent = true;
        pool.add(president);
        politics.senate = List.filled(100, DeepAlignment.eliteLiberal);
        politics.house = List.filled(435, DeepAlignment.eliteLiberal);
        for (final office in Exec.values) {
          politics.exec[office] = DeepAlignment.moderate;
        }
        final before = Map.of(politics.exec);
        await sleeperRecruit(president, {});
        expect(politics.exec, isNot(before));
        expect(getJoins(), isEmpty);
      },
    );
  });

  test(
    'standard recruitment retains existing fields and adds type snapshots',
    () async {
      final recruit = person();
      final r = RecruitmentSession(recruit, actor)..rawEagerness = 4;
      recruitmentSessions.add(r);
      console = _Input([Key.c, Key.enter, Key.enter, Key.a]);
      expect(await completeRecruitMeeting(r, actor), isTrue);
      expect(getJoins().single.data, {
        'memberId': recruit.id,
        'memberName': recruit.name,
        'memberTypeId': recruit.typeId,
        'memberTypeName': recruit.type.name,
        'joinMethod': 'standard_recruitment',
        'initialRole': 'active',
        'recruiterId': actor.id,
        'recruiterName': actor.name,
      });
    },
  );

  test(
    'campaign origin keeps its wire and role without invented provenance',
    () {
      final recruit = person()..sleeperAgent = true;
      recordMemberJoined(
        member: recruit,
        recruiter: actor,
        method: MemberJoinMethod.campaignOrigin,
      );
      expect(getJoins().single.data['joinMethod'], 'campaign_origin');
      expect(getJoins().single.data['initialRole'], 'sleeper');
      expect(getJoins().single.data, isNot(contains('provenance')));
    },
  );

  test(
    'contact and joined history survives real GameState and archive round trips',
    () async {
      final prospect = person();
      await contact(prospect);
      // Restore the prospect/session before joining to prove linking uses IDs.
      gameState = GameState.fromJson(
        jsonDecode(jsonEncode(gameState.toJson())) as Map<String, dynamic>,
      );
      actor = pool.single;
      final restoredProspect = datingSessions.single.dates.single;
      console = _Input([Key.enter, Key.enter, Key.enter, Key.b]);
      reseedRNG(seed: 42);
      await dateResult(
        100000,
        0,
        datingSessions.single,
        restoredProspect,
        actor,
        1,
      );
      final provenance =
          getJoins().single.data['provenance'] as Map<String, dynamic>;
      expect(provenance['contactEventSequence'], 1);
      final expected = jsonDecode(jsonEncode(gameState.playthroughEvents));
      gameState = GameState.fromJson(
        jsonDecode(jsonEncode(gameState.toJson())) as Map<String, dynamic>,
      );
      expect(jsonDecode(jsonEncode(gameState.playthroughEvents)), expected);
      expect(gameState.playthroughSequence, 2);
      final archive = CampaignHistoryArchive(
        archiveId: 'relational-test',
        gameId: gameState.uniqueGameId,
        finalGameDate: date,
        completedAt: DateTime.utc(2026, 9, 13),
        finalSequence: gameState.playthroughSequence,
        outcome: CampaignOutcome.victory,
        route: CampaignEndRoute.victoryConditions,
        events: gameState.playthroughEvents,
      );
      final restored = CampaignHistoryArchive.fromJson(
        jsonDecode(jsonEncode(archive.toJson())) as Map<String, dynamic>,
      );
      expect(jsonDecode(jsonEncode(restored.events)), expected);
      expect(restored.finalSequence, 2);
    },
  );

  test(
    'all join-method wires and payloads survive state and archive serialization',
    () {
      const wires = [
        'standard_recruitment',
        'dating_recruitment',
        'site_rescue',
        'hostage_conversion',
        'released_hostage_sleeper',
        'sleeper_recruitment',
        'campaign_origin',
      ];
      expect(MemberJoinMethod.values.map((m) => m.wireName), wires);
      for (final method in MemberJoinMethod.values) {
        final member = person();
        pool.add(member);
        recordMemberJoined(member: member, recruiter: actor, method: method);
      }
      final expected = jsonDecode(jsonEncode(gameState.playthroughEvents));
      gameState = GameState.fromJson(
        jsonDecode(jsonEncode(gameState.toJson())) as Map<String, dynamic>,
      );
      expect(jsonDecode(jsonEncode(gameState.playthroughEvents)), expected);
      final archive = CampaignHistoryArchive(
        archiveId: 'all-membership-wires',
        gameId: gameState.uniqueGameId,
        finalGameDate: date,
        completedAt: DateTime.utc(2026, 9, 13),
        finalSequence: gameState.playthroughSequence,
        outcome: CampaignOutcome.victory,
        route: CampaignEndRoute.victoryConditions,
        events: gameState.playthroughEvents,
      );
      final restored = CampaignHistoryArchive.fromJson(
        jsonDecode(jsonEncode(archive.toJson())) as Map<String, dynamic>,
      );
      expect(jsonDecode(jsonEncode(restored.events)), expected);
      expect(restored.finalSequence, wires.length);
    },
  );

  test(
    'helpers detach caller-owned nested maps and omit unavailable site context',
    () {
      final member = person();
      final source = historySiteSnapshot(activeSite)!;
      final provenance = <String, dynamic>{'sourceSite': source};
      recordMemberJoined(
        member: member,
        recruiter: actor,
        method: MemberJoinMethod.siteRescue,
        provenance: provenance,
      );
      recordDatingContact(actor: actor, person: member, sourceSite: source);
      final snapshot = jsonEncode(gameState.playthroughEvents);
      source['siteName'] = 'Changed';
      provenance.clear();
      expect(jsonEncode(gameState.playthroughEvents), snapshot);
      expect(historySiteSnapshot(null), isNull);
      recordDatingContact(actor: actor, person: member);
      expect(
        gameState.playthroughEvents.last.data,
        isNot(contains('sourceSite')),
      );
    },
  );
}
