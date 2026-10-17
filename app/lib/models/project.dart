import 'package:flutter/foundation.dart';
import 'money.dart';

@immutable
class Project {
  final String id;
  final String clientId;
  final String name;
  final String niche;
  final Money budget;
  final String status; // 'lead' | 'drafting' | 'active' | 'completed' | 'archived'
  final bool isSynthetic;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Project({
    required this.id,
    required this.clientId,
    required this.name,
    required this.niche,
    required this.budget,
    required this.status,
    this.isSynthetic = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Project copyWith({
    String? name,
    String? niche,
    Money? budget,
    String? status,
    bool? isSynthetic,
    DateTime? updatedAt,
  }) =>
      Project(
        id: id,
        clientId: clientId,
        name: name ?? this.name,
        niche: niche ?? this.niche,
        budget: budget ?? this.budget,
        status: status ?? this.status,
        isSynthetic: isSynthetic ?? this.isSynthetic,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
      );

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'client_id': clientId,
        'name': name,
        'niche': niche,
        'currency': budget.currency,
        'budget_minor_units': budget.minorUnits,
        'status': status,
        'is_synthetic': isSynthetic ? 1 : 0,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Project.fromDbMap(Map<String, dynamic> map) => Project(
        id: map['id'] as String,
        clientId: map['client_id'] as String,
        name: map['name'] as String,
        niche: map['niche'] as String,
        budget: Money(
          minorUnits: map['budget_minor_units'] as int,
          currency: map['currency'] as String,
        ),
        status: map['status'] as String,
        isSynthetic: (map['is_synthetic'] as int) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}
