import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/basemode/invest_in_location.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/location/city.dart';
import 'package:lcs_new_age/location/compound_upgrades.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/monthly/advance_month.dart';
import 'package:lcs_new_age/monthly/lcs_monthly.dart';
import 'package:lcs_new_age/playthrough_log/campaign_history_archive.dart';
import 'package:lcs_new_age/playthrough_log/financial_history.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

class _ScriptedConsole extends Console {
  _ScriptedConsole(this.keys);
  final List<int> keys;
  int reads = 0;

  @override
  Future<String> getkey() async {
    if (reads == keys.length) throw StateError('Unexpected input request');
    return String.fromCharCode(keys[reads++]);
  }
}

// Simulate a naming failure at the real front-establishment resolver.
class _FailingFrontSite extends Site {
  _FailingFrontSite() : super(SiteType.warehouse);

  @override
  set frontName(String? value) => throw StateError('Naming failed');
}

void main() {
  setUpAll(ensureGameDataLoaded);
  late GameState previousState;
  late Console previousConsole;
  late Site site;

  setUp(() {
    previousState = gameState;
    previousConsole = console;
    gameState = GameState();
    reseedRNG(seed: 42);
    final city = City('Test City', 'Test', '');
    cities.add(city);
    city.addDistrict('Industrial', '').addSites([SiteType.warehouse]);
    site = sites.single;
    ledger.forceSetFunds(1000000);
  });

  tearDown(() {
    gameState = previousState;
    console = previousConsole;
  });

  Future<void> invest(List<int> keys, [Site? target]) async {
    console = _ScriptedConsole(keys);
    await investInLocation(target ?? site);
  }

  void seedAccountingCycle() {
    ledger.forceSetFunds(100);
    ledger.addFunds(500, Income.donations);
    ledger.subtractFunds(100, Expense.shopping);
    ledger.resetMonthlyAmounts();
    ledger.addFunds(120, Income.artSales);
    ledger.addFunds(80, Income.busking);
    ledger.subtractFunds(30, Expense.artSupplies);
    ledger.subtractFunds(20, Expense.groceries);
  }

  group('financial accounting close', () {
    test(
      'snapshots cycle and lifetime amounts before reset, without dates inferred',
      () {
        seedAccountingCycle();
        gameState.date = DateTime(2026, 9, 1);
        final oldIncome = ledger.income;
        final oldExpenses = ledger.expense;
        logFinancialPeriodClosed();
        final event = gameState.playthroughEvents.single;
        expect(event.type, PlaythroughEventType.financialPeriodClosed);
        expect(event.gameDate, date);
        expect(event.data, {
          'periodKind': 'accounting_cycle',
          'income': {'art_sales': 120, 'busking': 80},
          'expenses': {'art_supplies': 30, 'groceries': 20},
          'totalIncome': 200,
          'totalExpenses': 50,
          'closingFunds': 650,
          'cumulativeIncome': 700,
          'cumulativeExpense': 150,
        });
        final snapshot = jsonEncode(event.toJson());
        ledger.resetMonthlyAmounts();
        oldIncome[Income.artSales] = 999;
        oldExpenses.clear();
        ledger.addFunds(70, Income.busking);
        ledger.subtractFunds(5, Expense.groceries);
        expect(jsonEncode(event.toJson()), snapshot);
      },
    );

    for (final visibility in [CantSeeReason.none, CantSeeReason.hiding]) {
      test(
        'advanceMonth closes and resets with visibility $visibility',
        () async {
          seedAccountingCycle();
          gameState.date = DateTime(2023, 2, 1);
          gameState.cantSeeReason = visibility;
          pool.add(Creature()..align = Alignment.liberal);
          console = _ScriptedConsole(List.filled(30, Key.enter));

          await advanceMonth();

          final event = gameState.playthroughEvents.single;
          expect(event.type, PlaythroughEventType.financialPeriodClosed);
          expect(event.gameDate, DateTime(2023, 2, 1));
          expect(event.data['income'], {'art_sales': 120, 'busking': 80});
          expect(event.data['expenses'], {'art_supplies': 30, 'groceries': 20});
          expect(ledger.income.values, everyElement(0));
          expect(ledger.expense.values, everyElement(0));
        },
      );
    }

    test(
      'an empty cycle emits nothing even with funds and cumulative totals',
      () {
        seedAccountingCycle();
        ledger.resetMonthlyAmounts();
        logFinancialPeriodClosed();
        expect(gameState.playthroughEvents, isEmpty);
        expect(gameState.playthroughSequence, 0);
      },
    );

    test('income-only and expense-only cycles are both meaningful', () {
      ledger.addFunds(10, Income.donations);
      logFinancialPeriodClosed();
      ledger.resetMonthlyAmounts();
      ledger.subtractFunds(10, Expense.rent);
      logFinancialPeriodClosed();
      expect(gameState.playthroughEvents, hasLength(2));
      expect(gameState.playthroughEvents.first.data['expenses'], isEmpty);
      expect(gameState.playthroughEvents.last.data['income'], isEmpty);
    });

    test(
      'viewing and reopening fundReport never closes or records a cycle',
      () async {
        seedAccountingCycle();
        console = _ScriptedConsole([Key.enter, Key.enter]);
        await fundReport(false);
        await fundReport(false);
        expect(gameState.playthroughEvents, isEmpty);
        expect(gameState.playthroughSequence, 0);
        expect(ledger.income[Income.artSales], 120);
        expect(ledger.expense[Expense.artSupplies], 30);
      },
    );

    test(
      'legacy save close survives GameState and archive JSON round trips',
      () async {
        final raw =
            jsonDecode(await File('test/saves/moe_1_5.json').readAsString())
                as Map<String, dynamic>;
        gameState = GameState.fromJson(SaveFile.fromJson(raw).saveData);
        expect(gameState.playthroughEvents, isEmpty);
        ledger.addFunds(19, Income.donations);
        logFinancialPeriodClosed();
        final original = gameState.playthroughEvents.single.toJson();
        expect(original.keys, isNot(contains('periodStart')));
        expect(original['periodKind'], 'accounting_cycle');
        gameState = GameState.fromJson(
          jsonDecode(jsonEncode(gameState.toJson())) as Map<String, dynamic>,
        );
        expect(gameState.playthroughEvents.single.toJson(), original);
        expect(gameState.playthroughSequence, original['seq']);
        final archive = CampaignHistoryArchive(
          archiveId: 'economic-history-test',
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
        expect(restored.events.single.toJson(), original);
        expect(restored.finalSequence, gameState.playthroughSequence);
        expect(restored.toJson(), archive.toJson());
      },
    );
  });

  group('business front establishment', () {
    test(
      'completed establishment snapshots final name and payment exactly once',
      () async {
        final siteName = site.name;
        final price = CompoundUpgrade.businessFront.price;
        await invest([Key.f, Key.f, Key.enter]);
        final event = gameState.playthroughEvents.single;
        expect(site.businessFront, isTrue);
        expect(event.type, PlaythroughEventType.businessFrontEstablished);
        expect(event.data, {
          'siteId': site.id,
          'siteName': siteName,
          'frontName': site.frontName,
          'price': price,
          'cityId': site.cityId,
          'districtId': site.districtId,
        });
        expect(site.frontName, isNotEmpty);
        expect(ledger.funds, 1000000 - price);
        final snapshot = jsonEncode(event.toJson());
        await invest([Key.enter]);
        site.rename('Renamed site', 'New');
        site.frontName = 'Renamed front';
        site.businessFront = false;
        expect(gameState.playthroughEvents, hasLength(1));
        expect(jsonEncode(event.toJson()), snapshot);
      },
    );

    test('name collisions resolve before the front name is recorded', () async {
      reseedRNG(seed: 1);
      await invest([Key.f, Key.enter]);
      final firstShortName = site.shortName;
      final other = Site(SiteType.warehouse);
      site.district.sites.add(other);
      reseedRNG(seed: 1);
      await invest([Key.f, Key.enter], other);
      expect(other.shortName, isNot(firstShortName));
      expect(gameState.playthroughEvents, hasLength(2));
      expect(
        gameState.playthroughEvents.last.data['frontName'],
        other.frontName,
      );
    });

    test('insufficient funds and cancellation emit nothing', () async {
      await invest([Key.enter]);
      ledger.forceSetFunds(CompoundUpgrade.businessFront.price - 1);
      await invest([Key.f, Key.enter]);
      expect(site.businessFront, isFalse);
      expect(gameState.playthroughEvents, isEmpty);
    });

    test(
      'intrinsic fronts and discreet sites do not establish a front',
      () async {
        final bar = Site(SiteType.barAndGrill);
        expect(bar.businessFront, isTrue);
        await invest([Key.f, Key.enter], bar);
        final bunker = Site(SiteType.bunker);
        await invest([Key.f, Key.enter], bunker);
        expect(gameState.playthroughEvents, isEmpty);
        expect(ledger.funds, 1000000);
      },
    );

    test('naming failure does not record an establishment', () async {
      final failing = _FailingFrontSite();
      await expectLater(invest([Key.f], failing), throwsStateError);
      expect(gameState.playthroughEvents, isEmpty);
    });
  });

  group('compound installation', () {
    const upgrades = {
      Key.w: (CompoundUpgrade.fortify, 'fortification'),
      Key.c: (CompoundUpgrade.cameras, 'cameras'),
      Key.t: (CompoundUpgrade.boobyTraps, 'booby_traps'),
      Key.b: (CompoundUpgrade.bollards, 'bollards'),
      Key.g: (CompoundUpgrade.generator, 'generator'),
      Key.p: (CompoundUpgrade.solarPanels, 'solar_panels'),
      Key.a: (CompoundUpgrade.aaGun, 'aa_gun'),
      Key.v: (CompoundUpgrade.videoRoom, 'video_room'),
      Key.h: (CompoundUpgrade.hackerDen, 'hacker_den'),
    };
    for (final entry in upgrades.entries) {
      final (upgrade, wireName) = entry.value;
      test(
        '$wireName records one paid installation and rejects duplicate selection',
        () async {
          final price = upgrade.price;
          final name = site.name;
          await invest([entry.key, entry.key, Key.enter]);
          expect(upgrade.isActiveOn(site), isTrue);
          expect(ledger.funds, 1000000 - price);
          final event = gameState.playthroughEvents.single;
          expect(event.type, PlaythroughEventType.compoundUpgradeInstalled);
          expect(event.data, {
            'siteId': site.id,
            'siteName': name,
            'upgradeId': wireName,
            'price': price,
          });
          final snapshot = jsonEncode(event.toJson());
          upgrade.removeFrom(site);
          site.rename('Later name', 'Later');
          laws[Law.pollution] = DeepAlignment.eliteLiberal;
          laws[Law.gunControl] = DeepAlignment.archConservative;
          expect(jsonEncode(event.toJson()), snapshot);
        },
      );

      test('$wireName cannot be installed without sufficient funds', () async {
        ledger.forceSetFunds(upgrade.price - 1);
        await invest([entry.key, Key.enter]);
        expect(upgrade.isActiveOn(site), isFalse);
        expect(gameState.playthroughEvents, isEmpty);
      });
    }

    for (final keys in [
      [Key.a, Key.p],
      [Key.p, Key.a],
    ]) {
      test(
        'mutually exclusive roof purchase ${keys.first} blocks ${keys.last}',
        () async {
          await invest([...keys, Key.enter]);
          final (upgrade, wireName) = upgrades[keys.first]!;
          expect(
            gameState.playthroughEvents.single.data['upgradeId'],
            wireName,
          );
          expect(ledger.funds, 1000000 - upgrade.price);
          expect(upgrades[keys.last]!.$1.isActiveOn(site), isFalse);
        },
      );
    }

    test(
      'cancellation, supplies, and non-upgradable sites emit no installations',
      () async {
        await invest([Key.enter]);
        site.compound.generator = true;
        await invest([Key.r, Key.d, Key.enter]);
        final apartment = Site(SiteType.upscaleApartment);
        await invest([Key.w, Key.enter], apartment);
        expect(apartment.compound.fortified, isFalse);
        expect(gameState.playthroughEvents, isEmpty);
      },
    );
  });
}
