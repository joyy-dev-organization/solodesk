import 'package:flutter/foundation.dart';

@immutable
class ScopeItem {
  final String id;
  final String scopeVersionId;
  final String category; // 'included' | 'excluded' | 'allowance'
  final String description;
  final int sortOrder;
  final bool isSynthetic;

  const ScopeItem({
    required this.id,
    required this.scopeVersionId,
    required this.category,
    required this.description,
    this.sortOrder = 0,
    this.isSynthetic = false,
  });

  bool get isIncluded => category == 'included';
  bool get isExcluded => category == 'excluded';
  bool get isAllowance => category == 'allowance';

  ScopeItem copyWith({
    String? category,
    String? description,
    int? sortOrder,
    bool? isSynthetic,
  }) =>
      ScopeItem(
        id: id,
        scopeVersionId: scopeVersionId,
        category: category ?? this.category,
        description: description ?? this.description,
        sortOrder: sortOrder ?? this.sortOrder,
        isSynthetic: isSynthetic ?? this.isSynthetic,
      );

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'scope_version_id': scopeVersionId,
        'category': category,
        'description': description,
        'sort_order': sortOrder,
        'is_synthetic': isSynthetic ? 1 : 0,
      };

  factory ScopeItem.fromDbMap(Map<String, dynamic> map) => ScopeItem(
        id: map['id'] as String,
        scopeVersionId: map['scope_version_id'] as String,
        category: map['category'] as String,
        description: map['description'] as String,
        sortOrder: map['sort_order'] as int,
        isSynthetic: (map['is_synthetic'] as int) == 1,
      );
}
