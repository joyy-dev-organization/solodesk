import 'package:flutter/foundation.dart';
import 'money.dart';

enum InvoiceStatus {
  draft,
  unpaid,
  paid,
  cancelled;

  static InvoiceStatus fromString(String val) {
    return InvoiceStatus.values.firstWhere(
      (e) => e.name == val.toLowerCase().trim(),
      orElse: () => InvoiceStatus.unpaid,
    );
  }
}

enum InvoiceDisplayStatus {
  paid,
  overdue,
  dueToday,
  upcoming,
  draft,
  cancelled,
}

@immutable
class Invoice {
  final String id;
  final String clientId;
  final String? projectId;
  final String invoiceNumber;
  final Money amount;
  final DateTime issueDate; // Calendar date (year, month, day)
  final DateTime dueDate;   // Calendar date (year, month, day)
  final InvoiceStatus status;
  final DateTime? paidAt;
  final String? notes;
  final bool isSynthetic;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Invoice({
    required this.id,
    required this.clientId,
    this.projectId,
    required this.invoiceNumber,
    required this.amount,
    required this.issueDate,
    required this.dueDate,
    required this.status,
    this.paidAt,
    this.notes,
    this.isSynthetic = false,
    required this.createdAt,
    required this.updatedAt,
  });

  static DateTime toCalendarDate(DateTime dt) {
    final local = dt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  bool isOverdueAt(DateTime referenceDate) {
    if (status == InvoiceStatus.paid || status == InvoiceStatus.cancelled) return false;
    final ref = toCalendarDate(referenceDate);
    final due = toCalendarDate(dueDate);
    return due.isBefore(ref);
  }

  bool isDueToday(DateTime referenceDate) {
    if (status == InvoiceStatus.paid || status == InvoiceStatus.cancelled) return false;
    final ref = toCalendarDate(referenceDate);
    final due = toCalendarDate(dueDate);
    return due.year == ref.year && due.month == ref.month && due.day == ref.day;
  }

  int daysOverdueAt(DateTime referenceDate) {
    if (!isOverdueAt(referenceDate)) return 0;
    final ref = toCalendarDate(referenceDate);
    final due = toCalendarDate(dueDate);
    return ref.difference(due).inDays;
  }

  InvoiceDisplayStatus displayStatusAt(DateTime referenceDate) {
    if (status == InvoiceStatus.paid) return InvoiceDisplayStatus.paid;
    if (status == InvoiceStatus.cancelled) return InvoiceDisplayStatus.cancelled;
    if (status == InvoiceStatus.draft) return InvoiceDisplayStatus.draft;
    if (isDueToday(referenceDate)) return InvoiceDisplayStatus.dueToday;
    if (isOverdueAt(referenceDate)) return InvoiceDisplayStatus.overdue;
    return InvoiceDisplayStatus.upcoming;
  }

  Invoice copyWith({
    String? clientId,
    String? projectId,
    String? invoiceNumber,
    Money? amount,
    DateTime? issueDate,
    DateTime? dueDate,
    InvoiceStatus? status,
    DateTime? paidAt,
    String? notes,
    bool? isSynthetic,
    DateTime? updatedAt,
  }) =>
      Invoice(
        id: id,
        clientId: clientId ?? this.clientId,
        projectId: projectId ?? this.projectId,
        invoiceNumber: invoiceNumber ?? this.invoiceNumber,
        amount: amount ?? this.amount,
        issueDate: issueDate ?? this.issueDate,
        dueDate: dueDate ?? this.dueDate,
        status: status ?? this.status,
        paidAt: paidAt ?? this.paidAt,
        notes: notes ?? this.notes,
        isSynthetic: isSynthetic ?? this.isSynthetic,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
      );

  static String _formatCalendarDate(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'client_id': clientId,
        'project_id': projectId,
        'invoice_number': invoiceNumber,
        'amount_minor_units': amount.minorUnits,
        'currency': amount.currency,
        'issue_date': _formatCalendarDate(issueDate),
        'due_date': _formatCalendarDate(dueDate),
        'status': status.name,
        'paid_at': paidAt?.toUtc().toIso8601String(),
        'notes': notes,
        'is_synthetic': isSynthetic ? 1 : 0,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Invoice.fromDbMap(Map<String, dynamic> map) => Invoice(
        id: map['id'] as String,
        clientId: map['client_id'] as String,
        projectId: map['project_id'] as String?,
        invoiceNumber: map['invoice_number'] as String,
        amount: Money(
          minorUnits: map['amount_minor_units'] as int,
          currency: map['currency'] as String,
        ),
        issueDate: DateTime.parse(map['issue_date'] as String),
        dueDate: DateTime.parse(map['due_date'] as String),
        status: InvoiceStatus.fromString(map['status'] as String),
        paidAt: map['paid_at'] != null ? DateTime.parse(map['paid_at'] as String) : null,
        notes: map['notes'] as String?,
        isSynthetic: (map['is_synthetic'] as int) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}

@immutable
class InvoiceWithClient {
  final Invoice invoice;
  final String clientName;
  final String clientInitials;
  final String? projectName;

  const InvoiceWithClient({
    required this.invoice,
    required this.clientName,
    required this.clientInitials,
    this.projectName,
  });
}
