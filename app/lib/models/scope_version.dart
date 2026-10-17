import 'package:flutter/foundation.dart';
import 'scope_item.dart';

@immutable
class ScopeVersion {
  final String id;
  final String projectId;
  final int versionNumber;
  final String title;
  final String status; // 'draft' | 'approved'
  final DateTime? approvedAt;
  final String? notes;
  final bool isSynthetic;
  final DateTime createdAt;

  const ScopeVersion({
    required this.id,
    required this.projectId,
    required this.versionNumber,
    required this.title,
    required this.status,
    this.approvedAt,
    this.notes,
    this.isSynthetic = false,
    required this.createdAt,
  });

  bool get isApproved => status == 'approved';

  ScopeVersion copyWith({
    String? title,
    String? status,
    DateTime? approvedAt,
    String? notes,
    bool? isSynthetic,
  }) =>
      ScopeVersion(
        id: id,
        projectId: projectId,
        versionNumber: versionNumber,
        title: title ?? this.title,
        status: status ?? this.status,
        approvedAt: approvedAt ?? this.approvedAt,
        notes: notes ?? this.notes,
        isSynthetic: isSynthetic ?? this.isSynthetic,
        createdAt: createdAt,
      );

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'project_id': projectId,
        'version_number': versionNumber,
        'title': title,
        'status': status,
        'approved_at': approvedAt?.toUtc().toIso8601String(),
        'notes': notes,
        'is_synthetic': isSynthetic ? 1 : 0,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory ScopeVersion.fromDbMap(Map<String, dynamic> map) => ScopeVersion(
        id: map['id'] as String,
        projectId: map['project_id'] as String,
        versionNumber: map['version_number'] as int,
        title: map['title'] as String,
        status: map['status'] as String,
        approvedAt: map['approved_at'] != null
            ? DateTime.parse(map['approved_at'] as String)
            : null,
        notes: map['notes'] as String?,
        isSynthetic: (map['is_synthetic'] as int) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

@immutable
class ScopeVersionWithItems {
  final ScopeVersion version;
  final List<ScopeItem> items;

  const ScopeVersionWithItems({
    required this.version,
    required this.items,
  });
}

class ScopeImmutabilityException implements Exception {
  final String message;
  const ScopeImmutabilityException(this.message);

  @override
  String toString() => message;
}
