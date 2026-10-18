import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:solodesk/db/database_service.dart';
import 'package:solodesk/db/client_repository.dart';
import 'package:solodesk/db/project_repository.dart';
import 'package:solodesk/db/invoice_repository.dart';
import 'package:solodesk/db/demo_data_repository.dart';
import 'package:solodesk/models/client.dart';
import 'package:solodesk/models/project.dart';
import 'package:solodesk/models/invoice.dart';
import 'package:solodesk/models/money.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Milestone M5: InvoiceRepository & SQLite Schema V2 Tests', () {
    late DatabaseService dbService;
    late ClientRepository clientRepo;
    late ProjectRepository projectRepo;
    late InvoiceRepository invoiceRepo;
    late DemoDataRepository demoDataRepo;

    setUp(() async {
      dbService = await DatabaseService.inMemory();
      clientRepo = ClientRepository(dbService.db);
      projectRepo = ProjectRepository(dbService.db);
      invoiceRepo = InvoiceRepository(dbService.db);
      demoDataRepo = DemoDataRepository(dbService.db);
    });

    tearDown(() async {
      await dbService.close();
    });

    test('Schema V2 Migration: invoices table exists and schema_migrations records v2', () async {
      final migrations = await dbService.db.query('schema_migrations', orderBy: 'version ASC');
      expect(migrations.length, greaterThanOrEqualTo(2));
      expect(migrations.map((m) => m['version']), containsAll([1, 2]));

      // Verify table exists by querying empty list
      final invoices = await invoiceRepo.getInvoices();
      expect(invoices, isEmpty);
    });

    test('CRUD & Foreign Key Cascade: deleting a client deletes its invoices', () async {
      final now = DateTime.now().toUtc();
      final client = Client(
        id: 'client-apex',
        name: 'Apex Design Corp',
        initials: 'AD',
        createdAt: now,
        updatedAt: now,
      );
      await clientRepo.createClient(client);

      final inv = Invoice(
        id: 'inv-101',
        clientId: client.id,
        invoiceNumber: 'INV-101',
        amount: const Money(minorUnits: 150000, currency: 'USD'),
        issueDate: DateTime(2026, 10, 1),
        dueDate: DateTime(2026, 10, 15),
        status: InvoiceStatus.unpaid,
        createdAt: now,
        updatedAt: now,
      );
      await invoiceRepo.createInvoice(inv);

      final fetched = await invoiceRepo.getInvoiceById('inv-101');
      expect(fetched, isNotNull);
      expect(fetched!.invoiceNumber, 'INV-101');
      expect(fetched.amount.minorUnits, 150000);
      expect(fetched.amount.currency, 'USD');

      // Delete client and verify cascade
      await clientRepo.deleteClient(client.id);
      final cascadeCheck = await invoiceRepo.getInvoiceById('inv-101');
      expect(cascadeCheck, isNull);
    });

    test('Mark Paid / Mark Unpaid Toggle: atomically updates status and paid_at timestamp', () async {
      final now = DateTime.now().toUtc();
      final client = Client(
        id: 'client-toggle',
        name: 'Toggle Client',
        initials: 'TC',
        createdAt: now,
        updatedAt: now,
      );
      await clientRepo.createClient(client);

      final inv = Invoice(
        id: 'inv-toggle',
        clientId: client.id,
        invoiceNumber: 'INV-TOGGLE',
        amount: const Money(minorUnits: 5000000, currency: 'NGN'),
        issueDate: DateTime(2026, 10, 1),
        dueDate: DateTime(2026, 10, 10),
        status: InvoiceStatus.unpaid,
        createdAt: now,
        updatedAt: now,
      );
      await invoiceRepo.createInvoice(inv);

      // Mark paid
      final paidTime = DateTime(2026, 10, 12, 14, 30);
      await invoiceRepo.markInvoicePaid('inv-toggle', paidAt: paidTime);

      final paidCheck = await invoiceRepo.getInvoiceById('inv-toggle');
      expect(paidCheck!.status, InvoiceStatus.paid);
      expect(paidCheck.paidAt, isNotNull);

      // Mark unpaid
      await invoiceRepo.markInvoiceUnpaid('inv-toggle');
      final unpaidCheck = await invoiceRepo.getInvoiceById('inv-toggle');
      expect(unpaidCheck!.status, InvoiceStatus.unpaid);
      expect(unpaidCheck.paidAt, isNull);
    });

    test('Status Filtering: correctly filters all, unpaid, overdue, and paid with client joins', () async {
      final now = DateTime(2026, 10, 17);
      final client = Client(
        id: 'client-filter',
        name: 'Filter Client',
        initials: 'FC',
        createdAt: now,
        updatedAt: now,
      );
      await clientRepo.createClient(client);

      // 1 overdue (due 2026-10-10)
      await invoiceRepo.createInvoice(Invoice(
        id: 'inv-overdue',
        clientId: client.id,
        invoiceNumber: 'INV-OVERDUE',
        amount: const Money(minorUnits: 10000, currency: 'USD'),
        issueDate: DateTime(2026, 10, 1),
        dueDate: DateTime(2026, 10, 10),
        status: InvoiceStatus.unpaid,
        createdAt: now,
        updatedAt: now,
      ));

      // 1 upcoming unpaid (due 2026-10-25)
      await invoiceRepo.createInvoice(Invoice(
        id: 'inv-upcoming',
        clientId: client.id,
        invoiceNumber: 'INV-UPCOMING',
        amount: const Money(minorUnits: 20000, currency: 'USD'),
        issueDate: DateTime(2026, 10, 10),
        dueDate: DateTime(2026, 10, 25),
        status: InvoiceStatus.unpaid,
        createdAt: now,
        updatedAt: now,
      ));

      // 1 paid
      await invoiceRepo.createInvoice(Invoice(
        id: 'inv-paid',
        clientId: client.id,
        invoiceNumber: 'INV-PAID',
        amount: const Money(minorUnits: 30000, currency: 'USD'),
        issueDate: DateTime(2026, 9, 1),
        dueDate: DateTime(2026, 9, 15),
        status: InvoiceStatus.paid,
        paidAt: DateTime(2026, 9, 14),
        createdAt: now,
        updatedAt: now,
      ));

      // Test 'all'
      final all = await invoiceRepo.getInvoicesWithClient(referenceDate: now);
      expect(all.length, 3);
      expect(all.first.clientName, 'Filter Client');

      // Test 'unpaid'
      final unpaid = await invoiceRepo.getInvoicesWithClient(statusFilter: 'unpaid', referenceDate: now);
      expect(unpaid.length, 2);

      // Test 'overdue'
      final overdue = await invoiceRepo.getInvoicesWithClient(statusFilter: 'overdue', referenceDate: now);
      expect(overdue.length, 1);
      expect(overdue.first.invoice.invoiceNumber, 'INV-OVERDUE');

      // Test 'paid'
      final paid = await invoiceRepo.getInvoicesWithClient(statusFilter: 'paid', referenceDate: now);
      expect(paid.length, 1);
      expect(paid.first.invoice.invoiceNumber, 'INV-PAID');
    });

    test('Synthetic Invoices Seeding and Purge', () async {
      await demoDataRepo.seedSyntheticData();
      final syntheticInvoices = await invoiceRepo.getInvoices(includeSynthetic: true);
      expect(syntheticInvoices.length, 4); // 4 seeded synthetic invoices (including due today)

      await demoDataRepo.purgeSyntheticData();
      final remaining = await invoiceRepo.getInvoices(includeSynthetic: true);
      expect(remaining, isEmpty);
    });

    test('Project Deletion: ON DELETE SET NULL retains invoice with null projectId', () async {
      final now = DateTime.now().toUtc();
      final client = Client(
        id: 'client-proj-del',
        name: 'Project Client',
        initials: 'PC',
        createdAt: now,
        updatedAt: now,
      );
      await clientRepo.createClient(client);

      final project = Project(
        id: 'proj-del-1',
        clientId: client.id,
        name: 'Website Redesign',
        niche: 'Design & branding',
        budget: const Money(minorUnits: 100000, currency: 'USD'),
        status: 'active',
        createdAt: now,
        updatedAt: now,
      );
      await projectRepo.createProject(project);

      final inv = Invoice(
        id: 'inv-proj-del',
        clientId: client.id,
        projectId: project.id,
        invoiceNumber: 'INV-PROJ-DEL',
        amount: const Money(minorUnits: 50000, currency: 'USD'),
        issueDate: DateTime(2026, 10, 1),
        dueDate: DateTime(2026, 10, 15),
        status: InvoiceStatus.unpaid,
        createdAt: now,
        updatedAt: now,
      );
      await invoiceRepo.createInvoice(inv);

      final before = await invoiceRepo.getInvoiceById('inv-proj-del');
      expect(before?.projectId, 'proj-del-1');

      // Delete project
      await projectRepo.deleteProject('proj-del-1');

      // Invoice survives, with projectId set to null
      final after = await invoiceRepo.getInvoiceById('inv-proj-del');
      expect(after, isNotNull);
      expect(after?.projectId, isNull);
    });

    test('Database schema CHECK constraint rejects negative amount_minor_units', () async {
      final now = DateTime.now().toUtc();
      final client = Client(
        id: 'client-neg-check',
        name: 'Negative Check Client',
        initials: 'NC',
        createdAt: now,
        updatedAt: now,
      );
      await clientRepo.createClient(client);

      expect(() async {
        await dbService.db.rawInsert('''
          INSERT INTO invoices (id, client_id, invoice_number, amount_minor_units, currency, issue_date, due_date, status, created_at, updated_at)
          VALUES ('inv-neg', 'client-neg-check', 'INV-NEG', -500, 'USD', '2026-10-01', '2026-10-15', 'unpaid', ?, ?)
        ''', [now.toIso8601String(), now.toIso8601String()]);
      }, throwsA(anything));
    });
  });
}
