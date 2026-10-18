import 'dart:async';
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
import 'package:solodesk/models/money.dart';
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

class DelayedFakeBriefCheckClient extends BriefCheckClient {
  final Completer<BriefCheckResult> completer;

  DelayedFakeBriefCheckClient(this.completer) : super(host: '127.0.0.1', port: 3141);

  @override
  Future<BriefCheckResult> checkBrief({
    required String briefText,
    required String niche,
    ServicePreference? preferences,
  }) {
    return completer.future;
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
  Future<ScopeVersionWithItems?> getLatestApprovedVersion(String projectId) async {
    final list = versions.where((v) => v.version.projectId == projectId && v.version.status == 'approved').toList();
    if (list.isEmpty) return null;
    list.sort((a, b) => b.version.versionNumber.compareTo(a.version.versionNumber));
    return list.first;
  }

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
      tester.view.physicalSize = const Size(1280, 1200);
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
      expect(find.text('Advisory Draft · Schema-Validated'), findsOneWidget);
      expect(find.text('Modern minimalist logo for coffee brand'), findsOneWidget);
      expect(find.textContaining('What specific cup dimensions'), findsOneWidget);
      expect(find.textContaining('Cup printing specifications'), findsOneWidget);
      expect(find.textContaining('Client needs vector SVG/EPS formats'), findsOneWidget);
      expect(find.text('Primary Logo Concept'), findsOneWidget);
      expect(find.text('Brand Assets Pack'), findsOneWidget);
      expect(find.text('INCLUDED'), findsWidgets);
    });

    testWidgets('allows adding a new deliverable and removing an existing deliverable', (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
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
      await tester.ensureVisible(removeButtons.last);
      await tester.pumpAndSettle();
      await tester.tap(removeButtons.last);
      await tester.pumpAndSettle();

      expect(find.text('Starter Deliverables (2)'), findsOneWidget);
      expect(find.text('Social Media Icon Kit'), findsNothing);
    });

    testWidgets('allows editing an existing deliverable title, description, and category', (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScreen());
      await tester.pump();

      // Run analysis
      await tester.tap(find.widgetWithText(ElevatedButton, '✧ Analyze brief'));
      await tester.pumpAndSettle();

      // Tap edit button on the first deliverable
      final editButtons = find.byTooltip('Edit deliverable');
      expect(editButtons, findsWidgets);
      await tester.tap(editButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('Edit Deliverable'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Deliverable Title *'), findsOneWidget);

      // Edit title and category
      await tester.enterText(find.widgetWithText(TextField, 'Deliverable Title *'), 'Secondary Logo Variations');
      await tester.tap(find.text('Excluded'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.text('Secondary Logo Variations'), findsOneWidget);
      expect(find.text('EXCLUDED'), findsOneWidget);
    });

    testWidgets('approves scope with empty budget preserving uninvented pricing in project record', (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
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
      // Verify budget field is NOT pre-filled with fictional price
      final budgetField = tester.widget<TextField>(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).at(2),
      );
      expect(budgetField.controller?.text, '');

      // Tap dialog confirm "Approve Scope (V1)"
      await tester.tap(find.widgetWithText(ElevatedButton, 'Approve Scope (V1)'));
      await tester.pumpAndSettle();

      // Verify callback fired
      expect(callbackFired, isTrue);

      // Verify SQLite state: budget is 0 (unstated/uninvented)
      expect(projectRepo.projects.length, 1);
      expect(projectRepo.projects.first.budget.minorUnits, 0);

      // Verify scope version approved
      expect(scopeRepo.versions.length, 1);
      final approvedScope = scopeRepo.versions.first;
      expect(approvedScope.version.status, 'approved');
      expect(approvedScope.version.versionNumber, 1);

      // Verify UI shows locked approved banner
      expect(find.textContaining('Scope Approved! Saved as immutable Version 1'), findsOneWidget);
      expect(find.text('✓ Scope Approved (V1)'), findsOneWidget);
    });

    testWidgets('cancelling analysis ignores late mock responses and prevents state overwrite', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Delayed client using Completer
      final completer = Completer<BriefCheckResult>();
      final delayedClient = DelayedFakeBriefCheckClient(completer);

      await tester.pumpWidget(buildTestScreen(client: delayedClient));
      await tester.pump();

      // Tap Analyze
      await tester.tap(find.widgetWithText(ElevatedButton, '✧ Analyze brief'));
      await tester.pump(); // Enter Loading state

      expect(find.text('Cancel Analysis'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel Analysis'));
      await tester.pumpAndSettle();

      // Verify returned to Idle
      expect(find.text('AI Requirements & Starting Scope'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, '✧ Analyze brief'), findsOneWidget);

      // Now complete the late future
      completer.complete(const BriefCheckResult(
        requestId: 'late-req-999',
        statedRequirements: ['Late deliverable'],
        assumptions: [],
        omissions: [],
        suggestedQuestions: [],
        starterScopeItems: [],
      ));
      await tester.pumpAndSettle();

      // Verify still in Idle and not overwritten by late response
      expect(find.text('AI Requirements & Starting Scope'), findsOneWidget);
      expect(find.text('Late deliverable'), findsNothing);
    });

    testWidgets('reloads approved scope from SQLite and populates intake view', (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Pre-seed an approved project and scope
      final testClient = Client(
        id: 'client-reloaded-1',
        name: 'AlphaBrand Corp',
        initials: 'AB',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      clientRepo.clients.add(testClient);

      final testProject = Project(
        id: 'proj-reloaded-1',
        clientId: testClient.id,
        name: 'AlphaBrand Identity System',
        niche: 'Design & branding',
        budget: const Money(minorUnits: 250000, currency: 'USD'),
        status: 'active',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      projectRepo.projects.add(testProject);

      final testItems = [
        const ScopeItem(
          id: 'item-1',
          scopeVersionId: 'ver-1',
          category: 'included',
          description: 'Vector Brand Identity Kit',
        ),
        const ScopeItem(
          id: 'item-2',
          scopeVersionId: 'ver-1',
          category: 'allowance',
          description: '3 Rounds of Revisions',
        ),
      ];
      final testVersion = ScopeVersion(
        id: 'ver-1',
        projectId: testProject.id,
        versionNumber: 1,
        title: 'Starting Scope',
        status: 'approved',
        approvedAt: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
      );
      scopeRepo.versions.add(ScopeVersionWithItems(version: testVersion, items: testItems));

      await tester.pumpWidget(buildTestScreen());
      await tester.pump();

      // Tap "Reload Approved Scope" in header
      final reloadBtn = find.widgetWithText(OutlinedButton, 'Reload Approved Scope');
      expect(reloadBtn, findsOneWidget);
      await tester.tap(reloadBtn);
      await tester.pumpAndSettle();

      // Dialog opens showing AlphaBrand Identity System
      expect(find.text('Reload Approved Scope'), findsWidgets);
      expect(find.text('AlphaBrand Identity System'), findsOneWidget);

      // Tap "Load Scope"
      await tester.tap(find.widgetWithText(ElevatedButton, 'Load Scope'));
      await tester.pumpAndSettle();

      // Scope is reloaded into view
      expect(find.text('✓ Scope Approved (V1)'), findsOneWidget);
      expect(find.textContaining('AlphaBrand Identity System'), findsWidgets);
      expect(find.text('Vector Brand Identity Kit'), findsOneWidget);
      expect(find.text('3 Rounds of Revisions'), findsOneWidget);
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
