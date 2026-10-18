import 'package:flutter_test/flutter_test.dart';
import 'package:solodesk/models/service_plan.dart';
import 'package:solodesk/models/money.dart';

void main() {
  group('Milestone M7: ServicePlan Domain Model Tests', () {
    test('instantiates with required fields and defaults', () {
      final now = DateTime.now().toUtc();
      final plan = ServicePlan(
        id: 'plan-1',
        title: 'Monthly Brand Design Retainer',
        serviceNiche: 'Design & branding',
        cadence: PlanCadence.monthly,
        price: const Money(minorUnits: 25000000, currency: 'NGN'), // 250,000 NGN in kobo
        deliverables: const ['4 Social media graphics', '1 Brand collateral refresh'],
        exclusions: const ['Custom 3D modeling', 'Rush weekend turns'],
        revisionLimit: '2 rounds per deliverable',
        status: PlanStatus.active,
        createdAt: now,
        updatedAt: now,
      );

      expect(plan.id, equals('plan-1'));
      expect(plan.title, equals('Monthly Brand Design Retainer'));
      expect(plan.serviceNiche, equals('Design & branding'));
      expect(plan.cadence, equals(PlanCadence.monthly));
      expect(plan.priceMinorUnits, equals(25000000));
      expect(plan.currency, equals('NGN'));
      expect(plan.price, equals(const Money(minorUnits: 25000000, currency: 'NGN')));
      expect(plan.deliverables.length, equals(2));
      expect(plan.exclusions.length, equals(2));
      expect(plan.revisionLimits, equals('2 rounds per deliverable'));
      expect(plan.status, equals(PlanStatus.active));
      expect(plan.status.isActive, isTrue);
      expect(plan.isSynthetic, isFalse);
      expect(plan.deliverablesCount, equals(2));
      expect(plan.exclusionsCount, equals(2));
    });

    test('price and monthlyEquivalent minor unit calculations for various cadences', () {
      final now = DateTime.now().toUtc();

      // Monthly
      final monthlyPlan = ServicePlan(
        id: 'p-m',
        title: 'Monthly SEO',
        serviceNiche: 'Writing & content',
        cadence: PlanCadence.monthly,
        price: const Money(minorUnits: 120000, currency: 'USD'), // $1,200.00
        deliverables: const ['Blog posts'],
        status: PlanStatus.active,
        createdAt: now,
        updatedAt: now,
      );
      expect(monthlyPlan.monthlyEquivalentMinorUnits, equals(120000));

      // Quarterly ($3,000 / 3 = $1,000/mo)
      final quarterlyPlan = ServicePlan(
        id: 'p-q',
        title: 'Quarterly Strategy',
        serviceNiche: 'Consulting & coaching',
        cadence: PlanCadence.quarterly,
        price: const Money(minorUnits: 300000, currency: 'USD'), // $3,000.00
        deliverables: const ['Quarterly review'],
        status: PlanStatus.active,
        createdAt: now,
        updatedAt: now,
      );
      expect(quarterlyPlan.monthlyEquivalentMinorUnits, equals(100000));
      expect(quarterlyPlan.monthlyEquivalentMoney, equals(const Money(minorUnits: 100000, currency: 'USD')));

      // Annual ($12,000 / 12 = $1,000/mo)
      final annualPlan = ServicePlan(
        id: 'p-a',
        title: 'Annual Support',
        serviceNiche: 'Software & development',
        cadence: PlanCadence.annual,
        price: const Money(minorUnits: 1200000, currency: 'USD'), // $12,000.00
        deliverables: const ['Bug fixes'],
        status: PlanStatus.active,
        createdAt: now,
        updatedAt: now,
      );
      expect(annualPlan.monthlyEquivalentMinorUnits, equals(100000));

      // Weekly ($250 * 52 / 12 = $1,083.33)
      final weeklyPlan = ServicePlan(
        id: 'p-w',
        title: 'Weekly Standup',
        serviceNiche: 'Consulting & coaching',
        cadence: PlanCadence.weekly,
        price: const Money(minorUnits: 25000, currency: 'USD'), // $250.00
        deliverables: const ['1 hr coaching'],
        status: PlanStatus.active,
        createdAt: now,
        updatedAt: now,
      );
      expect(weeklyPlan.monthlyEquivalentMinorUnits, equals(108333));
    });

    test('PlanCadence enum conversion fromDb and displayName', () {
      expect(PlanCadence.fromDb('monthly'), equals(PlanCadence.monthly));
      expect(PlanCadence.fromDb('quarterly'), equals(PlanCadence.quarterly));
      expect(PlanCadence.fromDb('annual'), equals(PlanCadence.annual));
      expect(PlanCadence.fromDb('weekly'), equals(PlanCadence.weekly));
      expect(PlanCadence.fromDb('biweekly'), equals(PlanCadence.biweekly));
      expect(PlanCadence.fromDb('MONTHLY'), equals(PlanCadence.monthly));
      expect(PlanCadence.fromDb('unknown'), equals(PlanCadence.monthly)); // Safe fallback

      expect(PlanCadence.monthly.displayName, equals('Monthly'));
      expect(PlanCadence.quarterly.displayName, equals('Quarterly'));
      expect(PlanCadence.annual.displayName, equals('Annual'));
    });

    test('PlanStatus enum conversion fromDb and flags', () {
      expect(PlanStatus.fromDb('draft'), equals(PlanStatus.draft));
      expect(PlanStatus.fromDb('active'), equals(PlanStatus.active));
      expect(PlanStatus.fromDb('paused'), equals(PlanStatus.paused));
      expect(PlanStatus.fromDb('completed'), equals(PlanStatus.completed));
      expect(PlanStatus.fromDb('ACTIVE'), equals(PlanStatus.active));
      expect(PlanStatus.fromDb('invalid'), equals(PlanStatus.draft));

      expect(PlanStatus.active.isActive, isTrue);
      expect(PlanStatus.draft.isActive, isFalse);
      expect(PlanStatus.paused.isActive, isFalse);
      expect(PlanStatus.completed.isActive, isFalse);
    });

    test('Serialization round-trip: toMap and fromMap preserve all facts exactly', () {
      final now = DateTime(2026, 10, 18, 12, 0, 0);
      final renewal = DateTime(2026, 11, 15);

      final original = ServicePlan(
        id: 'plan-serialize-1',
        clientId: 'client-101',
        title: 'Full Stack Maintenance',
        serviceNiche: 'Software & development',
        cadence: PlanCadence.quarterly,
        price: const Money(minorUnits: 450000, currency: 'USD'), // $4,500.00
        deliverables: const ['Security updates', 'Database backups', 'Uptime monitoring'],
        exclusions: const ['Net-new product architecture', 'On-call beyond 8x5'],
        revisionLimit: '1 round of feedback per release',
        status: PlanStatus.active,
        renewalDate: renewal,
        notes: 'Client renews on 15th every quarter.',
        isSynthetic: false,
        createdAt: now,
        updatedAt: now,
      );

      final map = original.toMap();
      expect(map['id'], equals('plan-serialize-1'));
      expect(map['client_id'], equals('client-101'));
      expect(map['title'], equals('Full Stack Maintenance'));
      expect(map['cadence'], equals('quarterly'));
      expect(map['price_minor_units'], equals(450000));
      expect(map['currency'], equals('USD'));
      expect(map['revision_limit'], equals('1 round of feedback per release'));
      expect(map['status'], equals('active'));
      expect(map['renewal_date'], equals('2026-11-15'));
      expect(map['is_synthetic'], equals(0));

      final restored = ServicePlan.fromMap(map);
      expect(restored.id, equals(original.id));
      expect(restored.clientId, equals(original.clientId));
      expect(restored.title, equals(original.title));
      expect(restored.serviceNiche, equals(original.serviceNiche));
      expect(restored.cadence, equals(original.cadence));
      expect(restored.priceMinorUnits, equals(original.priceMinorUnits));
      expect(restored.currency, equals(original.currency));
      expect(restored.deliverables, equals(original.deliverables));
      expect(restored.exclusions, equals(original.exclusions));
      expect(restored.revisionLimits, equals(original.revisionLimits));
      expect(restored.status, equals(original.status));
      expect(restored.renewalDate, equals(renewal));
      expect(restored.notes, equals(original.notes));
      expect(restored.isSynthetic, isFalse);
    });

    test('Calendar date normalization prevents timezone shifts', () {
      final date = DateTime.parse('2026-12-01');
      final plan = ServicePlan(
        id: 'plan-date-1',
        title: 'Video Retainer',
        serviceNiche: 'Photography & video',
        cadence: PlanCadence.monthly,
        price: const Money(minorUnits: 50000000, currency: 'NGN'),
        deliverables: const ['2 Reels/month'],
        status: PlanStatus.active,
        renewalDate: date,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final map = plan.toMap();
      expect(map['renewal_date'], equals('2026-12-01'));

      final restored = ServicePlan.fromMap(map);
      expect(restored.renewalDate!.year, equals(2026));
      expect(restored.renewalDate!.month, equals(12));
      expect(restored.renewalDate!.day, equals(1));
    });

    test('copyWith updates specified fields while keeping existing ones', () {
      final plan = ServicePlan(
        id: 'p-orig',
        title: 'Original Title',
        serviceNiche: 'Design & branding',
        cadence: PlanCadence.monthly,
        price: const Money(minorUnits: 100000, currency: 'USD'),
        deliverables: const ['Logo variations'],
        exclusions: const ['Printing'],
        revisionLimit: '1 round',
        status: PlanStatus.draft,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final updated = plan.copyWith(
        title: 'Updated Title',
        status: PlanStatus.active,
        price: const Money(minorUnits: 150000, currency: 'USD'),
      );

      expect(updated.id, equals('p-orig'));
      expect(updated.title, equals('Updated Title'));
      expect(updated.status, equals(PlanStatus.active));
      expect(updated.priceMinorUnits, equals(150000));
      expect(updated.deliverables, equals(const ['Logo variations']));
      expect(updated.exclusions, equals(const ['Printing']));
      expect(updated.revisionLimits, equals('1 round'));
    });
  });
}
