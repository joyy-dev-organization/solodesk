import '../models/invoice.dart';
import '../models/money.dart';

class CurrencyTotals {
  final String currency;
  final Money totalOutstanding; // Sum of unpaid (including overdue)
  final Money totalOverdue;     // Sum of unpaid with dueDate < referenceDate
  final Money totalPaid;        // Sum of paid invoices
  final int unpaidCount;
  final int overdueCount;
  final int paidCount;

  const CurrencyTotals({
    required this.currency,
    required this.totalOutstanding,
    required this.totalOverdue,
    required this.totalPaid,
    required this.unpaidCount,
    required this.overdueCount,
    required this.paidCount,
  });

  factory CurrencyTotals.zero(String currency) => CurrencyTotals(
        currency: currency,
        totalOutstanding: Money(minorUnits: 0, currency: currency),
        totalOverdue: Money(minorUnits: 0, currency: currency),
        totalPaid: Money(minorUnits: 0, currency: currency),
        unpaidCount: 0,
        overdueCount: 0,
        paidCount: 0,
      );
}

class InvoiceTotalsResult {
  final Map<String, CurrencyTotals> totalsByCurrency;
  final int totalInvoicesCount;
  final int totalUnpaidCount;
  final int totalOverdueCount;
  final int totalPaidCount;

  const InvoiceTotalsResult({
    required this.totalsByCurrency,
    required this.totalInvoicesCount,
    required this.totalUnpaidCount,
    required this.totalOverdueCount,
    required this.totalPaidCount,
  });
}

class InvoiceTotalsCalculator {
  /// Computes totals grouped strictly by ISO currency code.
  /// Paid and cancelled invoices are strictly excluded from unpaid and overdue totals.
  static InvoiceTotalsResult calculate(
    List<Invoice> invoices, {
    DateTime? referenceDate,
  }) {
    final ref = Invoice.toCalendarDate(referenceDate ?? DateTime.now());
    final currencyMap = <String, CurrencyTotals>{};

    int totalInvoices = invoices.length;
    int totalUnpaid = 0;
    int totalOverdue = 0;
    int totalPaid = 0;

    for (final inv in invoices) {
      if (inv.status == InvoiceStatus.cancelled) continue;

      final curr = inv.amount.currency.toUpperCase();
      final currentTotals = currencyMap[curr] ?? CurrencyTotals.zero(curr);

      if (inv.status == InvoiceStatus.paid) {
        totalPaid++;
        currencyMap[curr] = CurrencyTotals(
          currency: curr,
          totalOutstanding: currentTotals.totalOutstanding,
          totalOverdue: currentTotals.totalOverdue,
          totalPaid: currentTotals.totalPaid + inv.amount,
          unpaidCount: currentTotals.unpaidCount,
          overdueCount: currentTotals.overdueCount,
          paidCount: currentTotals.paidCount + 1,
        );
      } else if (inv.status == InvoiceStatus.unpaid) {
        totalUnpaid++;
        final isOverdue = inv.isOverdueAt(ref);
        if (isOverdue) totalOverdue++;

        final newOutstanding = currentTotals.totalOutstanding + inv.amount;
        final newOverdue = isOverdue
            ? currentTotals.totalOverdue + inv.amount
            : currentTotals.totalOverdue;

        currencyMap[curr] = CurrencyTotals(
          currency: curr,
          totalOutstanding: newOutstanding,
          totalOverdue: newOverdue,
          totalPaid: currentTotals.totalPaid,
          unpaidCount: currentTotals.unpaidCount + 1,
          overdueCount: currentTotals.overdueCount + (isOverdue ? 1 : 0),
          paidCount: currentTotals.paidCount,
        );
      }
    }

    return InvoiceTotalsResult(
      totalsByCurrency: currencyMap,
      totalInvoicesCount: totalInvoices,
      totalUnpaidCount: totalUnpaid,
      totalOverdueCount: totalOverdue,
      totalPaidCount: totalPaid,
    );
  }
}
