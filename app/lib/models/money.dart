import 'package:flutter/foundation.dart';

@immutable
class Money {
  final int minorUnits; // e.g. 150000 = $1,500.00 or ₦1,500.00
  final String currency; // 3-letter ISO 4217, e.g. 'USD', 'EUR', 'GBP', 'NGN'

  const Money({
    required this.minorUnits,
    required this.currency,
  })  : assert(minorUnits >= 0, 'Money minorUnits cannot be negative'),
        assert(currency.length == 3, 'Currency must be a 3-letter ISO 4217 code');

  static const Money zeroUSD = Money(minorUnits: 0, currency: 'USD');
  static const Money zeroNGN = Money(minorUnits: 0, currency: 'NGN');

  factory Money.fromMajorUnits(double majorUnits, String currency) {
    if (majorUnits < 0) throw ArgumentError('Amount cannot be negative');
    final minor = (majorUnits * 100).round();
    return Money(minorUnits: minor, currency: currency.toUpperCase());
  }

  Money operator +(Money other) {
    if (currency.toUpperCase() != other.currency.toUpperCase()) {
      throw ArgumentError('Currency mismatch: cannot add $currency and ${other.currency}');
    }
    return Money(minorUnits: minorUnits + other.minorUnits, currency: currency);
  }

  Money operator -(Money other) {
    if (currency.toUpperCase() != other.currency.toUpperCase()) {
      throw ArgumentError('Currency mismatch: cannot subtract $currency and ${other.currency}');
    }
    final result = minorUnits - other.minorUnits;
    if (result < 0) throw ArgumentError('Resulting money cannot be negative');
    return Money(minorUnits: result, currency: currency);
  }

  double toMajorUnits() => minorUnits / 100.0;

  String format() {
    final major = (minorUnits ~/ 100).toString();
    final minor = (minorUnits % 100).toString().padLeft(2, '0');
    switch (currency.toUpperCase()) {
      case 'USD':
        return '\$$major.$minor';
      case 'EUR':
        return '€$major.$minor';
      case 'GBP':
        return '£$major.$minor';
      case 'NGN':
        return '₦$major.$minor';
      case 'GHS':
        return 'GH₵$major.$minor';
      default:
        return '$currency $major.$minor';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Money &&
          runtimeType == other.runtimeType &&
          minorUnits == other.minorUnits &&
          currency == other.currency;

  @override
  int get hashCode => minorUnits.hashCode ^ currency.hashCode;

  @override
  String toString() => format();
}
