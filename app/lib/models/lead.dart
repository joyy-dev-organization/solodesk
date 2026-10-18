import 'package:flutter/foundation.dart';
import 'money.dart';

enum LeadStage {
  discovery('discovery', 'Discovery'),
  proposalSent('proposal_sent', 'Proposal sent'),
  inDiscussion('in_discussion', 'In discussion'),
  won('won', 'Won'),
  lost('lost', 'Lost');

  final String dbValue;
  final String displayName;

  const LeadStage(this.dbValue, this.displayName);

  static LeadStage fromString(String val) {
    final normalized = val.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    switch (normalized) {
      case 'discovery':
      case 'new_lead':
      case 'new':
        return LeadStage.discovery;
      case 'proposal_sent':
        return LeadStage.proposalSent;
      case 'in_discussion':
      case 'follow_up':
      case 'contacted':
        return LeadStage.inDiscussion;
      case 'won':
        return LeadStage.won;
      case 'lost':
        return LeadStage.lost;
      default:
        return LeadStage.discovery;
    }
  }

  bool get isActive => this != LeadStage.won && this != LeadStage.lost;
  bool get isClosed => this == LeadStage.won || this == LeadStage.lost;
}

enum LeadFollowUpTiming {
  overdue,
  dueToday,
  upcoming,
  none,
}

@immutable
class Lead {
  final String id;
  final String? clientId;
  final String contactName;
  final String? company;
  final String? email;
  final String? phone;
  final String serviceNiche;
  final LeadStage stage;
  final Money? estimatedValue;
  final DateTime? nextFollowUpDate;
  final String? notes;
  final bool isSynthetic;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Lead({
    required this.id,
    this.clientId,
    required this.contactName,
    this.company,
    this.email,
    this.phone,
    required this.serviceNiche,
    required this.stage,
    this.estimatedValue,
    this.nextFollowUpDate,
    this.notes,
    this.isSynthetic = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Normalizes date to calendar date (stripping time) in local timezone to avoid UTC midnight rollover shifts.
  static DateTime toCalendarDate(DateTime dt) {
    final local = dt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// Formats date to YYYY-MM-DD
  static String formatCalendarDate(DateTime dt) {
    final d = toCalendarDate(dt);
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  LeadFollowUpTiming timingRelativeTo(DateTime referenceDate) {
    if (nextFollowUpDate == null || !stage.isActive) {
      return LeadFollowUpTiming.none;
    }
    final ref = toCalendarDate(referenceDate);
    final due = toCalendarDate(nextFollowUpDate!);

    if (due.isBefore(ref)) {
      return LeadFollowUpTiming.overdue;
    } else if (due.year == ref.year && due.month == ref.month && due.day == ref.day) {
      return LeadFollowUpTiming.dueToday;
    } else {
      return LeadFollowUpTiming.upcoming;
    }
  }

  bool isFollowUpOverdue([DateTime? referenceDate]) =>
      timingRelativeTo(referenceDate ?? DateTime.now()) == LeadFollowUpTiming.overdue;

  bool isFollowUpToday([DateTime? referenceDate]) =>
      timingRelativeTo(referenceDate ?? DateTime.now()) == LeadFollowUpTiming.dueToday;

  bool isFollowUpUpcoming([DateTime? referenceDate]) =>
      timingRelativeTo(referenceDate ?? DateTime.now()) == LeadFollowUpTiming.upcoming;

  String get displayName => (company != null && company!.trim().isNotEmpty)
      ? '$contactName ($company)'
      : contactName;

  Lead copyWith({
    String? clientId,
    String? contactName,
    String? company,
    String? email,
    String? phone,
    String? serviceNiche,
    LeadStage? stage,
    Money? estimatedValue,
    bool clearEstimatedValue = false,
    DateTime? nextFollowUpDate,
    bool clearNextFollowUpDate = false,
    String? notes,
    bool? isSynthetic,
    DateTime? updatedAt,
  }) {
    return Lead(
      id: id,
      clientId: clientId ?? this.clientId,
      contactName: contactName ?? this.contactName,
      company: company ?? this.company,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      serviceNiche: serviceNiche ?? this.serviceNiche,
      stage: stage ?? this.stage,
      estimatedValue: clearEstimatedValue ? null : (estimatedValue ?? this.estimatedValue),
      nextFollowUpDate: clearNextFollowUpDate ? null : (nextFollowUpDate ?? this.nextFollowUpDate),
      notes: notes ?? this.notes,
      isSynthetic: isSynthetic ?? this.isSynthetic,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toDbMap() {
    return {
      'id': id,
      'client_id': clientId,
      'contact_name': contactName,
      'company': company,
      'email': email,
      'phone': phone,
      'service_niche': serviceNiche,
      'stage': stage.dbValue,
      'estimated_value_minor_units': estimatedValue?.minorUnits,
      'currency': estimatedValue?.currency,
      'next_follow_up_date': nextFollowUpDate != null ? formatCalendarDate(nextFollowUpDate!) : null,
      'notes': notes,
      'is_synthetic': isSynthetic ? 1 : 0,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory Lead.fromDbMap(Map<String, dynamic> map) {
    final minorUnits = map['estimated_value_minor_units'] as int?;
    final currency = map['currency'] as String?;
    final estimatedValue = (minorUnits != null && currency != null)
        ? Money(minorUnits: minorUnits, currency: currency)
        : null;

    final nextFollowUpStr = map['next_follow_up_date'] as String?;
    DateTime? followUp;
    if (nextFollowUpStr != null && nextFollowUpStr.isNotEmpty) {
      try {
        final parsed = DateTime.parse(nextFollowUpStr);
        followUp = toCalendarDate(parsed);
      } catch (_) {
        followUp = null;
      }
    }

    return Lead(
      id: map['id'] as String,
      clientId: map['client_id'] as String?,
      contactName: map['contact_name'] as String,
      company: map['company'] as String?,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      serviceNiche: (map['service_niche'] as String?) ?? 'Other',
      stage: LeadStage.fromString(map['stage'] as String),
      estimatedValue: estimatedValue,
      nextFollowUpDate: followUp,
      notes: map['notes'] as String?,
      isSynthetic: (map['is_synthetic'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
