import 'dart:convert';
import 'package:flutter/foundation.dart';

@immutable
class ServicePreference {
  final String id;
  final List<String> niches;
  final String defaultCurrency;
  final String businessName;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ServicePreference({
    this.id = 'default',
    required this.niches,
    required this.defaultCurrency,
    required this.businessName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ServicePreference.initial() {
    final now = DateTime.now().toUtc();
    return ServicePreference(
      id: 'default',
      niches: const ['Design & branding', 'Writing & content'],
      defaultCurrency: 'NGN',
      businessName: 'ladydiamond · Independent freelancer',
      createdAt: now,
      updatedAt: now,
    );
  }

  ServicePreference copyWith({
    List<String>? niches,
    String? defaultCurrency,
    String? businessName,
    DateTime? updatedAt,
  }) {
    return ServicePreference(
      id: id,
      niches: niches ?? this.niches,
      defaultCurrency: defaultCurrency ?? this.defaultCurrency,
      businessName: businessName ?? this.businessName,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'niches_json': jsonEncode(niches),
        'default_currency': defaultCurrency,
        'business_name': businessName,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory ServicePreference.fromDbMap(Map<String, dynamic> map) =>
      ServicePreference(
        id: map['id'] as String,
        niches: List<String>.from(
          jsonDecode(map['niches_json'] as String) as List,
        ),
        defaultCurrency: map['default_currency'] as String,
        businessName: map['business_name'] as String? ?? 'ladydiamond · Independent freelancer',
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}
