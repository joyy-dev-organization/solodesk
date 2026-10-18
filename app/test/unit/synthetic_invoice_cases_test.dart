import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:solodesk/models/invoice.dart';
import 'package:solodesk/models/money.dart';

void main() {
  group('Synthetic Invoice Cases Integration (fixtures/synthetic-cases.json)', () {
    late Map<String, dynamic> fixturesJson;
    late List<dynamic> invoiceCases;

    setUpAll(() async {
      final file = File('../fixtures/synthetic-cases.json');
      expect(await file.exists(), isTrue, reason: 'fixtures/synthetic-cases.json must exist');
      final content = await file.readAsString();
      fixturesJson = jsonDecode(content) as Map<String, dynamic>;
      invoiceCases = fixturesJson['invoiceReminders'] as List<dynamic>;
      expect(invoiceCases.length, greaterThanOrEqualTo(4));
    });

    test('Case 1 (gentle due today): deserializes and computes calendar date correctly', () {
      final c1 = invoiceCases[0] as Map<String, dynamic>;
      expect(c1['id'], 'reminder-1-gentle-due-today');
      expect(c1['daysOverdue'], 0);
      expect(c1['tone'], 'gentle');

      final dueDate = DateTime.parse(c1['dueDate'] as String);
      final refDate = DateTime.parse(c1['dueDate'] as String); // evaluated on its due date

      final inv = Invoice(
        id: c1['invoiceId'] as String,
        clientId: 'client-test-1',
        invoiceNumber: c1['invoiceNumber'] as String,
        amount: const Money(minorUnits: 120000, currency: 'USD'),
        issueDate: dueDate.subtract(const Duration(days: 14)),
        dueDate: dueDate,
        status: InvoiceStatus.unpaid,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(inv.isDueToday(refDate), isTrue);
      expect(inv.isOverdueAt(refDate), isFalse);
      expect(inv.daysOverdueAt(refDate), 0);
      expect(inv.displayStatusAt(refDate), InvoiceDisplayStatus.dueToday);
    });

    test('Case 2 (polite standard overdue 7d): daysOverdue matches fixture', () {
      final c2 = invoiceCases[1] as Map<String, dynamic>;
      expect(c2['id'], 'reminder-2-polite-standard-overdue');
      expect(c2['daysOverdue'], 7);

      final dueDate = DateTime.parse(c2['dueDate'] as String);
      final refDate = dueDate.add(const Duration(days: 7));

      final inv = Invoice(
        id: c2['invoiceId'] as String,
        clientId: 'client-test-2',
        invoiceNumber: c2['invoiceNumber'] as String,
        amount: const Money(minorUnits: 345000, currency: 'EUR'),
        issueDate: dueDate.subtract(const Duration(days: 14)),
        dueDate: dueDate,
        status: InvoiceStatus.unpaid,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(inv.isDueToday(refDate), isFalse);
      expect(inv.isOverdueAt(refDate), isTrue);
      expect(inv.daysOverdueAt(refDate), 7);
      expect(inv.displayStatusAt(refDate), InvoiceDisplayStatus.overdue);
    });

    test('Case 3 (firm overdue escalation 30d): displays overdue status and correct currency symbol', () {
      final c3 = invoiceCases[2] as Map<String, dynamic>;
      expect(c3['id'], 'reminder-3-firm-escalation-overdue');
      expect(c3['daysOverdue'], 30);
      expect(c3['currency'], 'GBP');

      final dueDate = DateTime.parse(c3['dueDate'] as String);
      final refDate = dueDate.add(const Duration(days: 30));

      final inv = Invoice(
        id: c3['invoiceId'] as String,
        clientId: 'client-test-3',
        invoiceNumber: c3['invoiceNumber'] as String,
        amount: const Money(minorUnits: 580000, currency: 'GBP'),
        issueDate: dueDate.subtract(const Duration(days: 14)),
        dueDate: dueDate,
        status: InvoiceStatus.unpaid,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(inv.amount.formattedGrouped, '£5,800.00');
      expect(inv.isOverdueAt(refDate), isTrue);
      expect(inv.daysOverdueAt(refDate), 30);
    });

    test('Case 4 (adversarial prompt injection NGN): preserves exact minor units and kobo formatting', () {
      final c4 = invoiceCases[3] as Map<String, dynamic>;
      expect(c4['id'], 'reminder-4-security-prompt-injection');
      expect(c4['currency'], 'NGN');

      const money = Money(minorUnits: 75000000, currency: 'NGN');
      expect(money.formattedGrouped, '₦750,000.00');
      expect(money.toMajorUnits(), 750000.0);
    });
  });
}
