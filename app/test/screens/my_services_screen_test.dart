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
import 'package:solodesk/models/scope_version.dart';
import 'package:solodesk/models/scope_item.dart';
import 'package:solodesk/models/service_preference.dart';
import 'package:solodesk/screens/my_services_screen.dart';
import '../helpers/fake_invoice_repository.dart';

class TestClientRepo implements IClientRepository {
  @override
  Future<List<Client>> getClients({bool includeSynthetic = true}) async => const [];
  @override
  Future<Client?> getClientById(String id) async => null;
  @override
  Future<void> createClient(Client client) async {}
  @override
  Future<void> updateClient(Client client) async {}
  @override
  Future<void> deleteClient(String id) async {}
}

class TestProjectRepo implements IProjectRepository {
  @override
  Future<List<Project>> getProjects({String? clientId, bool includeSynthetic = true}) async => const [];
  @override
  Future<Project?> getProjectById(String id) async => null;
  @override
  Future<void> createProject(Project project) async {}
  @override
  Future<void> updateProject(Project project) async {}
  @override
  Future<void> deleteProject(String id) async {}
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
  @override
  Future<bool> hasSyntheticData() async => false;
  @override
  Future<void> seedSyntheticData() async {}
  @override
  Future<void> purgeSyntheticData() async {}
  @override
  Future<OverviewMetrics> getMetrics({bool includeSynthetic = false}) async =>
      const OverviewMetrics(totalClients: 0, activeProjects: 0, approvedScopes: 0, pendingDrafts: 0, unpaidInvoices: 0);
}

void main() {
  group('MyServicesScreen Widget & Preferences Persistence Tests', () {
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

    Widget createWidgetUnderTest({VoidCallback? onSaved}) {
      return MaterialApp(
        home: Scaffold(
          body: RepositoryScope(
            preferenceRepo: preferenceRepo,
            clientRepo: clientRepo,
            projectRepo: projectRepo,
            scopeRepo: scopeRepo,
            demoDataRepo: demoDataRepo,
            invoiceRepo: invoiceRepo,
            child: MyServicesScreen(onSaved: onSaved),
          ),
        ),
      );
    }

    testWidgets('renders initial preferences with ladydiamond business profile', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('PERSONALIZATION'), findsOneWidget);
      expect(find.text('Make SoloDesk fit the work you do.'), findsOneWidget);
      expect(find.text('Design & branding'), findsWidgets);
      expect(find.text('Writing & content'), findsWidgets);
      expect(find.text('ladydiamond · Independent freelancer'), findsOneWidget);
    });

    testWidgets('toggling service niches updates selected niches and saves to repository', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      bool savedCalled = false;
      await tester.pumpWidget(createWidgetUnderTest(onSaved: () => savedCalled = true));
      await tester.pumpAndSettle();

      // Tap 'Software & development' filter chip
      final devChip = find.widgetWithText(FilterChip, 'Software & development');
      expect(devChip, findsOneWidget);
      await tester.tap(devChip);
      await tester.pumpAndSettle();

      // Tap 'Save preferences'
      final saveBtn = find.text('Save preferences');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(savedCalled, isTrue);
      expect(preferenceRepo.pref.niches.contains('Software & development'), isTrue);
      expect(find.textContaining('Saved 3 service categories and NGN currency to local database.'), findsOneWidget);
    });

    testWidgets('adding custom niche via Other textfield persists custom category', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tap 'Other' filter chip
      final otherChip = find.widgetWithText(FilterChip, 'Other');
      expect(otherChip, findsOneWidget);
      await tester.tap(otherChip);
      await tester.pumpAndSettle();

      // Custom category text field should appear
      final customNicheField = find.widgetWithText(TextField, 'Custom service category');
      expect(customNicheField, findsOneWidget);
      await tester.enterText(customNicheField, 'Podcast Audio Mastering');
      await tester.pumpAndSettle();

      // Tap 'Save preferences'
      final saveBtn = find.text('Save preferences');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(preferenceRepo.pref.niches.contains('Podcast Audio Mastering'), isTrue);
    });

    testWidgets('changing currency persists selected currency', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tap currency dropdown
      final currencyDropdown = find.text('NGN — Nigerian naira (₦)');
      expect(currencyDropdown, findsOneWidget);
      await tester.tap(currencyDropdown);
      await tester.pumpAndSettle();

      // Select EUR
      final eurItem = find.text('EUR — Euro (€)').last;
      await tester.tap(eurItem);
      await tester.pumpAndSettle();

      // Tap 'Save preferences'
      final saveBtn = find.text('Save preferences');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(preferenceRepo.pref.defaultCurrency, 'EUR');
    });
  });
}
