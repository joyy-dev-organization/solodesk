import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solodesk/db/repository_scope.dart';
import 'package:solodesk/db/client_repository.dart';
import 'package:solodesk/db/project_repository.dart';
import 'package:solodesk/db/scope_repository.dart';
import 'package:solodesk/db/preference_repository.dart';
import 'package:solodesk/db/demo_data_repository.dart';
import 'package:solodesk/models/client.dart';
import 'package:solodesk/models/money.dart';
import 'package:solodesk/models/project.dart';
import 'package:solodesk/models/scope_check_models.dart';
import 'package:solodesk/models/scope_version.dart';
import 'package:solodesk/models/scope_item.dart';
import 'package:solodesk/models/service_preference.dart';
import 'package:solodesk/screens/scope_shield_screen.dart';
import 'package:solodesk/services/scope_check_client.dart';
import 'package:solodesk/services/scope_check_exceptions.dart';

class FakeScopeCheckClient extends ScopeCheckClient {
  ScopeCheckResult? stubResult;
  Exception? errorToThrow;

  FakeScopeCheckClient({this.stubResult, this.errorToThrow})
      : super(host: '127.0.0.1', port: 3141);

  @override
  Future<ScopeCheckResult> checkScope({
    required String requestText,
    required String scopeVersionId,
    required List<ScopeItem> scopeItems,
    String niche = 'general',
  }) async {
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return stubResult ??
        ScopeCheckResult(
          requestId: 'test-scope-req-123',
          summary: 'Analyzed 2 request item(s): 1 included, 1 out of scope.',
          findings: const [
            ScopeFinding(
              classification: ScopeClassification.included,
              requestExcerpt: 'tweak the green shade',
              matchedScopeItemId: 'item-1',
              matchedScopeItemDescription: 'Primary Logo Design (2 revision rounds)',
              explanation: 'Color adjustment is covered within agreed revision rounds.',
            ),
            ScopeFinding(
              classification: ScopeClassification.potentiallyOutside,
              requestExcerpt: 'add a custom mobile app in Flutter',
              matchedScopeItemId: null,
              matchedScopeItemDescription: 'No matching scope deliverable found in approved agreement',
              explanation: 'Custom software development is not part of this brand design scope.',
            ),
          ],
          replyDraft: 'Hi! I can gladly adjust the green shade as part of our agreed revision round. For the Flutter mobile app, that would be an extra deliverable which I can quote separately.',
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
  Future<ScopeVersionWithItems?> getLatestApprovedVersion(String projectId) async {
    final matches = versions.where((v) => v.version.projectId == projectId && v.version.isApproved).toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) => b.version.versionNumber.compareTo(a.version.versionNumber));
    return matches.first;
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
      id: 'version-${versions.length + 1}',
      projectId: projectId,
      versionNumber: versions.length + 1,
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
    final approvedVersion = existing.version.copyWith(
      status: 'approved',
      approvedAt: DateTime.now().toUtc(),
    );
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
    final idx = versions.indexWhere((v) => v.version.id == approvedVersionId);
    final existing = versions[idx];
    final newVersion = ScopeVersion(
      id: 'version-${versions.length + 1}',
      projectId: existing.version.projectId,
      versionNumber: existing.version.versionNumber + 1,
      title: newTitle,
      status: 'draft',
      notes: notes,
      isSynthetic: false,
      createdAt: DateTime.now().toUtc(),
    );
    final clonedItems = existing.items
        .map((i) => ScopeItem(
              id: 'item-rev-${i.id}',
              scopeVersionId: newVersion.id,
              category: i.category,
              description: i.description,
              sortOrder: i.sortOrder,
            ))
        .toList();
    final res = ScopeVersionWithItems(version: newVersion, items: clonedItems);
    versions.add(res);
    return res;
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
  late TestClientRepo clientRepo;
  late TestProjectRepo projectRepo;
  late TestScopeRepo scopeRepo;
  late TestPreferenceRepo prefRepo;
  late TestDemoDataRepo demoRepo;

  setUp(() {
    clientRepo = TestClientRepo();
    projectRepo = TestProjectRepo();
    scopeRepo = TestScopeRepo();
    prefRepo = TestPreferenceRepo();
    demoRepo = TestDemoDataRepo();
  });

  Widget buildTestScreen({ScopeCheckClient? client}) {
    return RepositoryScope(
      clientRepo: clientRepo,
      projectRepo: projectRepo,
      scopeRepo: scopeRepo,
      preferenceRepo: prefRepo,
      demoDataRepo: demoRepo,
      child: MaterialApp(
        home: Scaffold(
          body: ScopeShieldScreen(
            isSyntheticDemoActive: false,
            client: client ?? FakeScopeCheckClient(),
          ),
        ),
      ),
    );
  }

  group('Milestone M4: ScopeShieldScreen Widget Tests', () {
    testWidgets('renders empty state when no approved projects exist', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      expect(find.text('No saved project scopes to evaluate'), findsOneWidget);
      expect(find.text('Approve a scope in BriefCheck or toggle "Load Demo Data" to test ScopeShield.'), findsOneWidget);
      expect(find.text('Go to BriefCheck'), findsOneWidget);
    });

    testWidgets('renders project selector, approved deliverables, and quick sample buttons when approved scope exists', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.now().toUtc();
      final client = Client(id: 'client-1', name: 'Apex Labs', initials: 'AL', createdAt: now, updatedAt: now);
      clientRepo.clients.add(client);

      final project = Project(
        id: 'proj-1',
        clientId: client.id,
        name: 'Apex Brand Identity',
        niche: 'design',
        budget: const Money(minorUnits: 250000, currency: 'USD'),
        status: 'active',
        createdAt: now,
        updatedAt: now,
      );
      projectRepo.projects.add(project);

      final approvedVersion = ScopeVersion(
        id: 'ver-1',
        projectId: project.id,
        versionNumber: 1,
        title: 'V1 Initial Scope',
        status: 'approved',
        approvedAt: now,
        isSynthetic: false,
        createdAt: now,
      );
      final items = [
        const ScopeItem(id: 'i-1', scopeVersionId: 'ver-1', category: 'included', description: 'Vector master logo pack', sortOrder: 0),
        const ScopeItem(id: 'i-2', scopeVersionId: 'ver-1', category: 'allowance', description: '2 rounds of typographic adjustments', sortOrder: 1),
        const ScopeItem(id: 'i-3', scopeVersionId: 'ver-1', category: 'excluded', description: 'Custom mobile application software', sortOrder: 2),
      ];
      scopeRepo.versions.add(ScopeVersionWithItems(version: approvedVersion, items: items));

      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Project header and deliverable chips
      expect(find.textContaining('Apex Brand Identity'), findsWidgets);
      expect(find.text('Project agreement'), findsOneWidget);
      expect(find.textContaining('Vector master logo pack'), findsOneWidget);
      expect(find.textContaining('2 rounds of typographic adjustments'), findsOneWidget);
      expect(find.textContaining('Custom mobile application software'), findsOneWidget);

      // Quick sample buttons
      expect(find.text('Load Included Request'), findsOneWidget);
      expect(find.text('Load Scope Creep Request'), findsOneWidget);
      expect(find.text('Load Mixed Request'), findsOneWidget);
      expect(find.text('Load Ambiguous Request'), findsOneWidget);
      expect(find.text('⛨ Compare with agreed scope'), findsOneWidget);
    });

    testWidgets('clicking quick sample button updates client request text', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.now().toUtc();
      final project = Project(
        id: 'proj-1',
        clientId: 'c-1',
        name: 'Apex Brand Identity',
        niche: 'design',
        budget: const Money(minorUnits: 250000, currency: 'USD'),
        status: 'active',
        createdAt: now,
        updatedAt: now,
      );
      projectRepo.projects.add(project);
      final approvedVersion = ScopeVersion(
        id: 'ver-1',
        projectId: project.id,
        versionNumber: 1,
        title: 'V1 Initial Scope',
        status: 'approved',
        approvedAt: now,
        isSynthetic: false,
        createdAt: now,
      );
      scopeRepo.versions.add(ScopeVersionWithItems(version: approvedVersion, items: const [
        ScopeItem(id: 'i-1', scopeVersionId: 'ver-1', category: 'included', description: 'Logo Pack', sortOrder: 0),
      ]));

      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Tap 'Load Scope Creep Request'
      await tester.tap(find.text('Load Scope Creep Request'));
      await tester.pump();

      expect(find.textContaining('Can we also add a Stripe checkout'), findsOneWidget);
    });

    testWidgets('executes scope check comparison and renders itemized findings and editable reply draft', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.now().toUtc();
      final project = Project(
        id: 'proj-1',
        clientId: 'c-1',
        name: 'Apex Brand Identity',
        niche: 'design',
        budget: const Money(minorUnits: 250000, currency: 'USD'),
        status: 'active',
        createdAt: now,
        updatedAt: now,
      );
      projectRepo.projects.add(project);
      final approvedVersion = ScopeVersion(
        id: 'ver-1',
        projectId: project.id,
        versionNumber: 1,
        title: 'V1 Initial Scope',
        status: 'approved',
        approvedAt: now,
        isSynthetic: false,
        createdAt: now,
      );
      scopeRepo.versions.add(ScopeVersionWithItems(version: approvedVersion, items: const [
        ScopeItem(id: 'item-1', scopeVersionId: 'ver-1', category: 'included', description: 'Primary Logo Design (2 revision rounds)', sortOrder: 0),
      ]));

      final fakeClient = FakeScopeCheckClient();
      await tester.pumpWidget(buildTestScreen(client: fakeClient));
      await tester.pumpAndSettle();

      // Run comparison
      final compareBtn = find.text('⛨ Compare with agreed scope');
      expect(compareBtn, findsOneWidget);
      await tester.tap(compareBtn);
      await tester.pumpAndSettle();

      // Results panel
      expect(find.text('Scope Comparison Results'), findsOneWidget);
      expect(find.text('INCLUDED'), findsWidgets);
      expect(find.text('OUT OF SCOPE'), findsWidgets);
      expect(find.text('“tweak the green shade”'), findsOneWidget);
      expect(find.text('“add a custom mobile app in Flutter”'), findsOneWidget);
      expect(find.text('Color adjustment is covered within agreed revision rounds.'), findsOneWidget);
      expect(find.text('Custom software development is not part of this brand design scope.'), findsOneWidget);

      // Reply draft
      expect(find.text('Suggested Response Draft (Editable)'), findsOneWidget);
      expect(find.textContaining('I can gladly adjust the green shade'), findsOneWidget);
      expect(find.text('▣ Copy suggested reply'), findsOneWidget);
      expect(find.text('SoloDesk Boundary Policy: Nothing is sent, charged, or added to approved scope automatically. Review before sending to your client.'), findsOneWidget);
    });

    testWidgets('allows editing reply draft and copying to clipboard', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.now().toUtc();
      final project = Project(
        id: 'proj-1',
        clientId: 'c-1',
        name: 'Apex Brand Identity',
        niche: 'design',
        budget: const Money(minorUnits: 250000, currency: 'USD'),
        status: 'active',
        createdAt: now,
        updatedAt: now,
      );
      projectRepo.projects.add(project);
      final approvedVersion = ScopeVersion(
        id: 'ver-1',
        projectId: project.id,
        versionNumber: 1,
        title: 'V1 Initial Scope',
        status: 'approved',
        approvedAt: now,
        isSynthetic: false,
        createdAt: now,
      );
      scopeRepo.versions.add(ScopeVersionWithItems(version: approvedVersion, items: const [
        ScopeItem(id: 'item-1', scopeVersionId: 'ver-1', category: 'included', description: 'Logo', sortOrder: 0),
      ]));

      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Run comparison
      await tester.tap(find.text('⛨ Compare with agreed scope'));
      await tester.pumpAndSettle();

      // Tap Copy Draft Reply
      final copyBtn = find.text('▣ Copy suggested reply');
      expect(copyBtn, findsOneWidget);
      await tester.tap(copyBtn);
      await tester.pump();

      // Verifies copy snackbar
      expect(find.text('Reply copied to clipboard! Ready to paste into email or messaging app.'), findsOneWidget);
    });

    testWidgets('zero-loss error handling preserves client request text and allows retry', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.now().toUtc();
      final project = Project(
        id: 'proj-1',
        clientId: 'c-1',
        name: 'Apex Brand Identity',
        niche: 'design',
        budget: const Money(minorUnits: 250000, currency: 'USD'),
        status: 'active',
        createdAt: now,
        updatedAt: now,
      );
      projectRepo.projects.add(project);
      final approvedVersion = ScopeVersion(
        id: 'ver-1',
        projectId: project.id,
        versionNumber: 1,
        title: 'V1 Initial Scope',
        status: 'approved',
        approvedAt: now,
        isSynthetic: false,
        createdAt: now,
      );
      scopeRepo.versions.add(ScopeVersionWithItems(version: approvedVersion, items: const [
        ScopeItem(id: 'item-1', scopeVersionId: 'ver-1', category: 'included', description: 'Logo', sortOrder: 0),
      ]));

      final failingClient = FakeScopeCheckClient(
        errorToThrow: ScopeCheckModelOfflineException(
          'Ollama is offline or unreachable at 127.0.0.1:11434',
        ),
      );

      await tester.pumpWidget(buildTestScreen(client: failingClient));
      await tester.pumpAndSettle();

      // Enter unique request text
      const customRequest = 'Can you build a high-priority eCommerce portal for tomorrow morning?';
      final requestField = find.byType(TextField).first;
      await tester.enterText(requestField, customRequest);
      await tester.pump();

      // Run comparison which fails
      await tester.tap(find.text('⛨ Compare with agreed scope'));
      await tester.pumpAndSettle();

      // Error panel is shown
      expect(find.text('Scope Evaluation Failed'), findsOneWidget);
      expect(find.text('MODEL_OFFLINE'), findsOneWidget);
      expect(find.textContaining('Ollama is offline'), findsOneWidget);
      expect(find.text('Retry Comparison'), findsOneWidget);

      // Client request text is PRESERVED (Zero-loss guarantee)
      expect(find.text(customRequest), findsOneWidget);
    });
  });
}
