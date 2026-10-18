import 'package:flutter_test/flutter_test.dart';
import 'package:solodesk/models/lead.dart';
import 'package:solodesk/models/money.dart';

void main() {
  group('Lead Domain Model Tests', () {
    test('instantiates with required fields and defaults', () {
      final now = DateTime.now().toUtc();
      final lead = Lead(
        id: 'lead-1',
        contactName: 'Amina Musa',
        serviceNiche: 'Design & branding',
        stage: LeadStage.discovery,
        createdAt: now,
        updatedAt: now,
      );

      expect(lead.id, equals('lead-1'));
      expect(lead.contactName, equals('Amina Musa'));
      expect(lead.company, isNull);
      expect(lead.serviceNiche, equals('Design & branding'));
      expect(lead.stage, equals(LeadStage.discovery));
      expect(lead.stage.isActive, isTrue);
      expect(lead.stage.isClosed, isFalse);
      expect(lead.estimatedValue, isNull);
      expect(lead.nextFollowUpDate, isNull);
      expect(lead.isSynthetic, isFalse);
      expect(lead.displayName, equals('Amina Musa'));
    });

    test('displayName includes company when present', () {
      final now = DateTime.now().toUtc();
      final lead = Lead(
        id: 'lead-2',
        contactName: 'Amina Musa',
        company: 'Musa Brand Lab',
        serviceNiche: 'Design & branding',
        stage: LeadStage.proposalSent,
        createdAt: now,
        updatedAt: now,
      );

      expect(lead.displayName, equals('Amina Musa (Musa Brand Lab)'));
    });

    test('LeadStage.fromString parses various normalizations and defaults cleanly', () {
      expect(LeadStage.fromString('discovery'), equals(LeadStage.discovery));
      expect(LeadStage.fromString('new_lead'), equals(LeadStage.discovery));
      expect(LeadStage.fromString('new'), equals(LeadStage.discovery));
      expect(LeadStage.fromString('proposal_sent'), equals(LeadStage.proposalSent));
      expect(LeadStage.fromString('Proposal Sent'), equals(LeadStage.proposalSent));
      expect(LeadStage.fromString('in_discussion'), equals(LeadStage.inDiscussion));
      expect(LeadStage.fromString('contacted'), equals(LeadStage.inDiscussion));
      expect(LeadStage.fromString('won'), equals(LeadStage.won));
      expect(LeadStage.fromString('lost'), equals(LeadStage.lost));
      expect(LeadStage.fromString('unknown_stage'), equals(LeadStage.discovery));
    });

    test('LeadFollowUpTiming calculates overdue, dueToday, upcoming, and none', () {
      final today = DateTime(2026, 10, 18); // Reference date
      final now = DateTime.now().toUtc();

      // Overdue
      final overdueLead = Lead(
        id: 'l-overdue',
        contactName: 'Overdue Client',
        serviceNiche: 'Writing & content',
        stage: LeadStage.inDiscussion,
        nextFollowUpDate: DateTime(2026, 10, 16),
        createdAt: now,
        updatedAt: now,
      );
      expect(overdueLead.timingRelativeTo(today), equals(LeadFollowUpTiming.overdue));
      expect(overdueLead.isFollowUpOverdue(today), isTrue);
      expect(overdueLead.isFollowUpToday(today), isFalse);
      expect(overdueLead.isFollowUpUpcoming(today), isFalse);

      // Due Today
      final todayLead = Lead(
        id: 'l-today',
        contactName: 'Today Client',
        serviceNiche: 'Writing & content',
        stage: LeadStage.proposalSent,
        nextFollowUpDate: DateTime(2026, 10, 18),
        createdAt: now,
        updatedAt: now,
      );
      expect(todayLead.timingRelativeTo(today), equals(LeadFollowUpTiming.dueToday));
      expect(todayLead.isFollowUpToday(today), isTrue);

      // Upcoming
      final upcomingLead = Lead(
        id: 'l-upcoming',
        contactName: 'Upcoming Client',
        serviceNiche: 'Writing & content',
        stage: LeadStage.discovery,
        nextFollowUpDate: DateTime(2026, 10, 22),
        createdAt: now,
        updatedAt: now,
      );
      expect(upcomingLead.timingRelativeTo(today), equals(LeadFollowUpTiming.upcoming));
      expect(upcomingLead.isFollowUpUpcoming(today), isTrue);

      // None
      final noneLead = Lead(
        id: 'l-none',
        contactName: 'No Date Client',
        serviceNiche: 'Writing & content',
        stage: LeadStage.discovery,
        nextFollowUpDate: null,
        createdAt: now,
        updatedAt: now,
      );
      expect(noneLead.timingRelativeTo(today), equals(LeadFollowUpTiming.none));

      // Closed leads (won/lost) have timing none even if date set
      final wonLead = Lead(
        id: 'l-won',
        contactName: 'Won Client',
        serviceNiche: 'Writing & content',
        stage: LeadStage.won,
        nextFollowUpDate: DateTime(2026, 10, 16),
        createdAt: now,
        updatedAt: now,
      );
      expect(wonLead.timingRelativeTo(today), equals(LeadFollowUpTiming.none));
    });

    test('toDbMap and fromDbMap round-trip preserves all fields', () {
      final now = DateTime.utc(2026, 10, 18, 10, 30, 0);
      final lead = Lead(
        id: 'lead-rt-1',
        clientId: 'client-apex-1',
        contactName: 'Tola James',
        company: 'Apex Digital',
        email: 'tola@apexdigital.com',
        phone: '+2348012345678',
        serviceNiche: 'Design & branding',
        stage: LeadStage.proposalSent,
        estimatedValue: const Money(minorUnits: 35000000, currency: 'NGN'),
        nextFollowUpDate: DateTime(2026, 10, 20),
        notes: 'Requested proposal revision with milestone breakdowns.',
        isSynthetic: true,
        createdAt: now,
        updatedAt: now,
      );

      final map = lead.toDbMap();
      expect(map['id'], equals('lead-rt-1'));
      expect(map['client_id'], equals('client-apex-1'));
      expect(map['contact_name'], equals('Tola James'));
      expect(map['company'], equals('Apex Digital'));
      expect(map['email'], equals('tola@apexdigital.com'));
      expect(map['phone'], equals('+2348012345678'));
      expect(map['service_niche'], equals('Design & branding'));
      expect(map['stage'], equals('proposal_sent'));
      expect(map['estimated_value_minor_units'], equals(35000000));
      expect(map['currency'], equals('NGN'));
      expect(map['next_follow_up_date'], equals('2026-10-20'));
      expect(map['notes'], equals('Requested proposal revision with milestone breakdowns.'));
      expect(map['is_synthetic'], equals(1));

      final restored = Lead.fromDbMap(map);
      expect(restored.id, equals(lead.id));
      expect(restored.clientId, equals(lead.clientId));
      expect(restored.contactName, equals(lead.contactName));
      expect(restored.company, equals(lead.company));
      expect(restored.email, equals(lead.email));
      expect(restored.phone, equals(lead.phone));
      expect(restored.serviceNiche, equals(lead.serviceNiche));
      expect(restored.stage, equals(lead.stage));
      expect(restored.estimatedValue?.minorUnits, equals(35000000));
      expect(restored.estimatedValue?.currency, equals('NGN'));
      expect(restored.nextFollowUpDate, equals(DateTime(2026, 10, 20)));
      expect(restored.notes, equals(lead.notes));
      expect(restored.isSynthetic, isTrue);
    });

    test('copyWith allows partial mutations and clears', () {
      final now = DateTime.now().toUtc();
      final lead = Lead(
        id: 'l-copy',
        contactName: 'Initial Name',
        serviceNiche: 'Writing & content',
        stage: LeadStage.discovery,
        estimatedValue: const Money(minorUnits: 10000, currency: 'USD'),
        nextFollowUpDate: DateTime(2026, 10, 25),
        createdAt: now,
        updatedAt: now,
      );

      final updated = lead.copyWith(
        stage: LeadStage.inDiscussion,
        clearEstimatedValue: true,
        clearNextFollowUpDate: true,
      );

      expect(updated.stage, equals(LeadStage.inDiscussion));
      expect(updated.estimatedValue, isNull);
      expect(updated.nextFollowUpDate, isNull);
      expect(updated.contactName, equals('Initial Name'));
    });
  });
}
