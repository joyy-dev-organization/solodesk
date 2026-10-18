import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solodesk/db/repository_scope.dart';
import 'package:solodesk/db/preference_repository.dart';
import 'package:solodesk/db/client_repository.dart';
import 'package:solodesk/db/project_repository.dart';
import 'package:solodesk/db/scope_repository.dart';
import 'package:solodesk/db/demo_data_repository.dart';
import 'package:solodesk/models/client.dart';
import 'package:solodesk/models/lead.dart';
import 'package:solodesk/models/money.dart';
import 'package:solodesk/models/service_preference.dart';
import 'package:solodesk/screens/lead_loop_screen.dart';
import '../helpers/fake_lead_repository.dart';
import '../helpers/fake_invoice_repository.dart';

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
  Future<Client?> getClientById(String id) async => null;
  @override
  Future<Client> createClient(Client client) async => client;
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
  group('LeadLoopScreen Widget & Flow Tests', () {
    late MockPreferenceRepo prefRepo;
    late MockClientRepo clientRepo;
    late FakeLeadRepository leadRepo;
    late FakeInvoiceRepository invoiceRepo;

    setUp(() {
      prefRepo = MockPreferenceRepo();
      clientRepo = MockClientRepo();
      leadRepo = FakeLeadRepository();
      invoiceRepo = FakeInvoiceRepository();
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
            invoiceRepo: invoiceRepo,
            leadRepo: leadRepo,
            child: LeadLoopScreen(
              isSyntheticDemoActive: isSyntheticDemoActive,
            ),
          ),
        ),
      );
    }

    testWidgets('renders empty state and SoloDesk Boundary Policy Banner', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('LeadLoop ✦'), findsOneWidget);
      expect(find.text('PROSPECT PIPELINE · LOCAL PLANNING ONLY'), findsOneWidget);
      expect(find.textContaining('SoloDesk Boundary Policy'), findsOneWidget);
      expect(find.text('No leads in your pipeline yet'), findsOneWidget);
      expect(find.text('Add your first lead'), findsOneWidget);
      expect(find.text('Open leads'), findsOneWidget);
      expect(find.text('Follow-ups due'), findsOneWidget);
      expect(find.text('Quoted pipeline'), findsOneWidget);
      expect(find.text('Won deals'), findsOneWidget);
    });

    testWidgets('renders seeded leads with contact name, company, stage chip, and urgency badge', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      final now = DateTime.now().toUtc();

      leadRepo.seedLeads([
        Lead(
          id: 'lead-1',
          contactName: 'Amina Musa',
          company: 'Musa Brand Lab',
          serviceNiche: 'Design & branding',
          stage: LeadStage.proposalSent,
          estimatedValue: const Money(minorUnits: 22000000, currency: 'NGN'),
          nextFollowUpDate: DateTime(2026, 10, 18), // Today
          notes: 'Packaging quote delivered.',
          isSynthetic: false,
          createdAt: now,
          updatedAt: now,
        ),
        Lead(
          id: 'lead-2',
          contactName: 'Coach Tunde',
          company: 'FitPath Coaching',
          serviceNiche: 'Consulting & coaching',
          stage: LeadStage.inDiscussion,
          estimatedValue: const Money(minorUnits: 35000000, currency: 'NGN'),
          nextFollowUpDate: DateTime(2026, 10, 15), // Overdue
          isSynthetic: true,
          createdAt: now,
          updatedAt: now,
        ),
      ]);

      await tester.pumpWidget(createWidgetUnderTest(isSyntheticDemoActive: true));
      await tester.pumpAndSettle();

      expect(find.text('Amina Musa (Musa Brand Lab)'), findsOneWidget);
      expect(find.text('Coach Tunde (FitPath Coaching)'), findsOneWidget);
      expect(find.text('DEMO RECORD'), findsOneWidget);
      expect(find.text('Proposal sent'), findsWidgets);
      expect(find.text('In discussion'), findsWidgets);
      expect(find.textContaining('₦220,000.00'), findsWidgets);
    });

    testWidgets('Add Lead Dialog validates required contact name and decimal precision', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Open Add Lead Dialog
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Lead'));
      await tester.pumpAndSettle();

      expect(find.text('Add Prospective Lead'), findsOneWidget);

      // Attempt submit without name
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Lead'));
      await tester.pumpAndSettle();

      expect(find.text('Contact name is required'), findsOneWidget);

      // Enter contact name
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contact / Prospect Name *'),
        'Grace Hopper',
      );

      // Enter invalid precision (>2 decimal places)
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quoted / Estimated Value (Optional)'),
        '150.999',
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Lead'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid non-negative amount (max 2 decimals)'), findsOneWidget);

      // Correct amount
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quoted / Estimated Value (Optional)'),
        '150.50',
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Lead'));
      await tester.pumpAndSettle();

      // Dialog should close and lead should appear
      expect(find.text('Add Prospective Lead'), findsNothing);
      expect(find.text('Grace Hopper'), findsOneWidget);
      expect(leadRepo.leads.length, equals(1));
      expect(leadRepo.leads.first.contactName, equals('Grace Hopper'));
      expect(leadRepo.leads.first.estimatedValue?.minorUnits, equals(15050));
    });

    testWidgets('Follow-up Draft Modal displays editable draft and boundary policy', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      final now = DateTime.now().toUtc();

      leadRepo.seedLeads([
        Lead(
          id: 'lead-draft-1',
          contactName: 'Tola James',
          serviceNiche: 'Writing & content',
          stage: LeadStage.discovery,
          isSynthetic: false,
          createdAt: now,
          updatedAt: now,
        ),
      ]);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Click Draft Follow-up button
      await tester.tap(find.widgetWithText(TextButton, 'Draft Follow-up'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Draft Follow-up · Tola James'), findsOneWidget);
      expect(find.textContaining('SoloDesk Boundary Policy: Review and edit this draft before sending'), findsOneWidget);
      expect(find.textContaining('Hi Tola, I hope you\'re having a productive week.'), findsOneWidget);
      expect(find.text('Copy to Clipboard'), findsOneWidget);

      // Close modal
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Draft Follow-up · Tola James'), findsNothing);
    });

    testWidgets('Advance Stage button progresses stage forward', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      final now = DateTime.now().toUtc();

      leadRepo.seedLeads([
        Lead(
          id: 'lead-adv-1',
          contactName: 'Ngozi Okonjo',
          serviceNiche: 'Consulting & coaching',
          stage: LeadStage.discovery,
          isSynthetic: false,
          createdAt: now,
          updatedAt: now,
        ),
      ]);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(leadRepo.leads.first.stage, equals(LeadStage.discovery));

      // Tap Advance Stage
      await tester.tap(find.widgetWithText(OutlinedButton, 'Advance Stage'));
      await tester.pumpAndSettle();

      expect(leadRepo.leads.first.stage, equals(LeadStage.proposalSent));
    });

    testWidgets('Add lead dialog opens successfully with non-standard preference currency (e.g. KES)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      prefRepo.pref = prefRepo.pref.copyWith(defaultCurrency: 'KES');

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tap Add Lead
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Lead'));
      await tester.pumpAndSettle();

      // Verify dialog renders cleanly without assertion crash
      expect(find.text('Add Prospective Lead'), findsOneWidget);
      expect(find.text('KES (KSh)'), findsOneWidget);

      // Verify saving lead with KES works
      await tester.enterText(find.widgetWithText(TextFormField, 'Contact / Prospect Name *'), 'Savannah Studios');
      await tester.enterText(find.widgetWithText(TextFormField, 'Quoted / Estimated Value (Optional)'), '75000');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Lead'));
      await tester.pumpAndSettle();

      expect(leadRepo.leads.length, equals(1));
      expect(leadRepo.leads.first.contactName, equals('Savannah Studios'));
      expect(leadRepo.leads.first.estimatedValue?.currency, equals('KES'));
      expect(leadRepo.leads.first.estimatedValue?.minorUnits, equals(7500000));
    });
  });
}
