import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:solodesk/db/database_service.dart';
import 'package:solodesk/db/client_repository.dart';
import 'package:solodesk/db/project_repository.dart';
import 'package:solodesk/db/scope_repository.dart';
import 'package:solodesk/db/demo_data_repository.dart';
import 'package:solodesk/models/client.dart';
import 'package:solodesk/models/project.dart';
import 'package:solodesk/models/money.dart';
import 'package:solodesk/models/scope_item.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Synthetic Demo Data Toggle & Trigger Upgrade Tests', () {
    test('seed and purge synthetic demo data cleanly without affecting real approved records', () async {
      final dbService = await DatabaseService.inMemory();
      final clientRepo = ClientRepository(dbService.db);
      final projectRepo = ProjectRepository(dbService.db);
      final scopeRepo = ScopeRepository(dbService.db);
      final demoRepo = DemoDataRepository(dbService.db);

      // 1. Create a real user client, project, and approved scope
      final now = DateTime.now().toUtc();
      await clientRepo.createClient(Client(
        id: 'real-client-1',
        name: 'Real Client Co',
        initials: 'RC',
        company: 'Real Client Inc',
        isSynthetic: false,
        createdAt: now,
        updatedAt: now,
      ));

      await projectRepo.createProject(Project(
        id: 'real-proj-1',
        clientId: 'real-client-1',
        name: 'Real Project',
        niche: 'Design & branding',
        budget: const Money(minorUnits: 5000000, currency: 'USD'),
        status: 'active',
        isSynthetic: false,
        createdAt: now,
        updatedAt: now,
      ));

      final realDraft = await scopeRepo.createDraft(
        projectId: 'real-proj-1',
        title: 'Real Approved Scope',
        items: [
          const ScopeItem(
            id: 'real-item-1',
            scopeVersionId: '',
            category: 'included',
            description: 'Real Deliverable 1',
            isSynthetic: false,
          ),
        ],
      );
      await scopeRepo.approveVersion(realDraft.version.id);

      // Verify no synthetic data initially
      expect(await demoRepo.hasSyntheticData(), isFalse);

      // 2. Toggle ON: Seed synthetic demo data
      await demoRepo.seedSyntheticData();
      expect(await demoRepo.hasSyntheticData(), isTrue);

      // Metrics with synthetic included vs excluded
      final metricsWithDemo = await demoRepo.getMetrics(includeSynthetic: true);
      expect(metricsWithDemo.totalClients, greaterThan(1));
      expect(metricsWithDemo.approvedScopes, greaterThan(1));

      final metricsClean = await demoRepo.getMetrics(includeSynthetic: false);
      expect(metricsClean.totalClients, equals(1));
      expect(metricsClean.approvedScopes, equals(1));

      // 3. Toggle OFF: Purge synthetic demo data
      await demoRepo.purgeSyntheticData();
      expect(await demoRepo.hasSyntheticData(), isFalse);

      // 4. Verify real records are 100% intact and still immutable
      final remainingClients = await clientRepo.getClients();
      expect(remainingClients.length, equals(1));
      expect(remainingClients.first.id, equals('real-client-1'));

      final remainingProjects = await projectRepo.getProjects();
      expect(remainingProjects.length, equals(1));
      expect(remainingProjects.first.id, equals('real-proj-1'));

      final remainingScope = await scopeRepo.getVersionWithItems(realDraft.version.id);
      expect(remainingScope, isNotNull);
      expect(remainingScope!.version.title, equals('Real Approved Scope'));
      expect(remainingScope.items.length, equals(1));
      expect(remainingScope.items.first.description, equals('Real Deliverable 1'));

      // 5. Verify real approved scope cannot be tampered with or deleted
      expect(
        () => dbService.db.rawUpdate(
          'UPDATE scope_versions SET title = ? WHERE id = ?',
          ['Tampered Title', realDraft.version.id],
        ),
        throwsA(isA<DatabaseException>()),
      );

      await dbService.close();
    });

    test('upgrades legacy database triggers onOpen so existing databases can toggle demo off', () async {
      final tempDir = await Directory.systemTemp.createTemp('solodesk_trigger_upgrade_');
      final dbFile = p.join(tempDir.path, 'legacy_trigger_test.db');

      try {
        // 1. Initialize a valid database at Schema Version 1
        {
          final dbV1 = await DatabaseService.openPath(dbFile, version: 1);
          // Manually replace trigger with old faulty trigger lacking is_synthetic = 0 check
          await dbV1.db.execute('DROP TRIGGER IF EXISTS trg_scope_items_prevent_delete_when_approved;');
          await dbV1.db.execute('''
            CREATE TRIGGER trg_scope_items_prevent_delete_when_approved
            BEFORE DELETE ON scope_items
            FOR EACH ROW
            WHEN (SELECT status FROM scope_versions WHERE id = OLD.scope_version_id) = 'approved'
            BEGIN
              SELECT RAISE(ABORT, 'IMMUTABILITY_VIOLATION: Cannot delete items under an approved scope version.');
            END;
          ''');

          // Insert synthetic approved scope and synthetic scope item into this legacy DB
          final now = DateTime.now().toUtc();
          await dbV1.db.insert('clients', {
            'id': 'legacy-client-1',
            'name': 'Legacy Client',
            'initials': 'LC',
            'is_synthetic': 1,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          });
          await dbV1.db.insert('projects', {
            'id': 'legacy-p-1',
            'client_id': 'legacy-client-1',
            'name': 'Legacy Project',
            'niche': 'Design & branding',
            'budget_minor_units': 10000,
            'currency': 'USD',
            'status': 'active',
            'is_synthetic': 1,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          });
          await dbV1.db.insert('scope_versions', {
            'id': 'syn-v1',
            'project_id': 'legacy-p-1',
            'version_number': 1,
            'title': 'Brand Identity Deliverables',
            'status': 'approved',
            'is_synthetic': 1,
            'created_at': now.toIso8601String(),
          });
          await dbV1.db.insert('scope_items', {
            'id': 'syn-item-1',
            'scope_version_id': 'syn-v1',
            'category': 'included',
            'description': 'Primary logo',
            'sort_order': 0,
            'is_synthetic': 1,
          });

          // Confirm that under the old trigger, attempting to delete the synthetic item fails
          expect(
            () => dbV1.db.execute('DELETE FROM scope_items WHERE is_synthetic = 1;'),
            throwsA(isA<DatabaseException>()),
          );

          await dbV1.close();
        }

        // 2. Open with DatabaseService.openPath - onOpen hook runs _ensureTriggers
        final upgradedService = await DatabaseService.openPath(dbFile);

        // 3. Deleting synthetic items now succeeds!
        await upgradedService.db.execute('DELETE FROM scope_items WHERE is_synthetic = 1;');
        final countRes = await upgradedService.db.rawQuery('SELECT COUNT(*) as count FROM scope_items;');
        expect(countRes.first['count'], equals(0));

        await upgradedService.close();
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
