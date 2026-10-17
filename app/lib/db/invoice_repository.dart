import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/invoice.dart';

abstract class IInvoiceRepository {
  Future<List<Invoice>> getInvoices({
    String? clientId,
    InvoiceStatus? status,
    bool includeSynthetic = true,
  });

  Future<List<InvoiceWithClient>> getInvoicesWithClient({
    String? clientId,
    String? statusFilter, // 'all' | 'unpaid' | 'overdue' | 'paid'
    bool includeSynthetic = true,
    DateTime? referenceDate,
  });

  Future<Invoice?> getInvoiceById(String id);
  Future<void> createInvoice(Invoice invoice);
  Future<void> updateInvoice(Invoice invoice);
  Future<void> deleteInvoice(String id);
  Future<void> markInvoicePaid(String id, {DateTime? paidAt});
  Future<void> markInvoiceUnpaid(String id);
}

class InvoiceRepository implements IInvoiceRepository {
  final Database db;

  InvoiceRepository(this.db);

  @override
  Future<List<Invoice>> getInvoices({
    String? clientId,
    InvoiceStatus? status,
    bool includeSynthetic = true,
  }) async {
    final where = <String>[];
    final args = <dynamic>[];

    if (clientId != null) {
      where.add('client_id = ?');
      args.add(clientId);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status.name);
    }
    if (!includeSynthetic) {
      where.add('is_synthetic = 0');
    }

    final rows = await db.query(
      'invoices',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'due_date ASC, created_at DESC',
    );
    return rows.map(Invoice.fromDbMap).toList();
  }

  @override
  Future<List<InvoiceWithClient>> getInvoicesWithClient({
    String? clientId,
    String? statusFilter,
    bool includeSynthetic = true,
    DateTime? referenceDate,
  }) async {
    final ref = referenceDate ?? DateTime.now();
    final todayStr = '${ref.year.toString().padLeft(4, '0')}-${ref.month.toString().padLeft(2, '0')}-${ref.day.toString().padLeft(2, '0')}';

    final where = <String>[];
    final args = <dynamic>[];

    if (!includeSynthetic) {
      where.add('i.is_synthetic = 0');
    }
    if (clientId != null) {
      where.add('i.client_id = ?');
      args.add(clientId);
    }

    if (statusFilter == 'paid') {
      where.add("i.status = 'paid'");
    } else if (statusFilter == 'unpaid') {
      where.add("i.status = 'unpaid'");
    } else if (statusFilter == 'overdue') {
      where.add("i.status = 'unpaid' AND i.due_date < ?");
      args.add(todayStr);
    }

    final whereClause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    final sql = '''
      SELECT 
        i.*,
        c.name AS client_name,
        c.initials AS client_initials,
        p.name AS project_name
      FROM invoices i
      JOIN clients c ON i.client_id = c.id
      LEFT JOIN projects p ON i.project_id = p.id
      $whereClause
      ORDER BY i.due_date ASC, i.created_at DESC;
    ''';

    final rows = await db.rawQuery(sql, args);
    return rows.map((r) {
      return InvoiceWithClient(
        invoice: Invoice.fromDbMap(r),
        clientName: r['client_name'] as String,
        clientInitials: r['client_initials'] as String,
        projectName: r['project_name'] as String?,
      );
    }).toList();
  }

  @override
  Future<Invoice?> getInvoiceById(String id) async {
    final rows = await db.query('invoices', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Invoice.fromDbMap(rows.first);
  }

  @override
  Future<void> createInvoice(Invoice invoice) async {
    await db.insert('invoices', invoice.toDbMap());
  }

  @override
  Future<void> updateInvoice(Invoice invoice) async {
    await db.update(
      'invoices',
      invoice.toDbMap(),
      where: 'id = ?',
      whereArgs: [invoice.id],
    );
  }

  @override
  Future<void> deleteInvoice(String id) async {
    await db.delete('invoices', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> markInvoicePaid(String id, {DateTime? paidAt}) async {
    final nowIso = (paidAt ?? DateTime.now()).toUtc().toIso8601String();
    await db.update(
      'invoices',
      {
        'status': InvoiceStatus.paid.name,
        'paid_at': nowIso,
        'updated_at': nowIso,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> markInvoiceUnpaid(String id) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'invoices',
      {
        'status': InvoiceStatus.unpaid.name,
        'paid_at': null,
        'updated_at': nowIso,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
