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

  group('ClientRepository CRUD & Constraints', () {
    late DatabaseService dbService;
    late ClientRepository clientRepo;
    late ProjectRepository projectRepo;
    late ScopeRepository scopeRepo;

    setUp(() async {
      dbService = await DatabaseService.inMemory();
      clientRepo = ClientRepository(dbService.db);
      projectRepo = ProjectRepository(dbService.db);
      scopeRepo = ScopeRepository(dbService.db);
    });

    tearDown(() async {
      await dbService.close();
    });

    test('creates, retrieves by ID, and lists clients with synthetic filtering', () async {
      final now = DateTime.now().toUtc();
      final client1 = Client(
        id: 'client-1',
        name: 'Amina Musa',
        initials: 'AM',
        company: 'Musa Brand Lab',
        email: 'amina@example.com',
        notes: 'Initial branding call',
        isSynthetic: false,
        createdAt: now,
        updatedAt: now,
      );

      final client2 = Client(
        id: 'client-2',
        name: 'Demo Synthetic Client',
        initials: 'DS',
        company: 'Synthetic Labs',
        email: 'demo@example.com',
        isSynthetic: true,
        createdAt: now,
        updatedAt: now,
      );

      await clientRepo.createClient(client1);
      await clientRepo.createClient(client2);

      // Retrieve by ID
      final retrieved = await clientRepo.getClientById('client-1');
      expect(retrieved, isNotNull);
      expect(retrieved!.name, equals('Amina Musa'));
      expect(retrieved.company, equals('Musa Brand Lab'));

      // Filter: includeSynthetic = true
      final allClients = await clientRepo.getClients(includeSynthetic: true);
      expect(allClients.length, equals(2));

      // Filter: includeSynthetic = false
      final realClients = await clientRepo.getClients(includeSynthetic: false);
      expect(realClients.length, equals(1));
      expect(realClients.first.id, equals('client-1'));
    });

    test('updates client information', () async {
      final now = DateTime.now().toUtc();
      final client = Client(
        id: 'client-update-1',
        name: 'Original Name',
        initials: 'ON',
        company: 'Old Company',
        email: 'old@example.com',
        createdAt: now,
        updatedAt: now,
      );
      await clientRepo.createClient(client);

      final updatedClient = client.copyWith(
        name: 'Updated Name',
        company: 'New Company',
        email: 'new@example.com',
        notes: 'Updated notes',
      );
      await clientRepo.updateClient(updatedClient);

      final reloaded = await clientRepo.getClientById('client-update-1');
      expect(reloaded!.name, equals('Updated Name'));
      expect(reloaded.company, equals('New Company'));
      expect(reloaded.email, equals('new@example.com'));
      expect(reloaded.notes, equals('Updated notes'));
    });

    test('deletes client without approved scopes cleanly', () async {
      final now = DateTime.now().toUtc();
      final client = Client(
        id: 'client-del-1',
        name: 'Disposable Client',
        initials: 'DC',
        createdAt: now,
        updatedAt: now,
      );
      await clientRepo.createClient(client);
      expect(await clientRepo.getClientById('client-del-1'), isNotNull);

      await clientRepo.deleteClient('client-del-1');
      expect(await clientRepo.getClientById('client-del-1'), isNull);
    });

    test('throws ScopeImmutabilityException when deleting client with approved scopes', () async {
      final now = DateTime.now().toUtc();
      final client = Client(
        id: 'client-imm-1',
        name: 'Locked Client',
        initials: 'LC',
        createdAt: now,
        updatedAt: now,
      );
      await clientRepo.createClient(client);

      await projectRepo.createProject(Project(
        id: 'proj-imm-1',
        clientId: 'client-imm-1',
        name: 'Locked Project',
        niche: 'Design & branding',
        budget: const Money(minorUnits: 100000, currency: 'NGN'),
        status: 'active',
        createdAt: now,
        updatedAt: now,
      ));

      final draft = await scopeRepo.createDraft(
        projectId: 'proj-imm-1',
        title: 'Approved Scope',
        items: [
          const ScopeItem(id: 'item-imm-1', scopeVersionId: '', category: 'included', description: 'Logo'),
        ],
      );
      await scopeRepo.approveVersion(draft.version.id);

      // Attempting to delete client must throw ScopeImmutabilityException
      expect(
        () => clientRepo.deleteClient('client-imm-1'),
        throwsA(isA<ScopeImmutabilityException>().having(
          (e) => e.message,
          'message',
          contains('Cannot delete client because they are linked to an approved, immutable project scope'),
        )),
      );

      // Client still exists in SQLite
      expect(await clientRepo.getClientById('client-imm-1'), isNotNull);
    });
  });
}
