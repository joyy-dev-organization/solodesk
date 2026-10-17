import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// Supported reminder tones for PolitePay invoice follow-ups.
enum ReminderTone {
  gentle,
  polite,
  firm;

  static ReminderTone fromString(String val) {
    final lower = val.toLowerCase().trim();
    if (lower.contains('gentle') || lower.contains('friendly') || lower.contains('soft')) {
      return ReminderTone.gentle;
    }
    if (lower.contains('firm') || lower.contains('urgent') || lower.contains('final') || lower.contains('escalat')) {
      return ReminderTone.firm;
    }
    return ReminderTone.polite;
  }

  String toBackendString() {
    switch (this) {
      case ReminderTone.gentle:
        return 'gentle';
      case ReminderTone.polite:
        return 'polite';
      case ReminderTone.firm:
        return 'firm';
    }
  }

  String get label {
    switch (this) {
      case ReminderTone.gentle:
        return 'Gentle';
      case ReminderTone.polite:
        return 'Polite';
      case ReminderTone.firm:
        return 'Firm';
    }
  }

  String get description {
    switch (this) {
      case ReminderTone.gentle:
        return 'Warm, relationship-preserving reminder for upcoming or recently due invoices.';
      case ReminderTone.polite:
        return 'Standard professional reminder balancing courtesy with clarity.';
      case ReminderTone.firm:
        return 'Direct, clear follow-up for significantly overdue accounts with explicit reference.';
    }
  }

  Color get color {
    switch (this) {
      case ReminderTone.gentle:
        return SoloDeskColors.green;
      case ReminderTone.polite:
        return SoloDeskColors.primary;
      case ReminderTone.firm:
        return SoloDeskColors.amber;
    }
  }

  IconData get icon {
    switch (this) {
      case ReminderTone.gentle:
        return Icons.sentiment_satisfied_alt_rounded;
      case ReminderTone.polite:
        return Icons.mark_email_read_outlined;
      case ReminderTone.firm:
        return Icons.priority_high_rounded;
    }
  }
}

/// Structured response from Mastra PolitePay workflow.
@immutable
class InvoiceReminderResult {
  final String requestId;
  final String reminderDraft;
  final String summary;
  final ReminderTone toneUsed;

  const InvoiceReminderResult({
    required this.requestId,
    required this.reminderDraft,
    required this.summary,
    required this.toneUsed,
  });

  factory InvoiceReminderResult.fromJson(Map<String, dynamic> json) {
    final requestId = json['requestId'] as String? ?? '';
    final data = json['data'] as Map<String, dynamic>? ?? json;

    final draft = data['reminderDraft'] as String? ??
        data['draft'] as String? ??
        data['suggestedMessage'] as String? ??
        '';

    final summary = data['summary'] as String? ?? '';
    final toneStr = data['toneUsed'] as String? ?? 'polite';

    return InvoiceReminderResult(
      requestId: requestId,
      reminderDraft: draft,
      summary: summary,
      toneUsed: ReminderTone.fromString(toneStr),
    );
  }

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'data': {
      'reminderDraft': reminderDraft,
      'summary': summary,
      'toneUsed': toneUsed.toBackendString(),
    },
  };
}
