import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:solodesk/db/database_service.dart';
import 'package:solodesk/db/client_repository.dart';
import 'package:solodesk/db/service_plan_repository.dart';
import 'package:solodesk/models/client.dart';
import 'package:solodesk/models/service_plan.dart';
import 'package:solodesk/models/money.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Milestone M7: ServicePlanRepository & SQLite Schema V4 Tests', () {
    late DatabaseService dbService;
    late ClientRepository clientRepo;
    late ServicePlanRepository planRepo;

    setUp(() async {
      dbService = await DatabaseService.inMemory();
      clientRepo = ClientRepository(dbService.db);
      planRepo = ServicePlanRepository(dbService.db);
    });

    tearDown(() async {
      await dbService.close();
    });

    test('Schema V4 Migration: service_plans table exists and schema_migrations records v4', () async {
      final migrations = await dbService.db.query('schema_migrations', orderBy: 'version ASC');
      expect(migrations.length, equals(4));
      expect(migrations[0]['version'], equals(1));
      expect(migrations[1]['version'], equals(2));
      expect(migrations[2]['version'], equals(3));
      expect(migrations[3]['version'], equals(4));
      expect(migrations[3]['description'], contains('service_plans table'));

      // Verify table exists by querying empty list
      final plans = await planRepo.getPlans();
      expect(plans, isEmpty);
    });

    test('CRUD operations: insert, get, update, delete service plan', () async {
      final now = DateTime.now().toUtc();
      final plan = ServicePlan(
        id: 'plan-test-1',
        title: 'Monthly Content Retainer',
        serviceNiche: 'Writing & content',
        cadence: PlanCadence.monthly,
        price: const Money(minorUnits: 15000000, currency: 'NGN'), // 150,000 NGN
        deliverables: const ['4 Blog Posts', '8 Social Posts'],
        exclusions: const ['Video production', 'Weekend rush turnarounds'],
        revisionLimit: '2 rounds per deliverable',
        status: PlanStatus.active,
        renewalDate: DateTime(2026, 11, 1),
        notes: 'Monthly billing on the 1st.',
        isSynthetic: false,
        createdAt: now,
        updatedAt: now,
      );

      // Create
      await planRepo.createPlan(plan);

      // Read
      final fetched = await planRepo.getPlanById('plan-test-1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Monthly Content Retainer'));
      expect(fetched.serviceNiche, equals('Writing & content'));
      expect(fetched.cadence, equals(PlanCadence.monthly));
      expect(fetched.priceMinorUnits, equals(15000000));
      expect(fetched.currency, equals('NGN'));
      expect(fetched.deliverables, equals(const ['4 Blog Posts', '8 Social Posts']));
      expect(fetched.exclusions, equals(const ['Video production', 'Weekend rush turnarounds']));
      expect(fetched.revisionLimits, equals('2 rounds per deliverable'));
      expect(fetched.status, equals(PlanStatus.active));
      expect(fetched.renewalDate, equals(DateTime(2026, 11, 1)));

      // Update
      final updated = fetched.copyWith(
        title: 'Premium Content Retainer',
        price: const Money(minorUnits: 20000000, currency: 'NGN'),
        status: PlanStatus.paused,
      );
      await planRepo.updatePlan(updated);

      final fetchedUpdated = await planRepo.getPlanById('plan-test-1');
      expect(fetchedUpdated!.title, equals('Premium Content Retainer'));
      expect(fetchedUpdated.priceMinorUnits, equals(20000000));
      expect(fetchedUpdated.status, equals(PlanStatus.paused));

      // Delete
      await planRepo.deletePlan('plan-test-1');
      final fetchedDeleted = await planRepo.getPlanById('plan-test-1');
      expect(fetchedDeleted, isNull);
    });

    test('Foreign key ON DELETE SET NULL behavior when client is deleted', () async {
      // Create a client
      final client = Client(
        id: 'client-m7-test',
        name: 'Tola Adebayo',
        initials: 'TA',
        company: 'Vanguard Media',
        email: 'tola@vanguard.ng',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await clientRepo.createClient(client);

      // Create a service plan linked to this client
      final plan = ServicePlan(
        id: 'plan-fk-test',
        clientId: client.id,
        title: 'Brand Growth Package',
        serviceNiche: 'Design & branding',
        cadence: PlanCadence.monthly,
        price: const Money(minorUnits: 30000000, currency: 'NGN'),
        deliverables: const ['Brand kit'],
        exclusions: const ['3D'],
        revisionLimit: '1 round',
        status: PlanStatus.active,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await planRepo.createPlan(plan);

      // Verify join works
      final plansWithClient = await planRepo.getPlansWithClient(clientId: client.id);
      expect(plansWithClient.length, equals(1));
      expect(plansWithClient.first.clientName, equals('Tola Adebayo'));
      expect(plansWithClient.first.clientCompany, equals('Vanguard Media'));

      // Delete the client
      await clientRepo.deleteClient(client.id);

      // Verify the service plan still survives, but clientId is set to NULL
      final survivingPlan = await planRepo.getPlanById('plan-fk-test');
      expect(survivingPlan, isNotNull);
      expect(survivingPlan!.clientId, isNull);

      final allPlansWithClient = await planRepo.getPlansWithClient();
      final survivingPlanJoined = allPlansWithClient.firstWhere((p) => p.plan.id == 'plan-fk-test');
      expect(survivingPlanJoined.clientName, isNull);
    });

    test('Filtering by status and cadence', () async {
      final p1 = ServicePlan(
        id: 'p-1',
        title: 'Active Monthly Plan',
        serviceNiche: 'Design & branding',
        cadence: PlanCadence.monthly,
        price: const Money(minorUnits: 100000, currency: 'USD'),
        deliverables: const ['Design'],
        status: PlanStatus.active,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      final p2 = ServicePlan(
        id: 'p-2',
        title: 'Paused Quarterly Plan',
        serviceNiche: 'Writing & content',
        cadence: PlanCadence.quarterly,
        price: const Money(minorUnits: 300000, currency: 'USD'),
        deliverables: const ['Articles'],
        status: PlanStatus.paused,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      final p3 = ServicePlan(
        id: 'p-3',
        title: 'Draft Annual Plan',
        serviceNiche: 'Consulting & coaching',
        cadence: PlanCadence.annual,
        price: const Money(minorUnits: 1200000, currency: 'USD'),
        deliverables: const ['Strategy'],
        status: PlanStatus.draft,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      await planRepo.createPlan(p1);
      await planRepo.createPlan(p2);
      await planRepo.createPlan(p3);

      // Filter by status
      final activePlans = await planRepo.getPlans(status: PlanStatus.active);
      expect(activePlans.length, equals(1));
      expect(activePlans.first.id, equals('p-1'));

      final pausedPlans = await planRepo.getPlans(status: PlanStatus.paused);
      expect(pausedPlans.length, equals(1));
      expect(pausedPlans.first.id, equals('p-2'));

      // Filter by cadence
      final monthlyPlans = await planRepo.getPlans(cadence: PlanCadence.monthly);
      expect(monthlyPlans.length, equals(1));
      expect(monthlyPlans.first.id, equals('p-1'));

      final quarterlyPlans = await planRepo.getPlans(cadence: PlanCadence.quarterly);
      expect(quarterlyPlans.length, equals(1));
      expect(quarterlyPlans.first.id, equals('p-2'));
    });

    test('Multi-Currency Invariant: NGN and USD MRR are segregated and never summed', () async {
      // 1 active NGN monthly plan: 250,000 NGN (25,000,000 kobo)
      final ngnPlan = ServicePlan(
        id: 'ngn-plan',
        title: 'Lagos Retainer',
        serviceNiche: 'Design & branding',
        cadence: PlanCadence.monthly,
        price: const Money(minorUnits: 25000000, currency: 'NGN'),
        deliverables: const ['4 Flyers'],
        status: PlanStatus.active,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      // 1 active USD monthly plan: $1,500.00 (150,000 cents)
      final usdMonthlyPlan = ServicePlan(
        id: 'usd-monthly-plan',
        title: 'US Client Monthly',
        serviceNiche: 'Software & development',
        cadence: PlanCadence.monthly,
        price: const Money(minorUnits: 150000, currency: 'USD'),
        deliverables: const ['Support'],
        status: PlanStatus.active,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      // 1 active USD quarterly plan: $3,000.00 / quarter = $1,000.00 / month (100,000 cents)
      final usdQuarterlyPlan = ServicePlan(
        id: 'usd-quarterly-plan',
        title: 'US Client Quarterly',
        serviceNiche: 'Consulting & coaching',
        cadence: PlanCadence.quarterly,
        price: const Money(minorUnits: 300000, currency: 'USD'),
        deliverables: const ['Consulting'],
        status: PlanStatus.active,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      // 1 paused USD plan: should NOT be included in MRR
      final usdPausedPlan = ServicePlan(
        id: 'usd-paused-plan',
        title: 'Paused Retainer',
        serviceNiche: 'Writing & content',
        cadence: PlanCadence.monthly,
        price: const Money(minorUnits: 50000, currency: 'USD'),
        deliverables: const ['Paused'],
        status: PlanStatus.paused,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      await planRepo.createPlan(ngnPlan);
      await planRepo.createPlan(usdMonthlyPlan);
      await planRepo.createPlan(usdQuarterlyPlan);
      await planRepo.createPlan(usdPausedPlan);

      final summary = await planRepo.getPlanSummary();

      // STRICT INVARIANT: Must be separate keys in recurringMonthlyRevenueByCurrency, NEVER a single combined total
      final mrr = summary.recurringMonthlyRevenueByCurrency;
      expect(mrr.containsKey('NGN'), isTrue);
      expect(mrr.containsKey('USD'), isTrue);
      expect(mrr.length, equals(2));

      // NGN MRR is exactly 25,000,000 kobo (250,000 NGN)
      expect(mrr['NGN'], equals(25000000));

      // USD MRR is $1,500 + ($3,000 / 3) = $2,500 (250,000 cents)
      expect(mrr['USD'], equals(250000));

      // Assert counts
      expect(summary.totalPlans, equals(4));
      expect(summary.activePlans, equals(3));
      expect(summary.pausedPlans, equals(1));
      expect(summary.draftPlans, equals(0));
      expect(summary.completedPlans, equals(0));
    });

    test('SQLite CHECK constraint violations throw DatabaseException', () async {
      // 1. Invalid negative price
      expect(
        () async => await dbService.db.insert('service_plans', {
          'id': 'bad-price',
          'title': 'Negative Price Plan',
          'service_niche': 'Design & branding',
          'cadence': 'monthly',
          'price_minor_units': -500, // CHECK constraint price_minor_units >= 0
          'currency': 'USD',
          'status': 'active',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }),
        throwsA(isA<DatabaseException>()),
      );

      // 2. Invalid currency (length != 3)
      expect(
        () async => await dbService.db.insert('service_plans', {
          'id': 'bad-curr',
          'title': 'Bad Currency Plan',
          'service_niche': 'Design & branding',
          'cadence': 'monthly',
          'price_minor_units': 1000,
          'currency': 'TOOLONG', // CHECK constraint length(currency) = 3
          'status': 'active',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }),
        throwsA(isA<DatabaseException>()),
      );

      // 3. Invalid cadence value
      expect(
        () async => await dbService.db.insert('service_plans', {
          'id': 'bad-cadence',
          'title': 'Bad Cadence Plan',
          'service_niche': 'Design & branding',
          'cadence': 'every_century', // CHECK constraint cadence IN (...)
          'price_minor_units': 1000,
          'currency': 'USD',
          'status': 'active',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
