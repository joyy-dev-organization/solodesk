import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solodesk/main.dart';
import 'package:solodesk/db/preference_repository.dart';
import 'package:solodesk/db/client_repository.dart';
import 'package:solodesk/db/project_repository.dart';
import 'package:solodesk/db/scope_repository.dart';
import 'package:solodesk/db/demo_data_repository.dart';
import 'package:solodesk/models/client.dart';
import 'package:solodesk/models/project.dart';
import 'package:solodesk/models/scope_version.dart';
import 'package:solodesk/models/scope_item.dart';
import 'package:solodesk/models/service_preference.dart';
import 'package:solodesk/services/service_health.dart';
import 'helpers/fake_invoice_repository.dart';
import 'helpers/fake_lead_repository.dart';
import 'helpers/fake_service_plan_repository.dart';

class FakeServiceHealthClient extends ServiceHealthClient {
  FakeServiceHealthClient() : super(host: '127.0.0.1', port: 3141);

  @override
  Future<ServiceHealthStatus> checkHealth() async {
    return const ServiceHealthStatus(
      isHealthy: true,
      status: 'ok',
      service: 'solodesk-service',
      version: '0.1.0',
      loopbackOnly: true,
      modelReady: true,
      activeModel: 'qwen3:1.7b',
    );
  }
}

class MockPreferenceRepo implements IPreferenceRepository {
  ServicePreference _pref = ServicePreference.initial();
  @override
  Future<ServicePreference> getPreferences() async => _pref;
  @override
  Future<void> savePreferences(ServicePreference preferences) async => _pref = preferences;
}

class MockClientRepo implements IClientRepository {
  final List<Client> _clients = [];
  @override
  Future<List<Client>> getClients({bool includeSynthetic = true}) async {
    return _clients.where((c) => includeSynthetic || !c.isSynthetic).toList();
  }
  @override
  Future<Client?> getClientById(String id) async =>
      _clients.cast<Client?>().firstWhere((c) => c?.id == id, orElse: () => null);
  @override
  Future<void> createClient(Client client) async => _clients.add(client);
  @override
  Future<void> updateClient(Client client) async {
    final idx = _clients.indexWhere((c) => c.id == client.id);
    if (idx != -1) _clients[idx] = client;
  }
  @override
  Future<void> deleteClient(String id) async => _clients.removeWhere((c) => c.id == id);
}

class MockProjectRepo implements IProjectRepository {
  final List<Project> _projects = [];
  @override
  Future<List<Project>> getProjects({String? clientId, bool includeSynthetic = true}) async {
    return _projects.where((p) {
      if (!includeSynthetic && p.isSynthetic) return false;
      if (clientId != null && p.clientId != clientId) return false;
      return true;
    }).toList();
  }
  @override
  Future<Project?> getProjectById(String id) async =>
      _projects.cast<Project?>().firstWhere((p) => p?.id == id, orElse: () => null);
  @override
  Future<void> createProject(Project project) async => _projects.add(project);
  @override
  Future<void> updateProject(Project project) async {
    final idx = _projects.indexWhere((p) => p.id == project.id);
    if (idx != -1) _projects[idx] = project;
  }
  @override
  Future<void> deleteProject(String id) async => _projects.removeWhere((p) => p.id == id);
}

class MockScopeRepo implements IScopeRepository {
  @override
  Future<List<ScopeVersion>> getVersionsForProject(String projectId) async => const [];

  @override
  Future<ScopeVersionWithItems?> getVersionWithItems(String versionId) async => null;

  @override
  Future<ScopeVersionWithItems?> getLatestApprovedVersion(String projectId) async => null;

  @override
  Future<ScopeVersionWithItems> createDraft({
    required String projectId,
    required String title,
    String? notes,
    List<ScopeItem> items = const [],
    bool isSynthetic = false,
  }) async {
    final now = DateTime.now();
    final v = ScopeVersion(
      id: 'v-test',
      projectId: projectId,
      versionNumber: 1,
      title: title,
      status: 'draft',
      notes: notes,
      isSynthetic: isSynthetic,
      createdAt: now,
    );
    return ScopeVersionWithItems(version: v, items: items);
  }

  @override
  Future<void> updateDraft({
    required ScopeVersion version,
    required List<ScopeItem> items,
  }) async {}

  @override
  Future<ScopeVersionWithItems> approveVersion(String versionId) async {
    final v = ScopeVersion(
      id: versionId,
      projectId: 'p',
      versionNumber: 1,
      title: 'Approved',
      status: 'approved',
      createdAt: DateTime.now(),
    );
    return ScopeVersionWithItems(version: v, items: const []);
  }

  @override
  Future<ScopeVersionWithItems> createRevisionFromApproved(
    String approvedVersionId, {
    required String newTitle,
    String? notes,
  }) async {
    final v = ScopeVersion(
      id: 'v-test-2',
      projectId: 'p',
      versionNumber: 2,
      title: newTitle,
      status: 'draft',
      notes: notes,
      createdAt: DateTime.now(),
    );
    return ScopeVersionWithItems(version: v, items: const []);
  }

  @override
  Future<void> deleteDraft(String versionId) async {}
}

class MockDemoDataRepo implements IDemoDataRepository {
  bool _hasDemo = false;
  @override
  Future<bool> hasSyntheticData() async => _hasDemo;
  @override
  Future<void> seedSyntheticData() async => _hasDemo = true;
  @override
  Future<void> purgeSyntheticData() async => _hasDemo = false;
  @override
  Future<OverviewMetrics> getMetrics({bool includeSynthetic = false}) async {
    if (_hasDemo && includeSynthetic) {
      return const OverviewMetrics(totalClients: 3, activeProjects: 2, approvedScopes: 1, pendingDrafts: 0);
    }
    return const OverviewMetrics(totalClients: 0, activeProjects: 0, approvedScopes: 0, pendingDrafts: 0);
  }
}

void main() {
  group('SoloDesk Desktop Shell & Navigation Widget Tests', () {
    late MockPreferenceRepo preferenceRepo;
    late MockClientRepo clientRepo;
    late MockProjectRepo projectRepo;
    late MockScopeRepo scopeRepo;
    late MockDemoDataRepo demoDataRepo;

    setUp(() {
      preferenceRepo = MockPreferenceRepo();
      clientRepo = MockClientRepo();
      projectRepo = MockProjectRepo();
      scopeRepo = MockScopeRepo();
      demoDataRepo = MockDemoDataRepo();
    });

    Widget createTestApp() {
      return SoloDeskApp(
        preferenceRepo: preferenceRepo,
        clientRepo: clientRepo,
        projectRepo: projectRepo,
        scopeRepo: scopeRepo,
        demoDataRepo: demoDataRepo,
        invoiceRepo: FakeInvoiceRepository(),
        leadRepo: FakeLeadRepository(),
        servicePlanRepo: FakeServicePlanRepository(),
        healthClient: FakeServiceHealthClient(),
        enableHealthPolling: false,
      );
    }

    testWidgets('renders sidebar navigation items and defaults to Overview with 0 records', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestApp());
      await tester.pump();

      // Sidebar branding
      expect(find.text('SoloDesk'), findsOneWidget);
      expect(find.text('YOUR FREELANCE HQ'), findsOneWidget);

      // Verify all 7 navigation destinations exist in sidebar
      expect(find.text('Overview'), findsWidgets);
      expect(find.text('LeadLoop'), findsOneWidget);
      expect(find.text('BriefCheck'), findsOneWidget);
      expect(find.text('ScopeShield'), findsOneWidget);
      expect(find.text('PolitePay'), findsOneWidget);
      expect(find.text('Repeat Work'), findsOneWidget);
      expect(find.text('My services'), findsWidgets);

      // Verify default Overview zero-record metrics (no hallucinated metrics)
      expect(find.text('00'), findsWidgets); // 4 stat cards showing "00"
      expect(find.text('Active projects'), findsOneWidget);
      expect(find.text('Total clients'), findsOneWidget);
      expect(find.text('Approved scopes'), findsOneWidget);
    });

    testWidgets('navigating to PolitePay, LeadLoop, and Repeat Work renders live screens', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestApp());
      await tester.pump();

      // 1. PolitePay (Implemented in M5)
      await tester.tap(find.text('PolitePay'));
      await tester.pumpAndSettle();
      expect(find.text('PolitePay: Invoices & Multi-Currency Accounting'), findsOneWidget);

      // 2. LeadLoop (Implemented in M6)
      await tester.tap(find.text('LeadLoop'));
      await tester.pumpAndSettle();
      expect(find.text('LeadLoop ✦'), findsOneWidget);

      // 3. Repeat Work (Implemented in M7)
      await tester.tap(find.text('Repeat Work'));
      await tester.pumpAndSettle();
      expect(find.text('Repeat Work'), findsWidgets);
      expect(find.text('+ New service plan'), findsOneWidget);
    });

    testWidgets('toggling synthetic demo records seeds and purges records in SQLite', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestApp());
      await tester.pump();

      // Initially zero records
      expect(await demoDataRepo.hasSyntheticData(), isFalse);

      // Find and click "Load Demo Data" toggle button
      final demoToggle = find.text('Load Demo Data');
      expect(demoToggle, findsOneWidget);
      await tester.tap(demoToggle);
      await tester.pump();

      // Verify synthetic records were seeded
      expect(await demoDataRepo.hasSyntheticData(), isTrue);
      expect(find.text('Demo Data: ON'), findsOneWidget);

      // Toggle back off (purges synthetic records)
      await tester.tap(find.text('Demo Data: ON'));
      await tester.pump();

      // Verify synthetic records were purged
      expect(await demoDataRepo.hasSyntheticData(), isFalse);
      expect(find.text('Load Demo Data'), findsOneWidget);
    });

    testWidgets('navigating to My services screen renders niche checklist', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestApp());
      await tester.pump();

      // Tap "My services" in sidebar
      await tester.tap(find.text('My services').first);
      await tester.pump();

      expect(find.text('Make SoloDesk fit the work you do.'), findsOneWidget);
      expect(find.text('Design & branding'), findsOneWidget);
      expect(find.text('Writing & content'), findsOneWidget);
      expect(find.text('Software & development'), findsOneWidget);
      expect(find.text('Save preferences'), findsOneWidget);
    });
  });
}
