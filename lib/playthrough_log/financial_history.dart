import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_event.dart';
import 'package:lcs_new_age/playthrough_log/playthrough_log.dart';

/// Called at accounting close, before the cycle counters are reset.
/// Existing saves do not establish when these counters started accumulating.
void logFinancialPeriodClosed() {
  final income = <String, int>{
    for (final entry in ledger.income.entries)
      if (entry.value != 0) _incomeWireName(entry.key): entry.value,
  };
  final expenses = <String, int>{
    for (final entry in ledger.expense.entries)
      if (entry.value != 0) _expenseWireName(entry.key): entry.value,
  };
  final totalIncome = income.values.fold(0, (total, amount) => total + amount);
  final totalExpenses = expenses.values.fold(
    0,
    (total, amount) => total + amount,
  );
  if (totalIncome == 0 && totalExpenses == 0) return;

  logPlaythroughEvent(
    gameDate: date,
    type: PlaythroughEventType.financialPeriodClosed,
    data: {
      'periodKind': 'accounting_cycle',
      'income': income,
      'expenses': expenses,
      'totalIncome': totalIncome,
      'totalExpenses': totalExpenses,
      'closingFunds': ledger.funds,
      'cumulativeIncome': ledger.totalIncome,
      'cumulativeExpense': ledger.totalExpense,
    },
  );
}

// Explicit history wire values; changing a Dart category name must not rename
// previously recorded categories. Missing entries in an event mean zero.
String _incomeWireName(Income category) => switch (category) {
  Income.brownies => 'brownies',
  Income.cars => 'cars',
  Income.creditCardFraud => 'credit_card_fraud',
  Income.donations => 'donations',
  Income.artSales => 'art_sales',
  Income.embezzlement => 'embezzlement',
  Income.extortion => 'extortion',
  Income.hustling => 'hustling',
  Income.pawn => 'pawn',
  Income.prostitution => 'prostitution',
  Income.busking => 'busking',
  Income.thievery => 'thievery',
  Income.tshirts => 'tshirts',
  Income.ransom => 'ransom',
};

String _expenseWireName(Expense category) => switch (category) {
  Expense.activism => 'activism',
  Expense.confiscated => 'confiscated',
  Expense.dating => 'dating',
  Expense.artSupplies => 'art_supplies',
  Expense.sewingSupplies => 'sewing_supplies',
  Expense.groceries => 'groceries',
  Expense.hostageTending => 'hostage_tending',
  Expense.legalFees => 'legal_fees',
  Expense.cars => 'cars',
  Expense.shopping => 'shopping',
  Expense.recruitment => 'recruitment',
  Expense.rent => 'rent',
  Expense.compoundUpgrades => 'compound_upgrades',
  Expense.training => 'training',
  Expense.travel => 'travel',
  Expense.augmentation => 'augmentation',
  Expense.hospitalBills => 'hospital_bills',
};
