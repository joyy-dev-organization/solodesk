import 'package:flutter_test/flutter_test.dart';
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

  group('Database Immutability Triggers', () {
    late DatabaseService dbService;
    late ClientRepository clientRepo;
    late ProjectRepository projectRepo;
    late ScopeRepository scopeRepo;

    setUp(() async {
      dbService = await DatabaseService.inMemory();
      clientRepo = ClientRepository(dbService.db);
      projectRepo = ProjectRepository(dbService.db);
      scopeRepo = ScopeRepository(dbService.db);

      // Create base client and project
      final now = DateTime.now().toUtc();
      await clientRepo.createClient(Client(
        id: 'c-test-1',
        name: 'MorningGlow Coffee',
        initials: 'MG',
        createdAt: now,
        updatedAt: now,
      ));

      await projectRepo.createProject(Project(
        id: 'p-test-1',
        clientId: 'c-test-1',
        name: 'Brand Identity',
        niche: 'Design & branding',
        budget: const Money(minorUnits: 15000000, currency: 'NGN'),
        status: 'active',
        createdAt: now,
        updatedAt: now,
      ));
    });

    tearDown(() async {
      await dbService.close();
    });

    test('allows editing draft scope versions before approval', () async {
      final draft = await scopeRepo.createDraft(
        projectId: 'p-test-1',
        title: 'Draft Scope',
        items: [
          const ScopeItem(
            id: 'i-1',
            scopeVersionId: '',
            category: 'included',
            description: 'Logo concept',
          ),
        ],
      );

      // Modify draft
      await scopeRepo.updateDraft(
        version: draft.version.copyWith(title: 'Updated Draft Title'),
        items: [
          const ScopeItem(
            id: 'i-1',
            scopeVersionId: '',
            category: 'included',
            description: 'Updated logo concept with 3 revisions',
          ),
        ],
      );

      final reloaded = await scopeRepo.getVersionWithItems(draft.version.id);
      expect(reloaded!.version.title, equals('Updated Draft Title'));
      expect(reloaded.items.first.description, contains('3 revisions'));
    });

    test('prevents updating or deleting an approved scope version via SQL triggers', () async {
      final draft = await scopeRepo.createDraft(
        projectId: 'p-test-1',
        title: 'Approved V1 Scope',
        items: [
          const ScopeItem(
            id: 'i-app-1',
            scopeVersionId: '',
            category: 'included',
            description: 'Vector logo files',
          ),
        ],
      );

      // Explicitly approve
      final approved = await scopeRepo.approveVersion(draft.version.id);
      expect(approved.version.isApproved, isTrue);

      // 1. Direct update to approved scope_version must fail via trigger
      expect(
        () => dbService.db.rawUpdate(
          'UPDATE scope_versions SET title = ? WHERE id = ?',
          ['Tampered Title', draft.version.id],
        ),
        throwsA(isA<DatabaseException>().having(
          (e) => e.toString(),
          'message',
          contains('IMMUTABILITY_VIOLATION'),
        )),
      );

      // 2. Direct delete of approved scope_version must fail via trigger
      expect(
        () => dbService.db.rawDelete(
          'DELETE FROM scope_versions WHERE id = ?',
          [draft.version.id],
        ),
        throwsA(isA<DatabaseException>().having(
          (e) => e.toString(),
          'message',
          contains('IMMUTABILITY_VIOLATION'),
        )),
      );

      // 3. Modifying an item of an approved version must fail via trigger
      expect(
        () => dbService.db.rawUpdate(
          'UPDATE scope_items SET description = ? WHERE scope_version_id = ?',
          ['Unauthorized change', draft.version.id],
        ),
        throwsA(isA<DatabaseException>().having(
          (e) => e.toString(),
          'message',
          contains('IMMUTABILITY_VIOLATION'),
        )),
      );

      // 4. Deleting an item of an approved version must fail via trigger
      expect(
        () => dbService.db.rawDelete(
          'DELETE FROM scope_items WHERE scope_version_id = ?',
          [draft.version.id],
        ),
        throwsA(isA<DatabaseException>().having(
          (e) => e.toString(),
          'message',
          contains('IMMUTABILITY_VIOLATION'),
        )),
      );

      // 5. Inserting a new item into an approved version must fail via trigger
      expect(
        () => dbService.db.rawInsert(
          'INSERT INTO scope_items (id, scope_version_id, category, description) VALUES (?, ?, ?, ?)',
          ['extra-item-1', draft.version.id, 'included', 'Rogue deliverable'],
        ),
        throwsA(isA<DatabaseException>().having(
          (e) => e.toString(),
          'message',
          contains('IMMUTABILITY_VIOLATION'),
        )),
      );
    });

    test('branching an approved version creates a clean new draft version 2', () async {
      final v1 = await scopeRepo.createDraft(
        projectId: 'p-test-1',
        title: 'Initial Contract',
        items: [
          const ScopeItem(id: 'item-1', scopeVersionId: '', category: 'included', description: 'Logo'),
          const ScopeItem(id: 'item-2', scopeVersionId: '', category: 'excluded', description: 'SEO'),
        ],
      );
      await scopeRepo.approveVersion(v1.version.id);

      // Branch to V2
      final v2 = await scopeRepo.createRevisionFromApproved(
        v1.version.id,
        newTitle: 'Phase 2 Revision',
      );

      expect(v2.version.versionNumber, equals(2));
      expect(v2.version.status, equals('draft'));
      expect(v2.items.length, equals(2));
      expect(v2.items.map((i) => i.description), containsAll(['Logo', 'SEO']));

      // Modifying v2 draft works without affecting v1
      await scopeRepo.updateDraft(
        version: v2.version,
        items: [
          ...v2.items,
          const ScopeItem(id: 'item-3', scopeVersionId: '', category: 'included', description: 'Brand Book'),
        ],
      );

      final v2Updated = await scopeRepo.getVersionWithItems(v2.version.id);
      expect(v2Updated!.items.length, equals(3));

      // V1 items remain exactly 2 and immutable
      final v1Check = await scopeRepo.getVersionWithItems(v1.version.id);
      expect(v1Check!.items.length, equals(2));
    });
  });
}
