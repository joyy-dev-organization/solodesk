import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:solodesk/db/database_service.dart';
import 'package:solodesk/db/client_repository.dart';
import 'package:solodesk/db/lead_repository.dart';
import 'package:solodesk/models/client.dart';
import 'package:solodesk/models/lead.dart';
import 'package:solodesk/models/money.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Milestone M6: LeadRepository & SQLite Schema V3 Tests', () {
    late DatabaseService dbService;
    late ClientRepository clientRepo;
    late LeadRepository leadRepo;

    setUp(() async {
      dbService = await DatabaseService.inMemory();
      clientRepo = ClientRepository(dbService.db);
      leadRepo = LeadRepository(dbService.db);
    });

    tearDown(() async {
      await dbService.close();
    });

    test('Schema V3 Migration: leads table exists and schema_migrations records v3', () async {
      final migrations = await dbService.db.query('schema_migrations', orderBy: 'version ASC');
      expect(migrations.length, equals(3));
      expect(migrations[0]['version'], equals(1));
      expect(migrations[1]['version'], equals(2));
      expect(migrations[2]['version'], equals(3));
      expect(migrations[2]['description'], contains('leads table'));

      // Verify table exists by querying empty list
      final leads = await leadRepo.getLeads();
      expect(leads, isEmpty);
    });

    test('CRUD operations: insert, get, update, delete lead', () async {
      final now = DateTime.now().toUtc();
      final lead = Lead(
        id: 'lead-test-1',
        contactName: 'Chidi Anagonye',
        company: 'Ethics Studio',
        email: 'chidi@ethics.edu',
        phone: '+1234567890',
        serviceNiche: 'Writing & content',
        stage: LeadStage.discovery,
        estimatedValue: const Money(minorUnits: 150000, currency: 'USD'),
        nextFollowUpDate: DateTime(2026, 10, 20),
        notes: 'Introductory discussion regarding philosophy curriculum.',
        isSynthetic: false,
        createdAt: now,
        updatedAt: now,
      );

      await leadRepo.createLead(lead);

      final fetched = await leadRepo.getLeadById('lead-test-1');
      expect(fetched, isNotNull);
      expect(fetched!.contactName, equals('Chidi Anagonye'));
      expect(fetched.company, equals('Ethics Studio'));
      expect(fetched.estimatedValue?.minorUnits, equals(150000));
      expect(fetched.estimatedValue?.currency, equals('USD'));
      expect(fetched.stage, equals(LeadStage.discovery));

      // Update lead
      final updated = fetched.copyWith(
        stage: LeadStage.proposalSent,
        notes: 'Proposal delivered with syllabus.',
      );
      await leadRepo.updateLead(updated);

      final fetchedUpdated = await leadRepo.getLeadById('lead-test-1');
      expect(fetchedUpdated!.stage, equals(LeadStage.proposalSent));
      expect(fetchedUpdated.notes, equals('Proposal delivered with syllabus.'));

      // Delete lead
      await leadRepo.deleteLead('lead-test-1');
      expect(await leadRepo.getLeadById('lead-test-1'), isNull);
    });

    test('Foreign key set null: deleting linked client preserves lead with null clientId', () async {
      final now = DateTime.now().toUtc();
      final client = Client(
        id: 'client-fk-1',
        name: 'Eleanor Shellstrop',
        initials: 'ES',
        createdAt: now,
        updatedAt: now,
      );
      await clientRepo.createClient(client);

      final lead = Lead(
        id: 'lead-fk-1',
        clientId: 'client-fk-1',
        contactName: 'Eleanor Shellstrop',
        serviceNiche: 'Consulting & coaching',
        stage: LeadStage.inDiscussion,
        createdAt: now,
        updatedAt: now,
      );
      await leadRepo.createLead(lead);

      // Verify linked
      var fetched = await leadRepo.getLeadById('lead-fk-1');
      expect(fetched!.clientId, equals('client-fk-1'));

      // Delete client
      await clientRepo.deleteClient('client-fk-1');

      // Lead must survive with clientId = null (ON DELETE SET NULL)
      fetched = await leadRepo.getLeadById('lead-fk-1');
      expect(fetched, isNotNull);
      expect(fetched!.clientId, isNull);
      expect(fetched.contactName, equals('Eleanor Shellstrop'));
    });

    test('Stage and Timing filtering work accurately without cross-talk', () async {
      final today = DateTime(2026, 10, 18);
      final now = DateTime.now().toUtc();

      // Lead 1: Overdue follow-up (Discovery)
      await leadRepo.createLead(Lead(
        id: 'l-1',
        contactName: 'Lead One',
        serviceNiche: 'Design & branding',
        stage: LeadStage.discovery,
        nextFollowUpDate: DateTime(2026, 10, 15),
        createdAt: now,
        updatedAt: now,
      ));

      // Lead 2: Due today (Proposal Sent)
      await leadRepo.createLead(Lead(
        id: 'l-2',
        contactName: 'Lead Two',
        serviceNiche: 'Design & branding',
        stage: LeadStage.proposalSent,
        nextFollowUpDate: DateTime(2026, 10, 18),
        createdAt: now,
        updatedAt: now,
      ));

      // Lead 3: Upcoming (In Discussion)
      await leadRepo.createLead(Lead(
        id: 'l-3',
        contactName: 'Lead Three',
        serviceNiche: 'Writing & content',
        stage: LeadStage.inDiscussion,
        nextFollowUpDate: DateTime(2026, 10, 25),
        createdAt: now,
        updatedAt: now,
      ));

      // Lead 4: Won (No follow-up)
      await leadRepo.createLead(Lead(
        id: 'l-4',
        contactName: 'Lead Four',
        serviceNiche: 'Writing & content',
        stage: LeadStage.won,
        nextFollowUpDate: null,
        createdAt: now,
        updatedAt: now,
      ));

      // Stage filtering
      final discoveryLeads = await leadRepo.getLeads(stage: LeadStage.discovery);
      expect(discoveryLeads.map((l) => l.id), equals(['l-1']));

      final wonLeads = await leadRepo.getLeads(stage: LeadStage.won);
      expect(wonLeads.map((l) => l.id), equals(['l-4']));

      // Timing filtering
      final overdueLeads = await leadRepo.getLeads(timing: LeadFollowUpTiming.overdue, referenceDate: today);
      expect(overdueLeads.map((l) => l.id), equals(['l-1']));

      final dueTodayLeads = await leadRepo.getLeads(timing: LeadFollowUpTiming.dueToday, referenceDate: today);
      expect(dueTodayLeads.map((l) => l.id), equals(['l-2']));

      final upcomingLeads = await leadRepo.getLeads(timing: LeadFollowUpTiming.upcoming, referenceDate: today);
      expect(upcomingLeads.map((l) => l.id), equals(['l-3']));

      // Stage counts
      final counts = await leadRepo.getLeadCountsByStage();
      expect(counts[LeadStage.discovery], equals(1));
      expect(counts[LeadStage.proposalSent], equals(1));
      expect(counts[LeadStage.inDiscussion], equals(1));
      expect(counts[LeadStage.won], equals(1));
      expect(counts[LeadStage.lost], equals(0));
    });

    test('Pipeline summary computes unweighted currency-segregated totals and real counts', () async {
      final today = DateTime(2026, 10, 18);
      final now = DateTime.now().toUtc();

      // Lead 1: NGN 200,000 (Active - Discovery - Overdue)
      await leadRepo.createLead(Lead(
        id: 'p-1',
        contactName: 'Kemi NGN 1',
        serviceNiche: 'Design & branding',
        stage: LeadStage.discovery,
        estimatedValue: const Money(minorUnits: 20000000, currency: 'NGN'),
        nextFollowUpDate: DateTime(2026, 10, 16),
        createdAt: now,
        updatedAt: now,
      ));

      // Lead 2: NGN 150,000 (Active - Proposal Sent - Due Today)
      await leadRepo.createLead(Lead(
        id: 'p-2',
        contactName: 'Tunde NGN 2',
        serviceNiche: 'Design & branding',
        stage: LeadStage.proposalSent,
        estimatedValue: const Money(minorUnits: 15000000, currency: 'NGN'),
        nextFollowUpDate: DateTime(2026, 10, 18),
        createdAt: now,
        updatedAt: now,
      ));

      // Lead 3: USD 2,500 (Active - In Discussion - Upcoming)
      await leadRepo.createLead(Lead(
        id: 'p-3',
        contactName: 'Marcus USD 1',
        serviceNiche: 'Writing & content',
        stage: LeadStage.inDiscussion,
        estimatedValue: const Money(minorUnits: 250000, currency: 'USD'),
        nextFollowUpDate: DateTime(2026, 10, 22),
        createdAt: now,
        updatedAt: now,
      ));

      // Lead 4: Won (Closed - Should not be in active pipeline summary)
      await leadRepo.createLead(Lead(
        id: 'p-4',
        contactName: 'Won Lead',
        serviceNiche: 'Writing & content',
        stage: LeadStage.won,
        estimatedValue: const Money(minorUnits: 100000, currency: 'USD'),
        createdAt: now,
        updatedAt: now,
      ));

      final summary = await leadRepo.getPipelineSummary(referenceDate: today);
      expect(summary.totalActiveLeads, equals(3));
      expect(summary.followUpsDue, equals(2)); // overdue (1) + dueToday (1)
      expect(summary.overdueCount, equals(1));
      expect(summary.dueTodayCount, equals(1));
      expect(summary.upcomingCount, equals(1));
      expect(summary.wonCount, equals(1));

      // Multi-currency segregation: values are strictly grouped by currency, NEVER summed together
      expect(summary.quotedValueMinorUnitsByCurrency['NGN'], equals(35000000)); // ₦350,000
      expect(summary.quotedValueMinorUnitsByCurrency['USD'], equals(250000)); // $2,500
    });

    test('Synthetic isolation: includeSynthetic false excludes synthetic demo leads', () async {
      final now = DateTime.now().toUtc();

      await leadRepo.createLead(Lead(
        id: 'lead-real',
        contactName: 'Real Client',
        serviceNiche: 'Design & branding',
        stage: LeadStage.discovery,
        isSynthetic: false,
        createdAt: now,
        updatedAt: now,
      ));

      await leadRepo.createLead(Lead(
        id: 'lead-demo',
        contactName: 'Demo Client',
        serviceNiche: 'Design & branding',
        stage: LeadStage.discovery,
        isSynthetic: true,
        createdAt: now,
        updatedAt: now,
      ));

      final allLeads = await leadRepo.getLeads(includeSynthetic: true);
      expect(allLeads.length, equals(2));

      final realOnly = await leadRepo.getLeads(includeSynthetic: false);
      expect(realOnly.length, equals(1));
      expect(realOnly.first.id, equals('lead-real'));
    });
  });
}
