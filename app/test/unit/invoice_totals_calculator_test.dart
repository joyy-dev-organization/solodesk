import 'package:flutter_test/flutter_test.dart';
import 'package:solodesk/domain/invoice_totals_calculator.dart';
import 'package:solodesk/models/invoice.dart';
import 'package:solodesk/models/money.dart';

void main() {
  group('Milestone M5: InvoiceTotalsCalculator Tests', () {
    final refDate = DateTime(2026, 10, 17);

    test('Due Today Rule: invoice due on referenceDate is counted as unpaid, not overdue', () {
      final inv = Invoice(
        id: 'inv-today',
        clientId: 'c1',
        invoiceNumber: 'INV-001',
        amount: const Money(minorUnits: 150000, currency: 'USD'), // $1,500.00
        issueDate: DateTime(2026, 10, 3),
        dueDate: DateTime(2026, 10, 17), // Due today
        status: InvoiceStatus.unpaid,
        createdAt: DateTime(2026, 10, 3),
        updatedAt: DateTime(2026, 10, 3),
      );

      expect(inv.isDueToday(refDate), isTrue);
      expect(inv.isOverdueAt(refDate), isFalse);
      expect(inv.daysOverdueAt(refDate), 0);
      expect(inv.displayStatusAt(refDate), InvoiceDisplayStatus.dueToday);

      final result = InvoiceTotalsCalculator.calculate([inv], referenceDate: refDate);
      expect(result.totalInvoicesCount, 1);
      expect(result.totalUnpaidCount, 1);
      expect(result.totalOverdueCount, 0);
      expect(result.totalPaidCount, 0);

      final usdTotals = result.totalsByCurrency['USD']!;
      expect(usdTotals.totalOutstanding.minorUnits, 150000);
      expect(usdTotals.totalOverdue.minorUnits, 0);
      expect(usdTotals.totalPaid.minorUnits, 0);
    });

    test('Overdue Rule: invoice due prior to referenceDate is counted in both outstanding and overdue', () {
      final inv = Invoice(
        id: 'inv-overdue',
        clientId: 'c1',
        invoiceNumber: 'INV-002',
        amount: const Money(minorUnits: 22000000, currency: 'NGN'), // ₦220,000.00
        issueDate: DateTime(2026, 9, 28),
        dueDate: DateTime(2026, 10, 12), // 5 days overdue relative to 2026-10-17
        status: InvoiceStatus.unpaid,
        createdAt: DateTime(2026, 9, 28),
        updatedAt: DateTime(2026, 9, 28),
      );

      expect(inv.isDueToday(refDate), isFalse);
      expect(inv.isOverdueAt(refDate), isTrue);
      expect(inv.daysOverdueAt(refDate), 5);
      expect(inv.displayStatusAt(refDate), InvoiceDisplayStatus.overdue);

      final result = InvoiceTotalsCalculator.calculate([inv], referenceDate: refDate);
      expect(result.totalInvoicesCount, 1);
      expect(result.totalUnpaidCount, 1);
      expect(result.totalOverdueCount, 1);
      expect(result.totalPaidCount, 0);

      final ngnTotals = result.totalsByCurrency['NGN']!;
      expect(ngnTotals.totalOutstanding.minorUnits, 22000000);
      expect(ngnTotals.totalOverdue.minorUnits, 22000000);
      expect(ngnTotals.totalPaid.minorUnits, 0);
    });

    test('Paid Exclusion Rule: paid invoices are strictly excluded from unpaid and overdue sums', () {
      final paidInv = Invoice(
        id: 'inv-paid',
        clientId: 'c1',
        invoiceNumber: 'INV-003',
        amount: const Money(minorUnits: 345000, currency: 'EUR'), // €3,450.00
        issueDate: DateTime(2026, 9, 1),
        dueDate: DateTime(2026, 9, 15), // Was due in the past, but paid
        status: InvoiceStatus.paid,
        paidAt: DateTime(2026, 9, 14),
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 14),
      );

      expect(paidInv.isOverdueAt(refDate), isFalse);
      expect(paidInv.isDueToday(refDate), isFalse);
      expect(paidInv.displayStatusAt(refDate), InvoiceDisplayStatus.paid);

      final result = InvoiceTotalsCalculator.calculate([paidInv], referenceDate: refDate);
      expect(result.totalInvoicesCount, 1);
      expect(result.totalUnpaidCount, 0);
      expect(result.totalOverdueCount, 0);
      expect(result.totalPaidCount, 1);

      final eurTotals = result.totalsByCurrency['EUR']!;
      expect(eurTotals.totalOutstanding.minorUnits, 0);
      expect(eurTotals.totalOverdue.minorUnits, 0);
      expect(eurTotals.totalPaid.minorUnits, 345000);
    });

    test('Multi-Currency Separation Rule: NGN, USD, and EUR never cross-sum', () {
      final invoices = [
        Invoice(
          id: 'inv-1',
          clientId: 'c1',
          invoiceNumber: 'INV-NGN-1',
          amount: const Money(minorUnits: 10000000, currency: 'NGN'), // ₦100,000.00
          issueDate: DateTime(2026, 10, 1),
          dueDate: DateTime(2026, 10, 10), // overdue
          status: InvoiceStatus.unpaid,
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 1),
        ),
        Invoice(
          id: 'inv-2',
          clientId: 'c1',
          invoiceNumber: 'INV-NGN-2',
          amount: const Money(minorUnits: 5000000, currency: 'NGN'), // ₦50,000.00
          issueDate: DateTime(2026, 10, 10),
          dueDate: DateTime(2026, 10, 24), // upcoming
          status: InvoiceStatus.unpaid,
          createdAt: DateTime(2026, 10, 10),
          updatedAt: DateTime(2026, 10, 10),
        ),
        Invoice(
          id: 'inv-3',
          clientId: 'c2',
          invoiceNumber: 'INV-USD-1',
          amount: const Money(minorUnits: 20000, currency: 'USD'), // $200.00
          issueDate: DateTime(2026, 10, 1),
          dueDate: DateTime(2026, 10, 15), // overdue
          status: InvoiceStatus.unpaid,
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 1),
        ),
        Invoice(
          id: 'inv-4',
          clientId: 'c3',
          invoiceNumber: 'INV-EUR-1',
          amount: const Money(minorUnits: 50000, currency: 'EUR'), // €500.00
          issueDate: DateTime(2026, 10, 1),
          dueDate: DateTime(2026, 10, 14),
          status: InvoiceStatus.paid,
          paidAt: DateTime(2026, 10, 13),
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 13),
        ),
      ];

      final result = InvoiceTotalsCalculator.calculate(invoices, referenceDate: refDate);
      expect(result.totalsByCurrency.keys, containsAll(['NGN', 'USD', 'EUR']));
      expect(result.totalsByCurrency.length, 3);

      // NGN Totals
      final ngn = result.totalsByCurrency['NGN']!;
      expect(ngn.totalOutstanding.minorUnits, 15000000); // ₦150,000.00
      expect(ngn.totalOverdue.minorUnits, 10000000);     // ₦100,000.00
      expect(ngn.totalPaid.minorUnits, 0);
      expect(ngn.unpaidCount, 2);
      expect(ngn.overdueCount, 1);
      expect(ngn.paidCount, 0);

      // USD Totals
      final usd = result.totalsByCurrency['USD']!;
      expect(usd.totalOutstanding.minorUnits, 20000); // $200.00
      expect(usd.totalOverdue.minorUnits, 20000);     // $200.00
      expect(usd.totalPaid.minorUnits, 0);
      expect(usd.unpaidCount, 1);
      expect(usd.overdueCount, 1);

      // EUR Totals
      final eur = result.totalsByCurrency['EUR']!;
      expect(eur.totalOutstanding.minorUnits, 0);
      expect(eur.totalOverdue.minorUnits, 0);
      expect(eur.totalPaid.minorUnits, 50000); // €500.00
      expect(eur.paidCount, 1);
    });

    test('Zero & Edge Value Handling: zero amount calculates without corruption', () {
      final zeroInv = Invoice(
        id: 'inv-zero',
        clientId: 'c1',
        invoiceNumber: 'INV-ZERO',
        amount: const Money(minorUnits: 0, currency: 'USD'),
        issueDate: DateTime(2026, 10, 1),
        dueDate: DateTime(2026, 10, 10),
        status: InvoiceStatus.unpaid,
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      );

      final result = InvoiceTotalsCalculator.calculate([zeroInv], referenceDate: refDate);
      expect(result.totalsByCurrency['USD']!.totalOutstanding.minorUnits, 0);
      expect(result.totalsByCurrency['USD']!.totalOverdue.minorUnits, 0);
    });
  });
}
