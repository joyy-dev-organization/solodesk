import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:solodesk/db/database_service.dart';
import 'package:solodesk/db/client_repository.dart';
import 'package:solodesk/db/project_repository.dart';
import 'package:solodesk/db/scope_repository.dart';
import 'package:solodesk/db/invoice_repository.dart';
import 'package:solodesk/db/lead_repository.dart';
import 'package:solodesk/models/client.dart';
import 'package:solodesk/models/project.dart';
import 'package:solodesk/models/money.dart';
import 'package:solodesk/models/scope_item.dart';
import 'package:solodesk/models/invoice.dart';
import 'package:solodesk/models/lead.dart';
import 'package:solodesk/db/service_plan_repository.dart';
import 'package:solodesk/models/service_plan.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Database schema upgrade from v1 to v2 preserves data and applies new migrations', () async {
    final tempDir = await Directory.systemTemp.createTemp('solodesk_upgrade_test_');
    final dbFile = p.join(tempDir.path, 'upgrade_test.db');

    try {
      // 1. Initialize database at Schema Version 1 (M2 baseline)
      {
        final dbV1 = await DatabaseService.openPath(dbFile, version: 1);
        final clientRepo = ClientRepository(dbV1.db);
        final projectRepo = ProjectRepository(dbV1.db);
        final scopeRepo = ScopeRepository(dbV1.db);

        // Verify user_version is 1
        final userVerRes = await dbV1.db.rawQuery('PRAGMA user_version;');
        expect(userVerRes.first.values.first, equals(1));

        // Verify invoices table does NOT exist in V1
        final tablesV1 = await dbV1.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='invoices';",
        );
        expect(tablesV1, isEmpty);

        // Insert V1 data
        final now = DateTime.now().toUtc();
        await clientRepo.createClient(Client(
          id: 'c-upg-1',
          name: 'Upstream Media',
          initials: 'UM',
          company: 'Upstream Corp',
          email: 'hello@upstream.com',
          createdAt: now,
          updatedAt: now,
        ));

        await projectRepo.createProject(Project(
          id: 'p-upg-1',
          clientId: 'c-upg-1',
          name: 'Corporate Branding',
          niche: 'Design & branding',
          budget: const Money(minorUnits: 30000000, currency: 'NGN'),
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ));

        final draft = await scopeRepo.createDraft(
          projectId: 'p-upg-1',
          title: 'Brand Guide Scope',
          items: [
            const ScopeItem(
              id: 'item-upg-1',
              scopeVersionId: '',
              category: 'included',
              description: 'Brand styleguide PDF',
            ),
          ],
        );
        await scopeRepo.approveVersion(draft.version.id);

        // Close V1 database
        await dbV1.close();
      }

      // 2. Open database at Schema Version 2 (triggers onUpgrade from 1 to 2)
      {
        final dbV2 = await DatabaseService.openPath(dbFile, version: 2);
        final clientRepo = ClientRepository(dbV2.db);
        final projectRepo = ProjectRepository(dbV2.db);
        final scopeRepo = ScopeRepository(dbV2.db);

        // Verify user_version is now 2
        final userVerRes = await dbV2.db.rawQuery('PRAGMA user_version;');
        expect(userVerRes.first.values.first, equals(2));

        // Verify invoices table now EXISTS in V2
        final tablesV2 = await dbV2.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='invoices';",
        );
        expect(tablesV2, isNotEmpty);

        // Verify schema_migrations audit log records both v1 and v2
        final migrationRows = await dbV2.db.query(
          'schema_migrations',
          orderBy: 'version ASC',
        );
        expect(migrationRows.length, equals(2));
        expect(migrationRows[0]['version'], equals(1));
        expect(migrationRows[1]['version'], equals(2));
        expect(migrationRows[1]['description'], contains('M5 schema: invoices table'));

        // Verify all V1 data survived the upgrade 100% intact
        final client = await clientRepo.getClientById('c-upg-1');
        expect(client, isNotNull);
        expect(client!.name, equals('Upstream Media'));

        final project = await projectRepo.getProjectById('p-upg-1');
        expect(project, isNotNull);
        expect(project!.name, equals('Corporate Branding'));
        expect(project.budget.minorUnits, equals(30000000));

        final latestApproved = await scopeRepo.getLatestApprovedVersion('p-upg-1');
        expect(latestApproved, isNotNull);
        expect(latestApproved!.version.isApproved, isTrue);
        expect(latestApproved.items.length, equals(1));
        expect(latestApproved.items.first.description, equals('Brand styleguide PDF'));

        // Close V2 database
        await dbV2.close();
      }
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test('Database schema upgrade from v2 to v3 preserves invoices and creates leads table', () async {
    final tempDir = await Directory.systemTemp.createTemp('solodesk_upgrade_v3_test_');
    final dbFile = p.join(tempDir.path, 'upgrade_v3_test.db');

    try {
      // 1. Initialize database at Schema Version 2 (M5 baseline)
      {
        final dbV2 = await DatabaseService.openPath(dbFile, version: 2);
        final clientRepo = ClientRepository(dbV2.db);
        final projectRepo = ProjectRepository(dbV2.db);
        final invoiceRepo = InvoiceRepository(dbV2.db);

        // Verify user_version is 2
        final userVerRes = await dbV2.db.rawQuery('PRAGMA user_version;');
        expect(userVerRes.first.values.first, equals(2));

        // Verify leads table does NOT exist in V2
        final tablesV2 = await dbV2.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='leads';",
        );
        expect(tablesV2, isEmpty);

        // Insert V2 data
        final now = DateTime.now().toUtc();
        await clientRepo.createClient(Client(
          id: 'c-v2-1',
          name: 'V2 Media Client',
          initials: 'VM',
          createdAt: now,
          updatedAt: now,
        ));

        await projectRepo.createProject(Project(
          id: 'p-v2-1',
          clientId: 'c-v2-1',
          name: 'V2 Project',
          niche: 'Writing & content',
          budget: const Money(minorUnits: 15000000, currency: 'NGN'),
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ));

        await invoiceRepo.createInvoice(Invoice(
          id: 'inv-v2-1',
          clientId: 'c-v2-1',
          projectId: 'p-v2-1',
          invoiceNumber: 'INV-2026-V2',
          amount: const Money(minorUnits: 15000000, currency: 'NGN'),
          issueDate: now,
          dueDate: now.add(const Duration(days: 7)),
          status: InvoiceStatus.unpaid,
          createdAt: now,
          updatedAt: now,
        ));

        // Close V2 database
        await dbV2.close();
      }

      // 2. Open database at Schema Version 3 (triggers onUpgrade from 2 to 3)
      {
        final dbV3 = await DatabaseService.openPath(dbFile, version: 3);
        final clientRepo = ClientRepository(dbV3.db);
        final invoiceRepo = InvoiceRepository(dbV3.db);
        final leadRepo = LeadRepository(dbV3.db);

        // Verify user_version is now 3
        final userVerRes = await dbV3.db.rawQuery('PRAGMA user_version;');
        expect(userVerRes.first.values.first, equals(3));

        // Verify leads table now EXISTS in V3
        final tablesV3 = await dbV3.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='leads';",
        );
        expect(tablesV3, isNotEmpty);

        // Verify schema_migrations audit log records v1, v2, and v3
        final migrationRows = await dbV3.db.query(
          'schema_migrations',
          orderBy: 'version ASC',
        );
        expect(migrationRows.length, equals(3));
        expect(migrationRows[2]['version'], equals(3));
        expect(migrationRows[2]['description'], contains('leads table'));

        // Verify V2 invoice survived
        final invoice = await invoiceRepo.getInvoiceById('inv-v2-1');
        expect(invoice, isNotNull);
        expect(invoice!.invoiceNumber, equals('INV-2026-V2'));
        expect(invoice.amount.minorUnits, equals(15000000));

        // Verify V2 client survived
        final client = await clientRepo.getClientById('c-v2-1');
        expect(client, isNotNull);
        expect(client!.name, equals('V2 Media Client'));

        // Verify creating a lead in V3 works
        final now = DateTime.now().toUtc();
        await leadRepo.createLead(Lead(
          id: 'lead-v3-1',
          clientId: 'c-v2-1',
          contactName: 'V3 Lead Contact',
          serviceNiche: 'Writing & content',
          stage: LeadStage.discovery,
          estimatedValue: const Money(minorUnits: 20000000, currency: 'NGN'),
          nextFollowUpDate: DateTime(2026, 10, 25),
          createdAt: now,
          updatedAt: now,
        ));

        final lead = await leadRepo.getLeadById('lead-v3-1');
        expect(lead, isNotNull);
        expect(lead!.contactName, equals('V3 Lead Contact'));
        expect(lead.stage, equals(LeadStage.discovery));

        await dbV3.close();
      }
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test('Database schema upgrade from v3 to v4 preserves leads and creates service_plans table', () async {
    final tempDir = await Directory.systemTemp.createTemp('solodesk_upgrade_v4_test_');
    final dbFile = p.join(tempDir.path, 'upgrade_v4_test.db');

    try {
      // 1. Initialize database at Schema Version 3 (M6 baseline)
      {
        final dbV3 = await DatabaseService.openPath(dbFile, version: 3);
        final clientRepo = ClientRepository(dbV3.db);
        final leadRepo = LeadRepository(dbV3.db);

        // Verify user_version is 3
        final userVerRes = await dbV3.db.rawQuery('PRAGMA user_version;');
        expect(userVerRes.first.values.first, equals(3));

        // Verify service_plans table does NOT exist in V3
        final tablesV3 = await dbV3.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='service_plans';",
        );
        expect(tablesV3, isEmpty);

        // Insert V3 data
        final now = DateTime.now().toUtc();
        await clientRepo.createClient(Client(
          id: 'c-v3-1',
          name: 'V3 Retainer Client',
          initials: 'RC',
          company: 'Retainer Co',
          createdAt: now,
          updatedAt: now,
        ));

        await leadRepo.createLead(Lead(
          id: 'lead-v3-survives',
          clientId: 'c-v3-1',
          contactName: 'Retainer Contact',
          serviceNiche: 'Design & branding',
          stage: LeadStage.proposalSent,
          estimatedValue: const Money(minorUnits: 50000000, currency: 'NGN'),
          createdAt: now,
          updatedAt: now,
        ));

        // Close V3 database
        await dbV3.close();
      }

      // 2. Open database at Schema Version 4 (triggers onUpgrade from 3 to 4)
      {
        final dbV4 = await DatabaseService.openPath(dbFile, version: 4);
        final clientRepo = ClientRepository(dbV4.db);
        final leadRepo = LeadRepository(dbV4.db);
        final planRepo = ServicePlanRepository(dbV4.db);

        // Verify user_version is now 4
        final userVerRes = await dbV4.db.rawQuery('PRAGMA user_version;');
        expect(userVerRes.first.values.first, equals(4));

        // Verify service_plans table now EXISTS in V4
        final tablesV4 = await dbV4.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='service_plans';",
        );
        expect(tablesV4, isNotEmpty);

        // Verify schema_migrations audit log records v1, v2, v3, and v4
        final migrationRows = await dbV4.db.query(
          'schema_migrations',
          orderBy: 'version ASC',
        );
        expect(migrationRows.length, equals(4));
        expect(migrationRows[3]['version'], equals(4));
        expect(migrationRows[3]['description'], contains('service_plans table'));

        // Verify V3 lead survived intact
        final survivingLead = await leadRepo.getLeadById('lead-v3-survives');
        expect(survivingLead, isNotNull);
        expect(survivingLead!.contactName, equals('Retainer Contact'));
        expect(survivingLead.estimatedValue!.minorUnits, equals(50000000));

        // Verify V3 client survived intact
        final survivingClient = await clientRepo.getClientById('c-v3-1');
        expect(survivingClient, isNotNull);
        expect(survivingClient!.name, equals('V3 Retainer Client'));

        // Verify creating and querying a service_plan in V4 works
        final now = DateTime.now().toUtc();
        await planRepo.createPlan(ServicePlan(
          id: 'plan-v4-1',
          clientId: 'c-v3-1',
          title: 'Brand retainer V4',
          serviceNiche: 'Design & branding',
          cadence: PlanCadence.monthly,
          price: const Money(minorUnits: 50000000, currency: 'NGN'),
          deliverables: const ['Quarterly Brand Refresh', 'Monthly Assets'],
          exclusions: const ['Video Shooting'],
          revisionLimit: '2 rounds',
          status: PlanStatus.active,
          createdAt: now,
          updatedAt: now,
        ));

        final createdPlan = await planRepo.getPlanById('plan-v4-1');
        expect(createdPlan, isNotNull);
        expect(createdPlan!.title, equals('Brand retainer V4'));
        expect(createdPlan.deliverables.length, equals(2));
        expect(createdPlan.exclusions.length, equals(1));
        expect(createdPlan.priceMinorUnits, equals(50000000));

        await dbV4.close();
      }
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });
}
