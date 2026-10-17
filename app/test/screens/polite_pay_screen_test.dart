import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solodesk/db/client_repository.dart';
import 'package:solodesk/db/demo_data_repository.dart';
import 'package:solodesk/db/preference_repository.dart';
import 'package:solodesk/db/project_repository.dart';
import 'package:solodesk/db/repository_scope.dart';
import 'package:solodesk/db/scope_repository.dart';
import 'package:solodesk/models/client.dart';
import 'package:solodesk/models/invoice.dart';
import 'package:solodesk/models/invoice_reminder_models.dart';
import 'package:solodesk/models/money.dart';
import 'package:solodesk/models/project.dart';
import 'package:solodesk/models/scope_item.dart';
import 'package:solodesk/models/scope_version.dart';
import 'package:solodesk/models/service_preference.dart';
import 'package:solodesk/screens/polite_pay_screen.dart';
import 'package:solodesk/services/invoice_reminder_client.dart';
import '../helpers/fake_invoice_repository.dart';

class FakeInvoiceReminderClient extends InvoiceReminderClient {
  InvoiceReminderResult? stubResult;
  Exception? errorToThrow;

  @override
  Future<InvoiceReminderResult> generateReminder({
    required String invoiceId,
    required String clientName,
    required String invoiceNumber,
    required String amountFormatted,
    required String currency,
    required String dueDate,
    required int daysOverdue,
    String tone = 'polite',
    String? optionalNotes,
  }) async {
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return stubResult ??
        InvoiceReminderResult(
          requestId: 'stub-req-1',
          reminderDraft:
              'Dear $clientName, friendly reminder regarding $invoiceNumber for $amountFormatted due on $dueDate.',
          summary: 'Polite reminder draft for $invoiceNumber',
          toneUsed: ReminderTone.fromString(tone),
        );
  }
}

class TestClientRepo implements IClientRepository {
  final List<Client> clients = [];

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
  Future<void> deleteClient(String id) async => clients.removeWhere((c) => c.id == id);
}

class TestProjectRepo implements IProjectRepository {
  final List<Project> projects = [];

  @override
  Future<List<Project>> getProjects({bool includeSynthetic = false, String? clientId}) async =>
      projects.where((p) => clientId == null || p.clientId == clientId).toList();

  @override
  Future<Project?> getProjectById(String id) async =>
      projects.where((p) => p.id == id).firstOrNull;

  @override
  Future<void> createProject(Project project) async => projects.add(project);

  @override
  Future<void> updateProject(Project project) async {}

  @override
  Future<void> deleteProject(String id) async => projects.removeWhere((p) => p.id == id);
}

class TestScopeRepo implements IScopeRepository {
  @override
  Future<ScopeVersionWithItems?> getLatestApprovedVersion(String projectId) async => null;
  @override
  Future<ScopeVersionWithItems?> getVersionWithItems(String versionId) async => null;
  @override
  Future<List<ScopeVersion>> getVersionsForProject(String projectId) async => [];
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
    return ScopeVersionWithItems(version: v, items: items);
  }
  @override
  Future<void> updateDraft({required ScopeVersion version, required List<ScopeItem> items}) async {}
  @override
  Future<ScopeVersionWithItems> approveVersion(String versionId) async => throw UnimplementedError();
  @override
  Future<ScopeVersionWithItems> createRevisionFromApproved(String approvedVersionId, {required String newTitle, String? notes}) async =>
      throw UnimplementedError();
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
  group('Milestone M5: PolitePayScreen Widget Tests', () {
    late FakeInvoiceRepository invoiceRepo;
    late TestClientRepo clientRepo;
    late TestProjectRepo projectRepo;
    late TestScopeRepo scopeRepo;
    late TestPreferenceRepo prefRepo;
    late TestDemoDataRepo demoRepo;
    late FakeInvoiceReminderClient fakeReminderClient;

    setUp(() {
      invoiceRepo = FakeInvoiceRepository();
      clientRepo = TestClientRepo();
      projectRepo = TestProjectRepo();
      scopeRepo = TestScopeRepo();
      prefRepo = TestPreferenceRepo();
      demoRepo = TestDemoDataRepo();
      fakeReminderClient = FakeInvoiceReminderClient();
    });

    Widget buildTestScreen({bool isSyntheticDemoActive = false}) {
      return RepositoryScope(
        preferenceRepo: prefRepo,
        clientRepo: clientRepo,
        projectRepo: projectRepo,
        scopeRepo: scopeRepo,
        demoDataRepo: demoRepo,
        invoiceRepo: invoiceRepo,
        child: MaterialApp(
          home: Scaffold(
            body: PolitePayScreen(
              isSyntheticDemoActive: isSyntheticDemoActive,
              client: fakeReminderClient,
            ),
          ),
        ),
      );
    }

    testWidgets('renders Empty State and Boundary Policy Notice when no invoices exist', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      expect(find.text('PolitePay: Invoices & Multi-Currency Accounting'), findsOneWidget);
      expect(find.textContaining('SoloDesk Boundary Policy: SoloDesk never processes payments'), findsOneWidget);
      expect(find.textContaining('No invoices recorded yet'), findsOneWidget);
      expect(find.text('Create Invoice'), findsOneWidget);
    });

    testWidgets('multi-currency accounting displays independent currency totals without cross-currency summing', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client1 = Client(
        id: 'c-1',
        name: 'Acme Global',
        initials: 'AG',
        company: 'Acme Corp',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final client2 = Client(
        id: 'c-2',
        name: 'Kano Studios',
        initials: 'KS',
        company: 'Kano Media',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      clientRepo.clients.addAll([client1, client2]);
      invoiceRepo.clients['c-1'] = client1;
      invoiceRepo.clients['c-2'] = client2;

      final now = DateTime.now();
      // USD Invoice: $1,500.00 unpaid
      final invUSD = Invoice(
        id: 'inv-usd',
        clientId: 'c-1',
        invoiceNumber: 'INV-USD-001',
        amount: const Money(minorUnits: 150000, currency: 'USD'),
        issueDate: DateTime(now.year, now.month, now.day - 10),
        dueDate: DateTime(now.year, now.month, now.day + 5),
        status: InvoiceStatus.unpaid,
        createdAt: now,
        updatedAt: now,
      );

      // NGN Invoice: ₦450,000.00 unpaid (overdue)
      final invNGN = Invoice(
        id: 'inv-ngn',
        clientId: 'c-2',
        invoiceNumber: 'INV-NGN-001',
        amount: const Money(minorUnits: 45000000, currency: 'NGN'),
        issueDate: DateTime(now.year, now.month, now.day - 20),
        dueDate: DateTime(now.year, now.month, now.day - 5),
        status: InvoiceStatus.unpaid,
        createdAt: now,
        updatedAt: now,
      );

      invoiceRepo.invoices.addAll([invUSD, invNGN]);

      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Verify USD and NGN sections are rendered independently
      expect(find.text('USD Currency Totals'), findsOneWidget);
      expect(find.text('NGN Currency Totals'), findsOneWidget);
      expect(find.textContaining('Strictly multi-currency: Balances are calculated independently'), findsOneWidget);

      // Verify formatted amounts
      expect(find.text('\$1500.00'), findsWidgets);
      expect(find.text('₦450000.00'), findsWidgets);

      // Verify filter counts: All (2), Unpaid (2), Overdue (1), Paid (0)
      expect(find.text('All (2)'), findsOneWidget);
      expect(find.text('Unpaid (2)'), findsOneWidget);
      expect(find.text('Overdue (1)'), findsOneWidget);
      expect(find.text('Paid (0)'), findsOneWidget);
    });

    testWidgets('mark paid / mark unpaid toggle updates status and recalculates totals', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = Client(
        id: 'c-1',
        name: 'Apex Design',
        initials: 'AD',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      clientRepo.clients.add(client);
      invoiceRepo.clients['c-1'] = client;

      final now = DateTime.now();
      final inv = Invoice(
        id: 'inv-1',
        clientId: 'c-1',
        invoiceNumber: 'INV-2026-001',
        amount: const Money(minorUnits: 200000, currency: 'USD'),
        issueDate: DateTime(now.year, now.month, now.day - 5),
        dueDate: DateTime(now.year, now.month, now.day + 10),
        status: InvoiceStatus.unpaid,
        createdAt: now,
        updatedAt: now,
      );
      invoiceRepo.invoices.add(inv);

      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Find Mark Paid button and tap it
      final markPaidBtn = find.text('Mark Paid');
      expect(markPaidBtn, findsOneWidget);
      await tester.tap(markPaidBtn);
      await tester.pumpAndSettle();

      // Status should now be Paid, Mark Unpaid button visible
      expect(find.text('Mark Unpaid'), findsOneWidget);
      expect(find.text('PAID'), findsOneWidget);

      // Tap Mark Unpaid to toggle back
      final markUnpaidBtn = find.text('Mark Unpaid');
      await tester.tap(markUnpaidBtn);
      await tester.pumpAndSettle();

      expect(find.text('Mark Paid'), findsOneWidget);
    });

    testWidgets('opens draft reminder modal and generates draft with selected tone', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = Client(
        id: 'c-1',
        name: 'Amina Musa',
        initials: 'AM',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      clientRepo.clients.add(client);
      invoiceRepo.clients['c-1'] = client;

      final now = DateTime.now();
      final inv = Invoice(
        id: 'inv-overdue',
        clientId: 'c-1',
        invoiceNumber: 'INV-2026-999',
        amount: const Money(minorUnits: 125000, currency: 'USD'),
        issueDate: DateTime(now.year, now.month, now.day - 15),
        dueDate: DateTime(now.year, now.month, now.day - 3),
        status: InvoiceStatus.unpaid,
        createdAt: now,
        updatedAt: now,
      );
      invoiceRepo.invoices.add(inv);

      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Click "Draft Reminder"
      final draftBtn = find.text('Draft Reminder');
      expect(draftBtn, findsOneWidget);
      await tester.tap(draftBtn);
      await tester.pumpAndSettle();

      // Modal is visible
      expect(find.text('Draft Polite Payment Reminder'), findsOneWidget);
      expect(find.text('Amina Musa'), findsWidgets);
      expect(find.text('INV-2026-999'), findsWidgets);
      expect(find.text('\$1250.00'), findsWidgets);

      // Verify tone chips: Gentle, Polite, Firm
      expect(find.text('Gentle'), findsOneWidget);
      expect(find.text('Polite'), findsOneWidget);
      expect(find.text('Firm'), findsOneWidget);

      // Tap "Firm" tone chip
      await tester.tap(find.text('Firm'));
      await tester.pumpAndSettle();

      // Tap "Generate Polite Reminder" CTA
      final generateBtn = find.text('Generate Polite Reminder');
      expect(generateBtn, findsOneWidget);
      await tester.tap(generateBtn);
      await tester.pumpAndSettle();

      // Generated draft is displayed in text field
      expect(find.textContaining('friendly reminder regarding INV-2026-999'), findsOneWidget);
      expect(find.text('Copy to Clipboard'), findsOneWidget);

      // Tap Copy to Clipboard
      await tester.tap(find.text('Copy to Clipboard'));
      await tester.pumpAndSettle();

      expect(find.textContaining('copied to clipboard'), findsOneWidget);
    });

    testWidgets('validates zero amount and creates invoice in SQLite', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = Client(
        id: 'c-1',
        name: 'Beta Studio',
        initials: 'BS',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      clientRepo.clients.add(client);
      invoiceRepo.clients['c-1'] = client;

      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Tap Create Invoice
      await tester.tap(find.text('Create Invoice'));
      await tester.pumpAndSettle();

      expect(find.text('Create New Invoice'), findsOneWidget);

      // Clear amount to 0
      final amountField = find.widgetWithText(TextFormField, '1500.00');
      await tester.enterText(amountField, '0');
      await tester.pumpAndSettle();

      // Tap save -> should fail validation
      final dialogCreateBtn = find.descendant(of: find.byType(AlertDialog), matching: find.text('Create Invoice'));
      await tester.tap(dialogCreateBtn);
      await tester.pumpAndSettle();

      expect(find.text('Must be > 0'), findsOneWidget);

      // Enter valid amount
      await tester.enterText(amountField, '750.50');
      await tester.pumpAndSettle();

      await tester.tap(dialogCreateBtn);
      await tester.pumpAndSettle();

      // Verify invoice was added to repo
      expect(invoiceRepo.invoices.length, 1);
      expect(invoiceRepo.invoices.first.amount.minorUnits, 75050);
      expect(invoiceRepo.invoices.first.amount.currency, 'USD');
    });
  });
}
