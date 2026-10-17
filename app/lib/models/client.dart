import 'package:flutter/foundation.dart';

@immutable
class Client {
  final String id;
  final String name;
  final String initials;
  final String? company;
  final String? email;
  final String? notes;
  final bool isSynthetic;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Client({
    required this.id,
    required this.name,
    required this.initials,
    this.company,
    this.email,
    this.notes,
    this.isSynthetic = false,
    required this.createdAt,
    required this.updatedAt,
  });

  String get displayName => company != null && company!.isNotEmpty ? '$name ($company)' : name;

  static String computeInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '??';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Client copyWith({
    String? name,
    String? company,
    String? email,
    String? notes,
    bool? isSynthetic,
    DateTime? updatedAt,
  }) {
    final effectiveName = name ?? this.name;
    return Client(
      id: id,
      name: effectiveName,
      initials: computeInitials(effectiveName),
      company: company ?? this.company,
      email: email ?? this.email,
      notes: notes ?? this.notes,
      isSynthetic: isSynthetic ?? this.isSynthetic,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'name': name,
        'initials': initials,
        'company': company,
        'email': email,
        'notes': notes,
        'is_synthetic': isSynthetic ? 1 : 0,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Client.fromDbMap(Map<String, dynamic> map) => Client(
        id: map['id'] as String,
        name: map['name'] as String,
        initials: map['initials'] as String? ?? computeInitials(map['name'] as String),
        company: map['company'] as String?,
        email: map['email'] as String?,
        notes: map['notes'] as String?,
        isSynthetic: (map['is_synthetic'] as int) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}
