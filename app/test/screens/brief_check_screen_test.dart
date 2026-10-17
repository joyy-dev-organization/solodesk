import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solodesk/db/repository_scope.dart';
import 'package:solodesk/db/client_repository.dart';
import 'package:solodesk/db/project_repository.dart';
import 'package:solodesk/db/scope_repository.dart';
import 'package:solodesk/db/preference_repository.dart';
import 'package:solodesk/db/demo_data_repository.dart';
import 'package:solodesk/models/brief_check_models.dart';
import 'package:solodesk/models/client.dart';
import 'package:solodesk/models/project.dart';
import 'package:solodesk/models/scope_version.dart';
import 'package:solodesk/models/scope_item.dart';
import 'package:solodesk/models/service_preference.dart';
import 'package:solodesk/screens/brief_check_screen.dart';
import 'package:solodesk/services/brief_check_client.dart';
import 'package:solodesk/services/brief_check_exceptions.dart';
import '../helpers/fake_invoice_repository.dart';

class FakeBriefCheckClient extends BriefCheckClient {
  BriefCheckResult? stubResult;
  Exception? errorToThrow;

  FakeBriefCheckClient({this.stubResult, this.errorToThrow})
      : super(host: '127.0.0.1', port: 3141);

  @override
  Future<BriefCheckResult> checkBrief({
    required String briefText,
    required String niche,
    ServicePreference? preferences,
  }) async {
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return stubResult ??
        BriefCheckResult(
          requestId: 'test-req-123',
          statedRequirements: const ['Modern minimalist logo for coffee brand'],
          assumptions: const ['Client needs vector SVG/EPS formats'],
          omissions: const ['Cup printing specifications', 'Exact launch deadline'],
          suggestedQuestions: const [
            'What specific cup dimensions or die-cut templates will you be printing on?',
            'What is your target launch date next month?'
          ],
          starterScopeItems: const [
            StarterScopeDeliverable(
              title: 'Primary Logo Concept',
              description: 'Vector logo design with full color and monochrome master files',
            ),
            StarterScopeDeliverable(
              title: 'Brand Assets Pack',
              description: 'Color palette and typography pairing guide',
            ),
          ],
        );
  }
}

class TestClientRepo implements IClientRepository {
  final List<Client> clients = [];
  @override
  Future<List<Client>> getClients({bool includeSynthetic = true}) async => clients;
  @override
  Future<Client?> getClientById(String id) async =>
      clients.cast<Client?>().firstWhere((c) => c?.id == id, orElse: () => null);
  @override
  Future<void> createClient(Client client) async => clients.add(client);
  @override
  Future<void> updateClient(Client client) async {}
  @override
  Future<void> deleteClient(String id) async {}
}

class TestProjectRepo implements IProjectRepository {
  final List<Project> projects = [];
  @override
  Future<List<Project>> getProjects({String? clientId, bool includeSynthetic = true}) async => projects;
  @override
  Future<Project?> getProjectById(String id) async =>
      projects.cast<Project?>().firstWhere((p) => p?.id == id, orElse: () => null);
  @override
  Future<void> createProject(Project project) async => projects.add(project);
  @override
  Future<void> updateProject(Project project) async {}
  @override
  Future<void> deleteProject(String id) async {}
}

class TestScopeRepo implements IScopeRepository {
  final List<ScopeVersionWithItems> versions = [];

  @override
  Future<List<ScopeVersion>> getVersionsForProject(String projectId) async =>
      versions.map((v) => v.version).where((v) => v.projectId == projectId).toList();

  @override
  Future<ScopeVersionWithItems?> getVersionWithItems(String versionId) async =>
      versions.cast<ScopeVersionWithItems?>().firstWhere(
            (v) => v?.version.id == versionId,
            orElse: () => null,
          );

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
    final v = ScopeVersion(
      id: 'version-1',
      projectId: projectId,
      versionNumber: 1,
      title: title,
      status: 'draft',
      notes: notes,
      isSynthetic: isSynthetic,
      createdAt: DateTime.now().toUtc(),
    );
    final res = ScopeVersionWithItems(version: v, items: items);
    versions.add(res);
    return res;
  }

  @override
  Future<void> updateDraft({
    required ScopeVersion version,
    required List<ScopeItem> items,
  }) async {}

  @override
  Future<ScopeVersionWithItems> approveVersion(String versionId) async {
    final idx = versions.indexWhere((v) => v.version.id == versionId);
    final existing = versions[idx];
    final approvedVersion = existing.version.copyWith(status: 'approved');
    final updated = ScopeVersionWithItems(
      version: approvedVersion,
      items: existing.items,
    );
    versions[idx] = updated;
    return updated;
  }

  @override
  Future<ScopeVersionWithItems> createRevisionFromApproved(
    String approvedVersionId, {
    required String newTitle,
    String? notes,
  }) async {
    throw UnimplementedError();
  }

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
  @override
  Future<bool> hasSyntheticData() async => false;
  @override
  Future<void> seedSyntheticData() async {}
  @override
  Future<void> purgeSyntheticData() async {}
  @override
  Future<OverviewMetrics> getMetrics({bool includeSynthetic = false}) async =>
      const OverviewMetrics(totalClients: 0, activeProjects: 0, approvedScopes: 0, pendingDrafts: 0);
}

void main() {
  group('BriefCheckScreen Widget & Integration Tests', () {
    late TestPreferenceRepo preferenceRepo;
    late TestClientRepo clientRepo;
    late TestProjectRepo projectRepo;
    late TestScopeRepo scopeRepo;
    late TestDemoDataRepo demoDataRepo;

    setUp(() {
      preferenceRepo = TestPreferenceRepo();
      clientRepo = TestClientRepo();
      projectRepo = TestProjectRepo();
      scopeRepo = TestScopeRepo();
      demoDataRepo = TestDemoDataRepo();
    });

    Widget buildTestScreen({BriefCheckClient? client, VoidCallback? onScopeApproved}) {
      return MaterialApp(
        home: RepositoryScope(
          preferenceRepo: preferenceRepo,
          clientRepo: clientRepo,
          projectRepo: projectRepo,
          scopeRepo: scopeRepo,
          demoDataRepo: demoDataRepo,
          invoiceRepo: FakeInvoiceRepository(),
          child: Scaffold(
            body: BriefCheckScreen(
              client: client ?? FakeBriefCheckClient(),
              onScopeApproved: onScopeApproved,
            ),
          ),
        ),
      );
    }

    testWidgets('renders Idle state with live character counter and sample buttons', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScreen());
      await tester.pump();

      expect(find.text('BRIEFCHECK · AI REQUIREMENTS REVIEW'), findsOneWidget);
      expect(find.text('LOCAL MODEL READY'), findsOneWidget);
      expect(find.text('AI Requirements & Starting Scope'), findsOneWidget);
      expect(find.textContaining('/ 8,000'), findsOneWidget);
      expect(find.text('Load Vague Design Brief'), findsOneWidget);
      expect(find.text('Load Specified Writing Brief'), findsOneWidget);
    });

    testWidgets('enforces 8,000 character limit by disabling analyze button and showing error', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScreen());
      await tester.pump();

      // Enter oversized brief (> 8,000 characters)
      final oversizedText = 'A' * 8005;
      await tester.enterText(find.byType(TextField).first, oversizedText);
      await tester.pump();

      expect(find.text('8005 / 8,000'), findsOneWidget);
      expect(find.text('Brief exceeds 8,000 character limit'), findsOneWidget);

      // Verify Analyze button is disabled
      final analyzeBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '✧ Analyze brief'),
      );
      expect(analyzeBtn.onPressed, isNull);
    });

    testWidgets('executes analysis and renders goal, questions, omissions, and editable deliverables', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeClient = FakeBriefCheckClient();
      await tester.pumpWidget(buildTestScreen(client: fakeClient));
      await tester.pump();

      // Tap Analyze brief
      await tester.tap(find.widgetWithText(ElevatedButton, '✧ Analyze brief'));
      await tester.pump(); // Transitions to Loading
      await tester.pump(const Duration(milliseconds: 50)); // Completes Future

      // State is now Success
      expect(find.text('AI Verified'), findsOneWidget);
      expect(find.text('Modern minimalist logo for coffee brand'), findsOneWidget);
      expect(find.textContaining('What specific cup dimensions'), findsOneWidget);
      expect(find.textContaining('Omission: Cup printing specifications'), findsOneWidget);
      expect(find.text('Primary Logo Concept'), findsOneWidget);
      expect(find.text('Brand Assets Pack'), findsOneWidget);
      expect(find.text('INCLUDED'), findsWidgets);
    });

    testWidgets('allows adding a new deliverable and removing an existing deliverable', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScreen());
      await tester.pump();

      // Run analysis first
      await tester.tap(find.widgetWithText(ElevatedButton, '✧ Analyze brief'));
      await tester.pumpAndSettle();

      expect(find.text('Starter Deliverables (2)'), findsOneWidget);

      // Tap "Add deliverable"
      await tester.tap(find.text('Add deliverable'));
      await tester.pumpAndSettle();

      expect(find.text('Add Scope Deliverable'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Deliverable Title *'), 'Social Media Icon Kit');
      await tester.tap(find.text('Add Deliverable'));
      await tester.pumpAndSettle();

      expect(find.text('Starter Deliverables (3)'), findsOneWidget);
      expect(find.text('Social Media Icon Kit'), findsOneWidget);

      // Remove the newly added deliverable
      final removeButtons = find.byTooltip('Remove deliverable');
      expect(removeButtons, findsWidgets);
      await tester.tap(removeButtons.last);
      await tester.pumpAndSettle();

      expect(find.text('Starter Deliverables (2)'), findsOneWidget);
      expect(find.text('Social Media Icon Kit'), findsNothing);
    });

    testWidgets('approves scope, saves client/project/scope to SQLite, and displays confirmation', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool callbackFired = false;
      await tester.pumpWidget(buildTestScreen(onScopeApproved: () => callbackFired = true));
      await tester.pump();

      // Run analysis
      await tester.tap(find.widgetWithText(ElevatedButton, '✧ Analyze brief'));
      await tester.pumpAndSettle();

      // Tap Approve
      final approveBtn = find.widgetWithText(ElevatedButton, '✓ Approve Starting Scope (V1)');
      await tester.ensureVisible(approveBtn);
      await tester.pumpAndSettle();
      await tester.tap(approveBtn);
      await tester.pumpAndSettle();

      expect(find.text('Approve & Save Starting Scope'), findsOneWidget);
      expect(find.text('Included Deliverables (2):'), findsOneWidget);

      // Tap dialog confirm "Approve Scope (V1)"
      await tester.tap(find.widgetWithText(ElevatedButton, 'Approve Scope (V1)'));
      await tester.pumpAndSettle();

      // Verify callback fired
      expect(callbackFired, isTrue);

      // Verify SQLite state
      expect(clientRepo.clients.length, 1);
      expect(clientRepo.clients.first.name, 'MorningGlow');

      expect(projectRepo.projects.length, 1);
      expect(projectRepo.projects.first.name, 'Primary Logo Concept');

      expect(scopeRepo.versions.length, 1);
      final approvedScope = scopeRepo.versions.first;
      expect(approvedScope.version.status, 'approved');
      expect(approvedScope.version.versionNumber, 1);
      expect(approvedScope.items.length, 2);

      // Verify UI shows locked approved banner
      expect(find.textContaining('Scope Approved! Saved as immutable Version 1'), findsOneWidget);
      expect(find.text('✓ Scope Approved (V1)'), findsOneWidget);
    });

    testWidgets('error state preserves brief text without erasure and shows retry button', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final offlineClient = FakeBriefCheckClient(
        errorToThrow: BriefCheckModelOfflineException('Local Ollama daemon is not responding.'),
      );

      await tester.pumpWidget(buildTestScreen(client: offlineClient));
      await tester.pump();

      const testPrompt = 'Design an organic bakery packaging label for artisan sourdough bread.';
      await tester.enterText(find.byType(TextField).first, testPrompt);
      await tester.pump();

      // Tap Analyze
      await tester.tap(find.widgetWithText(ElevatedButton, '✧ Analyze brief'));
      await tester.pumpAndSettle();

      // Error state displayed
      expect(find.text('Analysis Failed'), findsOneWidget);
      expect(find.text('MODEL_OFFLINE'), findsOneWidget);
      expect(find.textContaining('Local Ollama daemon is not responding'), findsOneWidget);
      expect(find.text('Retry Analysis'), findsOneWidget);

      // CRITICAL ACCEPTANCE CRITERIA: original brief text is NEVER erased
      final textField = tester.widget<TextField>(find.byType(TextField).first);
      expect(textField.controller?.text, testPrompt);
    });
  });
}
