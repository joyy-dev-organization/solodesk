import 'package:flutter/foundation.dart';

@immutable
class StarterScopeDeliverable {
  final String title;
  final String description;

  const StarterScopeDeliverable({
    required this.title,
    required this.description,
  });

  factory StarterScopeDeliverable.fromJson(Map<String, dynamic> json) {
    return StarterScopeDeliverable(
      title: json['title'] as String? ?? 'Untitled Deliverable',
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
  };
}

@immutable
class BriefCheckResult {
  final String requestId;
  final List<String> statedRequirements;
  final List<String> assumptions;
  final List<String> omissions;
  final List<String> suggestedQuestions;
  final List<StarterScopeDeliverable> starterScopeItems;

  const BriefCheckResult({
    required this.requestId,
    required this.statedRequirements,
    required this.assumptions,
    required this.omissions,
    required this.suggestedQuestions,
    required this.starterScopeItems,
  });

  /// Derives an executive goal summary from stated facts
  String get goalSummary {
    if (statedRequirements.isNotEmpty) {
      return statedRequirements.take(2).join('; ');
    }
    if (starterScopeItems.isNotEmpty) {
      return starterScopeItems.first.title;
    }
    return 'Client requirements analysis';
  }

  factory BriefCheckResult.fromJson(Map<String, dynamic> json) {
    final requestId = json['requestId'] as String? ?? '';
    final data = json['data'] as Map<String, dynamic>? ?? json;

    return BriefCheckResult(
      requestId: requestId,
      statedRequirements: List<String>.from(data['statedRequirements'] as List? ?? []),
      assumptions: List<String>.from(data['assumptions'] as List? ?? []),
      omissions: List<String>.from(data['omissions'] as List? ?? []),
      suggestedQuestions: List<String>.from(data['suggestedQuestions'] as List? ?? []),
      starterScopeItems: (data['starterScopeItems'] as List? ?? [])
          .map((item) => StarterScopeDeliverable.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Adapts Flutter UI niche categories to the backend Zod enum ('design' | 'writing' | 'general')
class NicheAdapter {
  static String toBackendNiche(String uiNiche) {
    final lower = uiNiche.toLowerCase();
    if (lower.contains('design') || lower.contains('brand')) return 'design';
    if (lower.contains('writ') || lower.contains('content') || lower.contains('copy')) return 'writing';
    return 'general';
  }
}
