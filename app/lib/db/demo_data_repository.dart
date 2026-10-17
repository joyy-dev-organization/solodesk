import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import '../models/client.dart';
import '../models/project.dart';
import '../models/money.dart';
import '../models/scope_version.dart';
import '../models/scope_item.dart';
import '../models/invoice.dart';

class OverviewMetrics {
  final int totalClients;
  final int activeProjects;
  final int approvedScopes;
  final int pendingDrafts;
  final int unpaidInvoices;

  const OverviewMetrics({
    required this.totalClients,
    required this.activeProjects,
    required this.approvedScopes,
    required this.pendingDrafts,
    this.unpaidInvoices = 0,
  });
}

abstract class IDemoDataRepository {
  Future<bool> hasSyntheticData();
  Future<void> seedSyntheticData();
  Future<void> purgeSyntheticData();
  Future<OverviewMetrics> getMetrics({bool includeSynthetic = false});
}

class DemoDataRepository implements IDemoDataRepository {
  final Database db;
  final Uuid uuid;

  DemoDataRepository(this.db, {this.uuid = const Uuid()});

  @override
  Future<bool> hasSyntheticData() async {
    final rows = await db.rawQuery('SELECT COUNT(*) as count FROM clients WHERE is_synthetic = 1');
    final count = rows.first['count'] as int? ?? 0;
    return count > 0;
  }

  @override
  Future<void> seedSyntheticData() async {
    if (await hasSyntheticData()) return;

    final batch = db.batch();
    final now = DateTime.now().toUtc();

    // 1. Synthetic Client 1: Amina Musa
    final client1Id = uuid.v4();
    final client1 = Client(
      id: client1Id,
      name: 'Amina Musa',
      initials: 'AM',
      company: 'Musa Brand Lab',
      email: 'amina@example.com',
      notes: 'Brand identity for product launch.',
      isSynthetic: true,
      createdAt: now.subtract(const Duration(days: 5)),
      updatedAt: now.subtract(const Duration(days: 5)),
    );
    batch.insert('clients', client1.toDbMap());

    // Project 1: Brand identity package
    final proj1Id = uuid.v4();
    final proj1 = Project(
      id: proj1Id,
      clientId: client1Id,
      name: 'Brand identity package',
      niche: 'Design & branding',
      budget: const Money(minorUnits: 22000000, currency: 'NGN'), // ₦220,000.00
      status: 'active',
      isSynthetic: true,
      createdAt: now.subtract(const Duration(days: 5)),
      updatedAt: now.subtract(const Duration(days: 5)),
    );
    batch.insert('projects', proj1.toDbMap());

    // Scope v1 (Draft -> Approved)
    final scope1Id = uuid.v4();
    final scope1 = ScopeVersion(
      id: scope1Id,
      projectId: proj1Id,
      versionNumber: 1,
      title: 'Brand Identity Deliverables',
      status: 'draft',
      notes: 'Agreed starting scope with 2 revision rounds',
      isSynthetic: true,
      createdAt: now.subtract(const Duration(days: 5)),
    );
    batch.insert('scope_versions', scope1.toDbMap());

    // Scope Items for scope1
    final scope1Items = [
      'Primary logo',
      'Colour palette',
      'Typography guide',
      '2 revision rounds',
      'Brand PDF',
    ];
    for (int i = 0; i < scope1Items.length; i++) {
      final item = ScopeItem(
        id: uuid.v4(),
        scopeVersionId: scope1Id,
        category: 'included',
        description: scope1Items[i],
        sortOrder: i,
        isSynthetic: true,
      );
      batch.insert('scope_items', item.toDbMap());
    }

    // Mark scope1 approved
    batch.update(
      'scope_versions',
      {
        'status': 'approved',
        'approved_at': now.subtract(const Duration(days: 4)).toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [scope1Id],
    );

    // 2. Synthetic Client 2: Northstar Media
    final client2Id = uuid.v4();
    final client2 = Client(
      id: client2Id,
      name: 'Northstar Media',
      initials: 'NS',
      company: 'Northstar Media Group',
      email: 'editor@northstarmedia.com',
      notes: 'Monthly content and newsletter writing.',
      isSynthetic: true,
      createdAt: now.subtract(const Duration(days: 10)),
      updatedAt: now.subtract(const Duration(days: 10)),
    );
    batch.insert('clients', client2.toDbMap());

    // Project 2: Monthly content package
    final proj2Id = uuid.v4();
    final proj2 = Project(
      id: proj2Id,
      clientId: client2Id,
      name: 'Monthly content package',
      niche: 'Writing & content',
      budget: const Money(minorUnits: 18000000, currency: 'NGN'), // ₦180,000.00
      status: 'active',
      isSynthetic: true,
      createdAt: now.subtract(const Duration(days: 10)),
      updatedAt: now.subtract(const Duration(days: 10)),
    );
    batch.insert('projects', proj2.toDbMap());

    // 3. Synthetic Client 3: FitPath Coaching
    final client3Id = uuid.v4();
    final client3 = Client(
      id: client3Id,
      name: 'FitPath Coaching',
      initials: 'FP',
      company: 'FitPath Online',
      email: 'hello@fitpath.com',
      notes: 'Consulting discovery phase.',
      isSynthetic: true,
      createdAt: now.subtract(const Duration(days: 2)),
      updatedAt: now.subtract(const Duration(days: 2)),
    );
    batch.insert('clients', client3.toDbMap());

    // 4. Synthetic Invoices
    // Invoice 1: Amina Musa, ₦220,000.00, overdue by 5 days
    final inv1 = Invoice(
      id: uuid.v4(),
      clientId: client1Id,
      projectId: proj1Id,
      invoiceNumber: 'INV-2026-001',
      amount: const Money(minorUnits: 22000000, currency: 'NGN'),
      issueDate: now.subtract(const Duration(days: 19)),
      dueDate: now.subtract(const Duration(days: 5)),
      status: InvoiceStatus.unpaid,
      notes: 'Initial 50% deposit for brand identity deliverables.',
      isSynthetic: true,
      createdAt: now.subtract(const Duration(days: 19)),
      updatedAt: now.subtract(const Duration(days: 19)),
    );
    batch.insert('invoices', inv1.toDbMap());

    // Invoice 2: Northstar Media, ₦180,000.00, due in 7 days (upcoming)
    final inv2 = Invoice(
      id: uuid.v4(),
      clientId: client2Id,
      projectId: proj2Id,
      invoiceNumber: 'INV-2026-002',
      amount: const Money(minorUnits: 18000000, currency: 'NGN'),
      issueDate: now.subtract(const Duration(days: 7)),
      dueDate: now.add(const Duration(days: 7)),
      status: InvoiceStatus.unpaid,
      notes: 'Monthly content sprint invoice (net-14 terms).',
      isSynthetic: true,
      createdAt: now.subtract(const Duration(days: 7)),
      updatedAt: now.subtract(const Duration(days: 7)),
    );
    batch.insert('invoices', inv2.toDbMap());

    // Invoice 3: FitPath Coaching, $850.00 USD, paid 3 days ago
    final inv3 = Invoice(
      id: uuid.v4(),
      clientId: client3Id,
      invoiceNumber: 'INV-2026-003',
      amount: const Money(minorUnits: 85000, currency: 'USD'),
      issueDate: now.subtract(const Duration(days: 14)),
      dueDate: now.subtract(const Duration(days: 3)),
      status: InvoiceStatus.paid,
      paidAt: now.subtract(const Duration(days: 3)),
      notes: 'Consulting strategy session.',
      isSynthetic: true,
      createdAt: now.subtract(const Duration(days: 14)),
      updatedAt: now.subtract(const Duration(days: 3)),
    );
    batch.insert('invoices', inv3.toDbMap());

    await batch.commit(noResult: true);
  }

  @override
  Future<void> purgeSyntheticData() async {
    final batch = db.batch();
    batch.delete('invoices', where: 'is_synthetic = 1');
    batch.delete('scope_items', where: 'is_synthetic = 1');
    batch.delete('scope_versions', where: 'is_synthetic = 1');
    batch.delete('projects', where: 'is_synthetic = 1');
    batch.delete('clients', where: 'is_synthetic = 1');
    await batch.commit(noResult: true);
  }

  @override
  Future<OverviewMetrics> getMetrics({bool includeSynthetic = false}) async {
    final synFilter = includeSynthetic ? '' : 'WHERE is_synthetic = 0';
    final synAndFilter = includeSynthetic ? '' : 'AND is_synthetic = 0';

    final clientsRes = await db.rawQuery('SELECT COUNT(*) as count FROM clients $synFilter');
    final projectsRes = await db.rawQuery("SELECT COUNT(*) as count FROM projects WHERE status = 'active' $synAndFilter");
    final scopesRes = await db.rawQuery("SELECT COUNT(*) as count FROM scope_versions WHERE status = 'approved' $synAndFilter");
    final draftsRes = await db.rawQuery("SELECT COUNT(*) as count FROM scope_versions WHERE status = 'draft' $synAndFilter");

    int unpaidInvoices = 0;
    final invoiceTable = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='invoices';");
    if (invoiceTable.isNotEmpty) {
      final invRes = await db.rawQuery("SELECT COUNT(*) as count FROM invoices WHERE status = 'unpaid' $synAndFilter");
      unpaidInvoices = invRes.first['count'] as int? ?? 0;
    }

    return OverviewMetrics(
      totalClients: clientsRes.first['count'] as int? ?? 0,
      activeProjects: projectsRes.first['count'] as int? ?? 0,
      approvedScopes: scopesRes.first['count'] as int? ?? 0,
      pendingDrafts: draftsRes.first['count'] as int? ?? 0,
      unpaidInvoices: unpaidInvoices,
    );
  }
}
