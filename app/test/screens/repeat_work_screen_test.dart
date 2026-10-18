import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solodesk/db/repository_scope.dart';
import 'package:solodesk/db/preference_repository.dart';
import 'package:solodesk/db/client_repository.dart';
import 'package:solodesk/db/project_repository.dart';
import 'package:solodesk/db/scope_repository.dart';
import 'package:solodesk/db/demo_data_repository.dart';
import 'package:solodesk/models/client.dart';
import 'package:solodesk/models/service_preference.dart';
import 'package:solodesk/models/service_plan.dart';
import 'package:solodesk/models/money.dart';
import 'package:solodesk/screens/repeat_work_screen.dart';
import '../helpers/fake_invoice_repository.dart';
import '../helpers/fake_lead_repository.dart';
import '../helpers/fake_service_plan_repository.dart';
import '../helpers/fake_offer_draft_client.dart';

// Test Repo Doubles
class MockPreferenceRepo implements IPreferenceRepository {
  ServicePreference pref = ServicePreference.initial();
  @override
  Future<ServicePreference> getPreferences() async => pref;
  @override
  Future<void> savePreferences(ServicePreference preferences) async => pref = preferences;
}

class MockClientRepo implements IClientRepository {
  List<Client> clients = [];
  @override
  Future<List<Client>> getClients({bool includeSynthetic = false}) async => clients;
  @override
  Future<Client?> getClientById(String id) async =>
      clients.where((c) => c.id == id).firstOrNull;
  @override
  Future<void> createClient(Client client) async => clients.add(client);
  @override
  Future<void> updateClient(Client client) async {}
  @override
  Future<void> deleteClient(String id) async {}
}

class MockProjectRepo implements IProjectRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockScopeRepo implements IScopeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockDemoDataRepo implements IDemoDataRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('RepeatWorkScreen Widget & Flow Tests (Milestone M7)', () {
    late MockPreferenceRepo prefRepo;
    late MockClientRepo clientRepo;
    late FakeServicePlanRepository planRepo;
    late FakeOfferDraftClient offerClient;

    setUp(() {
      prefRepo = MockPreferenceRepo();
      clientRepo = MockClientRepo();
      planRepo = FakeServicePlanRepository();
      offerClient = FakeOfferDraftClient();
    });

    Widget createWidgetUnderTest({bool isSyntheticDemoActive = false}) {
      return MaterialApp(
        home: Scaffold(
          body: RepositoryScope(
            preferenceRepo: prefRepo,
            clientRepo: clientRepo,
            projectRepo: MockProjectRepo(),
            scopeRepo: MockScopeRepo(),
            demoDataRepo: MockDemoDataRepo(),
            invoiceRepo: FakeInvoiceRepository(),
            leadRepo: FakeLeadRepository(),
            servicePlanRepo: planRepo,
            child: RepeatWorkScreen(
              isSyntheticDemoActive: isSyntheticDemoActive,
              offerClient: offerClient,
            ),
          ),
        ),
      );
    }

    testWidgets('renders empty state, KPI cards, and SoloDesk Boundary Policy banner', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Screen Header
      expect(find.text('REPEAT WORK · RETAINERS & RENEWALS'), findsOneWidget);
      expect(find.text('Make the next project easier to win.'), findsOneWidget);
      expect(find.text('+ New service plan'), findsOneWidget);

      // AI Policy Banner
      expect(find.textContaining('SoloDesk Policy: Repeat-work retainers and model-assisted offers are strictly advisory drafts'), findsOneWidget);

      // KPI Metric StatCards
      expect(find.text('Active retainers'), findsOneWidget);
      expect(find.text('Monthly recurring'), findsOneWidget);
      expect(find.text('Renewals due soon'), findsOneWidget);

      // Empty State Card
      expect(find.text('Package your repeat service'), findsOneWidget);
      expect(find.text('Create service plan'), findsOneWidget);
    });

    testWidgets('renders seeded service plans with cadence badge, price, deliverables chips', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      final now = DateTime.now().toUtc();

      planRepo.seedPlans([
        ServicePlan(
          id: 'p-seed-1',
          title: 'Brand Growth Retainer',
          serviceNiche: 'Design & branding',
          cadence: PlanCadence.monthly,
          price: const Money(minorUnits: 25000000, currency: 'NGN'),
          deliverables: const ['4 Social media graphics', '1 Collateral refresh'],
          exclusions: const ['Custom 3D modeling'],
          revisionLimit: '2 rounds per deliverable',
          status: PlanStatus.active,
          renewalDate: DateTime(2026, 11, 1),
          createdAt: now,
          updatedAt: now,
        ),
      ]);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Plan Title
      expect(find.text('Brand Growth Retainer'), findsOneWidget);

      // Deliverables & Exclusions
      expect(find.textContaining('4 Social media graphics · 1 Collateral refresh'), findsOneWidget);
      expect(find.text('Limits: 2 rounds per deliverable'), findsOneWidget);

      // Action Button on Plan Card
      expect(find.text('Draft renewal ↗'), findsOneWidget);
    });

    testWidgets('creates a new service plan via modal dialog and updates grid', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Click "+ New service plan" button
      final addBtn = find.text('+ New service plan');
      expect(addBtn, findsOneWidget);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // Modal Dialog should be visible
      expect(find.text('New Service Plan'), findsOneWidget);

      // Fill in Title
      final titleField = find.widgetWithText(TextFormField, 'e.g. Monthly Content Package');
      await tester.enterText(titleField, 'Technical Writing Retainer');

      // Fill in Price
      final priceField = find.widgetWithText(TextFormField, 'e.g. 150000');
      await tester.enterText(priceField, '1500');

      // Fill in Deliverables (required)
      final delivField = find.widgetWithText(TextFormField, '• 4 Blog articles\n• 2 Newsletters');
      await tester.enterText(delivField, 'Monthly API Documentation');

      // Click Save Plan
      final saveBtn = find.text('Save Plan');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify plan is in repository and rendered on screen
      expect(planRepo.plans.length, equals(1));
      expect(planRepo.plans.first.title, equals('Technical Writing Retainer'));
      expect(find.text('Technical Writing Retainer'), findsOneWidget);
    });

    testWidgets('drafting studio populates facts, calls model service, and displays editable output', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1400));
      final now = DateTime.now().toUtc();

      planRepo.seedPlans([
        ServicePlan(
          id: 'plan-studio-1',
          title: 'Quarterly SEO Retainer',
          serviceNiche: 'Writing & content',
          cadence: PlanCadence.quarterly,
          price: const Money(minorUnits: 300000, currency: 'USD'),
          deliverables: const ['4 Pillar Articles', 'Technical SEO Audit'],
          exclusions: const ['Net-new web development'],
          revisionLimit: '1 round of edits',
          status: PlanStatus.active,
          createdAt: now,
          updatedAt: now,
        ),
      ]);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Click "Draft renewal ↗" on the card to populate the studio
      await tester.tap(find.text('Draft renewal ↗'));
      await tester.pumpAndSettle();

      // Scroll down to reveal the drafting studio
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Draft a new recurring offer'), findsOneWidget);

      // Select Value-focused tone
      await tester.tap(find.text('Value & growth focused'));
      await tester.pumpAndSettle();

      // Click "Generate offer draft"
      final draftBtn = find.text('Generate offer draft');
      expect(draftBtn, findsOneWidget);
      await tester.tap(draftBtn);
      await tester.pumpAndSettle();

      // Verify output is displayed
      final previewText = find.textContaining('I would love to propose our ongoing Quarterly SEO Retainer');
      expect(previewText, findsOneWidget);

      // Copy offer button is present and clickable
      final copyBtn = find.text('Copy offer');
      expect(copyBtn, findsOneWidget);
      await tester.tap(copyBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Offer copied to clipboard.'), findsOneWidget);
    });
  });
}
