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
import 'package:solodesk/models/scope_version.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ProjectRepository CRUD & Constraints', () {
    late DatabaseService dbService;
    late ClientRepository clientRepo;
    late ProjectRepository projectRepo;
    late ScopeRepository scopeRepo;

    setUp(() async {
      dbService = await DatabaseService.inMemory();
      clientRepo = ClientRepository(dbService.db);
      projectRepo = ProjectRepository(dbService.db);
      scopeRepo = ScopeRepository(dbService.db);

      // Create a test client
      final now = DateTime.now().toUtc();
      await clientRepo.createClient(Client(
        id: 'client-proj-test',
        name: 'Test Client',
        initials: 'TC',
        createdAt: now,
        updatedAt: now,
      ));
    });

    tearDown(() async {
      await dbService.close();
    });

    test('creates, retrieves by ID, filters by client and synthetic status', () async {
      final now = DateTime.now().toUtc();
      final p1 = Project(
        id: 'proj-1',
        clientId: 'client-proj-test',
        name: 'Brand Identity',
        niche: 'Design & branding',
        budget: const Money(minorUnits: 25000000, currency: 'NGN'),
        status: 'active',
        isSynthetic: false,
        createdAt: now,
        updatedAt: now,
      );

      final p2 = Project(
        id: 'proj-2',
        clientId: 'client-proj-test',
        name: 'Synthetic Project',
        niche: 'Writing & content',
        budget: const Money(minorUnits: 10000000, currency: 'NGN'),
        status: 'drafting',
        isSynthetic: true,
        createdAt: now,
        updatedAt: now,
      );

      await projectRepo.createProject(p1);
      await projectRepo.createProject(p2);

      // Get by ID
      final retrieved = await projectRepo.getProjectById('proj-1');
      expect(retrieved, isNotNull);
      expect(retrieved!.name, equals('Brand Identity'));
      expect(retrieved.budget.minorUnits, equals(25000000));

      // Filter by clientId
      final clientProjects = await projectRepo.getProjects(clientId: 'client-proj-test');
      expect(clientProjects.length, equals(2));

      // Filter: includeSynthetic = false
      final realProjects = await projectRepo.getProjects(includeSynthetic: false);
      expect(realProjects.length, equals(1));
      expect(realProjects.first.id, equals('proj-1'));
    });

    test('updates project status and budget', () async {
      final now = DateTime.now().toUtc();
      final project = Project(
        id: 'proj-update-1',
        clientId: 'client-proj-test',
        name: 'Original Project',
        niche: 'Software & development',
        budget: const Money(minorUnits: 50000000, currency: 'NGN'),
        status: 'lead',
        createdAt: now,
        updatedAt: now,
      );
      await projectRepo.createProject(project);

      final updated = project.copyWith(
        name: 'Revised Project Name',
        status: 'active',
        budget: const Money(minorUnits: 65000000, currency: 'NGN'),
      );
      await projectRepo.updateProject(updated);

      final reloaded = await projectRepo.getProjectById('proj-update-1');
      expect(reloaded!.name, equals('Revised Project Name'));
      expect(reloaded.status, equals('active'));
      expect(reloaded.budget.minorUnits, equals(65000000));
    });

    test('deletes project without approved scopes cleanly', () async {
      final now = DateTime.now().toUtc();
      final project = Project(
        id: 'proj-del-1',
        clientId: 'client-proj-test',
        name: 'Disposable Project',
        niche: 'Marketing',
        budget: const Money(minorUnits: 50000, currency: 'NGN'),
        status: 'lead',
        createdAt: now,
        updatedAt: now,
      );
      await projectRepo.createProject(project);
      expect(await projectRepo.getProjectById('proj-del-1'), isNotNull);

      await projectRepo.deleteProject('proj-del-1');
      expect(await projectRepo.getProjectById('proj-del-1'), isNull);
    });

    test('throws ScopeImmutabilityException when deleting project with approved scopes', () async {
      final now = DateTime.now().toUtc();
      final project = Project(
        id: 'proj-locked-1',
        clientId: 'client-proj-test',
        name: 'Locked Project',
        niche: 'Design',
        budget: const Money(minorUnits: 20000000, currency: 'NGN'),
        status: 'active',
        createdAt: now,
        updatedAt: now,
      );
      await projectRepo.createProject(project);

      final draft = await scopeRepo.createDraft(
        projectId: 'proj-locked-1',
        title: 'Starting Scope',
        items: [
          const ScopeItem(id: 'item-lock-1', scopeVersionId: '', category: 'included', description: 'Deliverable 1'),
        ],
      );
      await scopeRepo.approveVersion(draft.version.id);

      // Attempting to delete project must throw ScopeImmutabilityException
      expect(
        () => projectRepo.deleteProject('proj-locked-1'),
        throwsA(isA<ScopeImmutabilityException>().having(
          (e) => e.message,
          'message',
          contains('Cannot delete project because it has an approved, immutable scope version'),
        )),
      );

      // Project still exists
      expect(await projectRepo.getProjectById('proj-locked-1'), isNotNull);
    });
  });
}
