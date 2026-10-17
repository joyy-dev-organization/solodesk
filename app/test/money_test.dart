import 'package:flutter_test/flutter_test.dart';
import 'package:solodesk/models/money.dart';

void main() {
  group('Money Value Object', () {
    test('formats amounts correctly for known currencies', () {
      const m1 = Money(minorUnits: 150000, currency: 'USD');
      expect(m1.format(), equals('\$1500.00'));
      expect(m1.toMajorUnits(), equals(1500.0));

      const m2 = Money(minorUnits: 48500000, currency: 'NGN');
      expect(m2.format(), equals('₦485000.00'));

      const m3 = Money(minorUnits: 99, currency: 'EUR');
      expect(m3.format(), equals('€0.99'));
    });

    test('adds money with the same currency', () {
      const a = Money(minorUnits: 1000, currency: 'USD');
      const b = Money(minorUnits: 2500, currency: 'USD');
      final c = a + b;
      expect(c.minorUnits, equals(3500));
      expect(c.currency, equals('USD'));
    });

    test('rejects addition of mismatched currencies', () {
      const a = Money(minorUnits: 1000, currency: 'USD');
      const b = Money(minorUnits: 1000, currency: 'NGN');
      expect(() => a + b, throwsA(isA<ArgumentError>()));
    });

    test('subtracts money safely and prevents negative balances', () {
      const a = Money(minorUnits: 5000, currency: 'GBP');
      const b = Money(minorUnits: 2000, currency: 'GBP');
      final c = a - b;
      expect(c.minorUnits, equals(3000));

      // Subtracting larger from smaller throws
      expect(() => b - a, throwsA(isA<ArgumentError>()));
    });
  });
}
