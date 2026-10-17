import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solodesk/db/repository_scope.dart';
import 'package:solodesk/db/client_repository.dart';
import 'package:solodesk/db/project_repository.dart';
import 'package:solodesk/db/scope_repository.dart';
import 'package:solodesk/db/preference_repository.dart';
import 'package:solodesk/db/demo_data_repository.dart';
import 'package:solodesk/models/client.dart';
import 'package:solodesk/models/project.dart';
import 'package:solodesk/models/money.dart';
import 'package:solodesk/models/scope_version.dart';
import 'package:solodesk/models/scope_item.dart';
import 'package:solodesk/models/service_preference.dart';
import 'package:solodesk/screens/overview_screen.dart';
import '../helpers/fake_invoice_repository.dart';

class TestClientRepo implements IClientRepository {
  final List<Client> clients = [];
  @override
  Future<List<Client>> getClients({bool includeSynthetic = true}) async {
    return clients.where((c) => includeSynthetic || !c.isSynthetic).toList();
  }
  @override
  Future<Client?> getClientById(String id) async =>
      clients.cast<Client?>().firstWhere((c) => c?.id == id, orElse: () => null);
  @override
  Future<void> createClient(Client client) async => clients.add(client);
  @override
  Future<void> updateClient(Client client) async {
    final idx = clients.indexWhere((c) => c.id == client.id);
    if (idx != -1) clients[idx] = client;
  }
  @override
  Future<void> deleteClient(String id) async => clients.removeWhere((c) => c.id == id);
}

class TestProjectRepo implements IProjectRepository {
  final List<Project> projects = [];
  @override
  Future<List<Project>> getProjects({String? clientId, bool includeSynthetic = true}) async {
    return projects.where((p) {
      if (!includeSynthetic && p.isSynthetic) return false;
      if (clientId != null && p.clientId != clientId) return false;
      return true;
    }).toList();
  }
  @override
  Future<Project?> getProjectById(String id) async =>
      projects.cast<Project?>().firstWhere((p) => p?.id == id, orElse: () => null);
  @override
  Future<void> createProject(Project project) async => projects.add(project);
  @override
  Future<void> updateProject(Project project) async {
    final idx = projects.indexWhere((p) => p.id == project.id);
    if (idx != -1) projects[idx] = project;
  }
  @override
  Future<void> deleteProject(String id) async => projects.removeWhere((p) => p.id == id);
}

class TestScopeRepo implements IScopeRepository {
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
  }) async => throw UnimplementedError();
  @override
  Future<void> updateDraft({required ScopeVersion version, required List<ScopeItem> items}) async {}
  @override
  Future<ScopeVersionWithItems> approveVersion(String versionId) async => throw UnimplementedError();
  @override
  Future<ScopeVersionWithItems> createRevisionFromApproved(
    String approvedVersionId, {
    required String newTitle,
    String? notes,
  }) async => throw UnimplementedError();
  @override
  Future<void> deleteDraft(String versionId) async {}
}

class TestPreferenceRepo implements IPreferenceRepository {
  ServicePreference pref = ServicePreference.initial();
  @override
  Future<ServicePreference> getPreferences() async => pref;
  @override
  Future<void> savePreferences(ServicePreference preferences) async => pref = preferences;
}

class TestDemoDataRepo implements IDemoDataRepository {
  bool syntheticActive = false;
  OverviewMetrics metrics = const OverviewMetrics(
    totalClients: 0,
    activeProjects: 0,
    approvedScopes: 0,
    pendingDrafts: 0,
    unpaidInvoices: 0,
  );

  @override
  Future<bool> hasSyntheticData() async => syntheticActive;
  @override
  Future<void> seedSyntheticData() async => syntheticActive = true;
  @override
  Future<void> purgeSyntheticData() async => syntheticActive = false;
  @override
  Future<OverviewMetrics> getMetrics({bool includeSynthetic = false}) async => metrics;
}

void main() {
  group('OverviewScreen Widget & CRUD Tests', () {
    late TestPreferenceRepo preferenceRepo;
    late TestClientRepo clientRepo;
    late TestProjectRepo projectRepo;
    late TestScopeRepo scopeRepo;
    late TestDemoDataRepo demoDataRepo;
    late FakeInvoiceRepository invoiceRepo;

    setUp(() {
      preferenceRepo = TestPreferenceRepo();
      clientRepo = TestClientRepo();
      projectRepo = TestProjectRepo();
      scopeRepo = TestScopeRepo();
      demoDataRepo = TestDemoDataRepo();
      invoiceRepo = FakeInvoiceRepository();
    });

    Widget createWidgetUnderTest({bool isSyntheticDemoActive = false}) {
      return MaterialApp(
        home: Scaffold(
          body: RepositoryScope(
            preferenceRepo: preferenceRepo,
            clientRepo: clientRepo,
            projectRepo: projectRepo,
            scopeRepo: scopeRepo,
            demoDataRepo: demoDataRepo,
            invoiceRepo: invoiceRepo,
            child: OverviewScreen(
              onNavigate: (_) {},
              isSyntheticDemoActive: isSyntheticDemoActive,
            ),
          ),
        ),
      );
    }

    testWidgets('renders zero metrics on fresh state without fabricating numbers', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('WORKSPACE · YOUR BUSINESS AT A GLANCE'), findsOneWidget);
      expect(find.text('Workspace Overview ✦'), findsOneWidget);
      expect(find.text('No saved projects yet'), findsOneWidget);
      expect(find.text('Active projects'), findsOneWidget);
      expect(find.text('Total clients'), findsOneWidget);
      expect(find.text('Approved scopes'), findsOneWidget);
      expect(find.text('Invoices due'), findsOneWidget);
    });

    testWidgets('Add Client dialog creates client and refreshes screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final addClientBtn = find.text('＋ Add client');
      expect(addClientBtn, findsOneWidget);
      await tester.tap(addClientBtn);
      await tester.pumpAndSettle();

      expect(find.text('Add Client'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Client or Contact Name *'), 'Acme Studios');
      await tester.enterText(find.widgetWithText(TextField, 'Company / Brand (Optional)'), 'Acme Global Inc');
      await tester.enterText(find.widgetWithText(TextField, 'Email Address (Optional)'), 'contact@acme.com');

      final saveBtn = find.widgetWithText(ElevatedButton, 'Save Client');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(clientRepo.clients.length, 1);
      expect(clientRepo.clients.first.name, 'Acme Studios');
    });

    testWidgets('Add Project dialog creates project and refreshes screen', (tester) async {
      final now = DateTime.now().toUtc();
      clientRepo.clients.add(Client(
        id: 'client-1',
        name: 'Apex Design',
        initials: 'AD',
        createdAt: now,
        updatedAt: now,
      ));

      await tester.binding.setSurfaceSize(const Size(1400, 900));
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final addProjBtn = find.text('＋ Add project');
      expect(addProjBtn, findsOneWidget);
      await tester.tap(addProjBtn);
      await tester.pumpAndSettle();

      expect(find.text('Add Project'), findsOneWidget);

      // Enter project name and budget
      await tester.enterText(find.byType(TextField).first, 'Brand Identity');
      await tester.enterText(find.byType(TextField).last, '2500');

      final saveBtn = find.widgetWithText(ElevatedButton, 'Save Project');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(projectRepo.projects.length, 1);
      expect(projectRepo.projects.first.name, 'Brand Identity');
      expect(projectRepo.projects.first.budget.minorUnits, 250000);
      expect(find.text('Brand Identity'), findsOneWidget);
    });

    testWidgets('Displays DEMO RECORD badge for synthetic records when demo is active', (tester) async {
      final now = DateTime.now().toUtc();
      clientRepo.clients.add(Client(
        id: 'c-synth',
        name: 'Synthetic Client Co',
        initials: 'SC',
        isSynthetic: true,
        createdAt: now,
        updatedAt: now,
      ));
      projectRepo.projects.add(Project(
        id: 'p-synth',
        clientId: 'c-synth',
        name: 'Synthetic Project Alpha',
        niche: 'Design & branding',
        budget: const Money(minorUnits: 120000, currency: 'USD'),
        status: 'active',
        isSynthetic: true,
        createdAt: now,
        updatedAt: now,
      ));

      await tester.binding.setSurfaceSize(const Size(1400, 900));
      await tester.pumpWidget(createWidgetUnderTest(isSyntheticDemoActive: true));
      await tester.pumpAndSettle();

      expect(find.text('Synthetic Project Alpha'), findsOneWidget);
      expect(find.textContaining('Synthetic Client Co'), findsOneWidget);
      expect(find.text('DEMO RECORD'), findsWidgets);
    });
  });
}
