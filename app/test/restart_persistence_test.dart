import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:solodesk/db/database_service.dart';
import 'package:solodesk/db/preference_repository.dart';
import 'package:solodesk/db/client_repository.dart';
import 'package:solodesk/db/project_repository.dart';
import 'package:solodesk/db/scope_repository.dart';
import 'package:solodesk/models/service_preference.dart';
import 'package:solodesk/models/client.dart';
import 'package:solodesk/models/project.dart';
import 'package:solodesk/models/money.dart';
import 'package:solodesk/models/scope_item.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Simulated cold restart persistence test from disk file', () async {
    final tempDir = await Directory.systemTemp.createTemp('solodesk_persistence_test_');
    final dbFile = p.join(tempDir.path, 'restart_test.db');

    try {
      // 1. Session 1: Create and approve records
      {
        final dbService = await DatabaseService.openPath(dbFile);
        final prefRepo = PreferenceRepository(dbService.db);
        final clientRepo = ClientRepository(dbService.db);
        final projectRepo = ProjectRepository(dbService.db);
        final scopeRepo = ScopeRepository(dbService.db);

        // Save preferences
        final now = DateTime.now().toUtc();
        await prefRepo.savePreferences(ServicePreference(
          id: 'default',
          niches: const ['Design & branding', 'Writing & content', 'Consulting'],
          defaultCurrency: 'USD',
          businessName: 'Joyce Ava Creative',
          createdAt: now,
          updatedAt: now,
        ));

        // Save client
        await clientRepo.createClient(Client(
          id: 'client-restart-1',
          name: 'Starlight Media',
          initials: 'SM',
          company: 'Starlight Group',
          createdAt: now,
          updatedAt: now,
        ));

        // Save project
        await projectRepo.createProject(Project(
          id: 'proj-restart-1',
          clientId: 'client-restart-1',
          name: 'Social Media Assets',
          niche: 'Design & branding',
          budget: const Money(minorUnits: 175000, currency: 'USD'),
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ));

        // Create and approve scope version
        final draft = await scopeRepo.createDraft(
          projectId: 'proj-restart-1',
          title: 'Starting Deliverables',
          items: [
            const ScopeItem(id: 'item-r-1', scopeVersionId: '', category: 'included', description: '5 Instagram carousels'),
            const ScopeItem(id: 'item-r-2', scopeVersionId: '', category: 'excluded', description: 'Ad spend management'),
          ],
        );
        await scopeRepo.approveVersion(draft.version.id);

        // Explicitly close DB to simulate complete process exit
        await dbService.close();
      }

      // 2. Session 2: Cold restart from same disk file
      {
        final reopenedDbService = await DatabaseService.openPath(dbFile);
        final prefRepo = PreferenceRepository(reopenedDbService.db);
        final clientRepo = ClientRepository(reopenedDbService.db);
        final projectRepo = ProjectRepository(reopenedDbService.db);
        final scopeRepo = ScopeRepository(reopenedDbService.db);

        // Assert preferences survived
        final prefs = await prefRepo.getPreferences();
        expect(prefs.defaultCurrency, equals('USD'));
        expect(prefs.businessName, equals('Joyce Ava Creative'));
        expect(prefs.niches, contains('Consulting'));

        // Assert client survived
        final client = await clientRepo.getClientById('client-restart-1');
        expect(client, isNotNull);
        expect(client!.name, equals('Starlight Media'));
        expect(client.initials, equals('SM'));

        // Assert project survived
        final projects = await projectRepo.getProjects(clientId: 'client-restart-1');
        expect(projects.length, equals(1));
        expect(projects.first.budget.format(), equals('\$1750.00'));

        // Assert approved scope survived with items
        final approvedScope = await scopeRepo.getLatestApprovedVersion('proj-restart-1');
        expect(approvedScope, isNotNull);
        expect(approvedScope!.version.isApproved, isTrue);
        expect(approvedScope.version.title, equals('Starting Deliverables'));
        expect(approvedScope.items.length, equals(2));
        expect(approvedScope.items.map((i) => i.description), containsAll(['5 Instagram carousels', 'Ad spend management']));

        await reopenedDbService.close();
      }
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
