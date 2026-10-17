import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:solodesk/db/database_service.dart';
import 'package:solodesk/db/client_repository.dart';
import 'package:solodesk/db/project_repository.dart';
import 'package:solodesk/db/scope_repository.dart';
import 'package:solodesk/models/client.dart';
import 'package:solodesk/models/project.dart';
import 'package:solodesk/models/money.dart';
import 'package:solodesk/models/scope_item.dart';

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
}
