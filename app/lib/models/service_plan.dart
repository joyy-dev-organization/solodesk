import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'money.dart';

enum PlanCadence {
  weekly('weekly', 'Weekly', 52.0 / 12.0),
  biweekly('biweekly', 'Bi-weekly', 26.0 / 12.0),
  monthly('monthly', 'Monthly', 1.0),
  quarterly('quarterly', 'Quarterly', 1.0 / 3.0),
  annual('annual', 'Annual', 1.0 / 12.0);

  final String dbValue;
  final String displayName;
  final double monthlyFactor;

  const PlanCadence(this.dbValue, this.displayName, this.monthlyFactor);

  double get monthlyMultiplier => monthlyFactor;
  static PlanCadence fromDb(String val) => fromString(val);

  static PlanCadence fromString(String val) {
    final normalized = val.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    switch (normalized) {
      case 'weekly':
        return PlanCadence.weekly;
      case 'biweekly':
      case 'bi_weekly':
        return PlanCadence.biweekly;
      case 'monthly':
        return PlanCadence.monthly;
      case 'quarterly':
        return PlanCadence.quarterly;
      case 'annual':
      case 'annually':
      case 'yearly':
        return PlanCadence.annual;
      default:
        return PlanCadence.monthly;
    }
  }
}

enum PlanStatus {
  draft('draft', 'Draft'),
  active('active', 'Active'),
  paused('paused', 'Paused'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  final String dbValue;
  final String displayName;

  const PlanStatus(this.dbValue, this.displayName);

  static PlanStatus fromDb(String val) => fromString(val);

  static PlanStatus fromString(String val) {
    final normalized = val.trim().toLowerCase();
    switch (normalized) {
      case 'draft':
        return PlanStatus.draft;
      case 'active':
        return PlanStatus.active;
      case 'paused':
        return PlanStatus.paused;
      case 'completed':
        return PlanStatus.completed;
      case 'cancelled':
      case 'canceled':
        return PlanStatus.cancelled;
      default:
        return PlanStatus.draft;
    }
  }

  bool get isActive => this == PlanStatus.active;
  bool get isPaused => this == PlanStatus.paused;
  bool get isTerminated => this == PlanStatus.completed || this == PlanStatus.cancelled;
}

@immutable
class ServicePlan {
  final String id;
  final String? clientId;
  final String title;
  final String serviceNiche;
  final PlanCadence cadence;
  final Money price;
  final PlanStatus status;
  final List<String> deliverables;
  final List<String> exclusions;
  final String revisionLimit;
  final DateTime? startDate;   // Calendar date (year, month, day)
  final DateTime? renewalDate; // Calendar date (year, month, day)
  final String? notes;
  final bool isSynthetic;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ServicePlan({
    required this.id,
    this.clientId,
    required this.title,
    required this.serviceNiche,
    required this.cadence,
    required this.price,
    required this.status,
    this.deliverables = const [],
    this.exclusions = const [],
    this.revisionLimit = '2 rounds per deliverable',
    this.startDate,
    this.renewalDate,
    this.notes,
    this.isSynthetic = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Normalizes date to calendar date in local timezone (avoids UTC rollover shifts)
  static DateTime toCalendarDate(DateTime dt) {
    final local = dt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// Formats date to YYYY-MM-DD
  static String formatCalendarDate(DateTime dt) {
    final d = toCalendarDate(dt);
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  bool isRenewalOverdue([DateTime? referenceDate]) {
    if (renewalDate == null || !status.isActive) return false;
    final ref = toCalendarDate(referenceDate ?? DateTime.now());
    final renew = toCalendarDate(renewalDate!);
    return renew.isBefore(ref);
  }

  bool isRenewalDueToday([DateTime? referenceDate]) {
    if (renewalDate == null || !status.isActive) return false;
    final ref = toCalendarDate(referenceDate ?? DateTime.now());
    final renew = toCalendarDate(renewalDate!);
    return renew.year == ref.year && renew.month == ref.month && renew.day == ref.day;
  }

  int daysUntilRenewal([DateTime? referenceDate]) {
    if (renewalDate == null) return 0;
    final ref = toCalendarDate(referenceDate ?? DateTime.now());
    final renew = toCalendarDate(renewalDate!);
    return renew.difference(ref).inDays;
  }

  int get priceMinorUnits => price.minorUnits;
  String get currency => price.currency;
  String get revisionLimits => revisionLimit;
  int get deliverablesCount => deliverables.length;
  int get exclusionsCount => exclusions.length;
  String get formattedPrice => price.formatted;
  int get monthlyEquivalentMinorUnits => (price.minorUnits * cadence.monthlyMultiplier).round();
  Money get monthlyEquivalentMoney => Money(minorUnits: monthlyEquivalentMinorUnits, currency: price.currency);

  Map<String, dynamic> toMap() => toDbMap();
  static ServicePlan fromMap(Map<String, dynamic> map) => ServicePlan.fromDbMap(map);

  ServicePlan copyWith({
    String? clientId,
    bool clearClientId = false,
    String? title,
    String? serviceNiche,
    PlanCadence? cadence,
    Money? price,
    PlanStatus? status,
    List<String>? deliverables,
    List<String>? exclusions,
    String? revisionLimit,
    DateTime? startDate,
    bool clearStartDate = false,
    DateTime? renewalDate,
    bool clearRenewalDate = false,
    String? notes,
    bool? isSynthetic,
    DateTime? updatedAt,
  }) {
    return ServicePlan(
      id: id,
      clientId: clearClientId ? null : (clientId ?? this.clientId),
      title: title ?? this.title,
      serviceNiche: serviceNiche ?? this.serviceNiche,
      cadence: cadence ?? this.cadence,
      price: price ?? this.price,
      status: status ?? this.status,
      deliverables: deliverables ?? this.deliverables,
      exclusions: exclusions ?? this.exclusions,
      revisionLimit: revisionLimit ?? this.revisionLimit,
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      renewalDate: clearRenewalDate ? null : (renewalDate ?? this.renewalDate),
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
      'title': title,
      'service_niche': serviceNiche,
      'cadence': cadence.dbValue,
      'price_minor_units': price.minorUnits,
      'currency': price.currency,
      'status': status.dbValue,
      'deliverables_json': jsonEncode(deliverables),
      'exclusions_json': jsonEncode(exclusions),
      'revision_limit': revisionLimit,
      'start_date': startDate != null ? formatCalendarDate(startDate!) : null,
      'renewal_date': renewalDate != null ? formatCalendarDate(renewalDate!) : null,
      'notes': notes,
      'is_synthetic': isSynthetic ? 1 : 0,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory ServicePlan.fromDbMap(Map<String, dynamic> map) {
    List<String> deliverables = [];
    if (map['deliverables_json'] != null) {
      try {
        final decoded = jsonDecode(map['deliverables_json'] as String);
        if (decoded is List) deliverables = decoded.map((e) => e.toString()).toList();
      } catch (_) {}
    }

    List<String> exclusions = [];
    if (map['exclusions_json'] != null) {
      try {
        final decoded = jsonDecode(map['exclusions_json'] as String);
        if (decoded is List) exclusions = decoded.map((e) => e.toString()).toList();
      } catch (_) {}
    }

    DateTime? startDate;
    final startStr = map['start_date'] as String?;
    if (startStr != null && startStr.isNotEmpty) {
      try {
        startDate = toCalendarDate(DateTime.parse(startStr));
      } catch (_) {}
    }

    DateTime? renewalDate;
    final renewStr = map['renewal_date'] as String?;
    if (renewStr != null && renewStr.isNotEmpty) {
      try {
        renewalDate = toCalendarDate(DateTime.parse(renewStr));
      } catch (_) {}
    }

    return ServicePlan(
      id: map['id'] as String,
      clientId: map['client_id'] as String?,
      title: map['title'] as String,
      serviceNiche: (map['service_niche'] as String?) ?? 'General',
      cadence: PlanCadence.fromString(map['cadence'] as String),
      price: Money(
        minorUnits: map['price_minor_units'] as int,
        currency: map['currency'] as String,
      ),
      status: PlanStatus.fromString(map['status'] as String),
      deliverables: deliverables,
      exclusions: exclusions,
      revisionLimit: (map['revision_limit'] as String?) ?? '2 rounds per deliverable',
      startDate: startDate,
      renewalDate: renewalDate,
      notes: map['notes'] as String?,
      isSynthetic: (map['is_synthetic'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

@immutable
class ServicePlanWithClient {
  final ServicePlan plan;
  final String? clientName;
  final String? clientInitials;
  final String? clientCompany;

  const ServicePlanWithClient({
    required this.plan,
    this.clientName,
    this.clientInitials,
    this.clientCompany,
  });
}
