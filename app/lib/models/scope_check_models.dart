import 'package:flutter/material.dart';
import '../models/scope_item.dart';
import '../theme/colors.dart';

/// Semantic classification of client requests against agreed scope.
enum ScopeClassification {
  included,
  potentiallyOutside,
  needsClarification;

  static ScopeClassification fromString(String val) {
    final lower = val.toLowerCase().trim();
    if (lower.contains('include') || lower == 'in_scope' || lower == 'in-scope') {
      return ScopeClassification.included;
    }
    if (lower.contains('outside') ||
        lower.contains('out_of_scope') ||
        lower.contains('out-of-scope') ||
        lower.contains('extra') ||
        lower.contains('excluded')) {
      return ScopeClassification.potentiallyOutside;
    }
    return ScopeClassification.needsClarification;
  }

  String toBackendString() {
    switch (this) {
      case ScopeClassification.included:
        return 'included';
      case ScopeClassification.potentiallyOutside:
        return 'out_of_scope';
      case ScopeClassification.needsClarification:
        return 'needs_clarification';
    }
  }

  String get label {
    switch (this) {
      case ScopeClassification.included:
        return 'INCLUDED';
      case ScopeClassification.potentiallyOutside:
        return 'OUT OF SCOPE';
      case ScopeClassification.needsClarification:
        return 'NEEDS CLARIFICATION';
    }
  }

  Color get foregroundColor {
    switch (this) {
      case ScopeClassification.included:
        return SoloDeskColors.green;
      case ScopeClassification.potentiallyOutside:
        return SoloDeskColors.amber;
      case ScopeClassification.needsClarification:
        return SoloDeskColors.primary;
    }
  }

  Color get backgroundColor {
    switch (this) {
      case ScopeClassification.included:
        return SoloDeskColors.greenBg;
      case ScopeClassification.potentiallyOutside:
        return SoloDeskColors.amberBg;
      case ScopeClassification.needsClarification:
        return SoloDeskColors.primaryPale;
    }
  }

  IconData get icon {
    switch (this) {
      case ScopeClassification.included:
        return Icons.check_circle_outline;
      case ScopeClassification.potentiallyOutside:
        return Icons.warning_amber_rounded;
      case ScopeClassification.needsClarification:
        return Icons.help_outline_rounded;
    }
  }
}

/// Evaluated finding comparing client request excerpt to scope deliverable.
@immutable
class ScopeFinding {
  final String requestExcerpt;
  final ScopeClassification classification;
  final String explanation;
  final String? matchedScopeItemId;
  final String? matchedScopeItemDescription;

  const ScopeFinding({
    required this.requestExcerpt,
    required this.classification,
    required this.explanation,
    this.matchedScopeItemId,
    this.matchedScopeItemDescription,
  });

  factory ScopeFinding.fromJson(Map<String, dynamic> json) {
    final catRaw = json['category'] ?? json['classification'] ?? 'needs_clarification';
    return ScopeFinding(
      requestExcerpt: json['requestExcerpt'] as String? ?? json['excerpt'] as String? ?? '',
      classification: ScopeClassification.fromString(catRaw.toString()),
      explanation: json['explanation'] as String? ?? json['rationale'] as String? ?? '',
      matchedScopeItemId: json['matchedScopeItemId'] as String?,
      matchedScopeItemDescription: json['matchedScopeItemDescription'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'requestExcerpt': requestExcerpt,
    'category': classification.toBackendString(),
    'explanation': explanation,
    'matchedScopeItemId': matchedScopeItemId,
    'matchedScopeItemDescription': matchedScopeItemDescription,
  };
}

/// Structured response from Mastra ScopeShield workflow.
@immutable
class ScopeCheckResult {
  final String requestId;
  final List<ScopeFinding> findings;
  final String replyDraft;
  final String summary;

  const ScopeCheckResult({
    required this.requestId,
    required this.findings,
    required this.replyDraft,
    required this.summary,
  });

  int get includedCount =>
      findings.where((f) => f.classification == ScopeClassification.included).length;

  int get outsideCount =>
      findings.where((f) => f.classification == ScopeClassification.potentiallyOutside).length;

  int get clarificationCount =>
      findings.where((f) => f.classification == ScopeClassification.needsClarification).length;

  factory ScopeCheckResult.fromJson(Map<String, dynamic> json) {
    final requestId = json['requestId'] as String? ?? '';
    final data = json['data'] as Map<String, dynamic>? ?? json;

    final findingsList = (data['findings'] as List? ?? data['evaluations'] as List? ?? [])
        .map((e) => ScopeFinding.fromJson(e as Map<String, dynamic>))
        .toList();

    return ScopeCheckResult(
      requestId: requestId,
      findings: findingsList,
      replyDraft: data['replyDraft'] as String? ?? data['suggestedReply'] as String? ?? '',
      summary: data['summary'] as String? ?? '',
    );
  }
}

/// Adapter converting SQLite ScopeItem to backend ScopeItemInput schema
class ScopeItemAdapter {
  static Map<String, dynamic> toBackendItem(ScopeItem item) {
    return {
      'id': item.id,
      'category': item.category,
      'description': item.description,
    };
  }
}
