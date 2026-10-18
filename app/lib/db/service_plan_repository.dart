import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/service_plan.dart';

class ServicePlanSummary {
  final int totalPlans;
  final int activePlans;
  final int pausedPlans;
  final int draftPlans;
  final int completedPlans;
  final int cancelledPlans;
  final int renewalsDueCount;
  /// Recurring monthly revenue grouped strictly by ISO currency code.
  /// NEVER summed across currencies! e.g. {'NGN': 27000000, 'USD': 95000}
  final Map<String, int> recurringMonthlyRevenueByCurrency;
  /// Total nominal active retainer price grouped strictly by currency code
  final Map<String, int> activeNominalValueByCurrency;

  const ServicePlanSummary({
    required this.totalPlans,
    required this.activePlans,
    required this.pausedPlans,
    required this.draftPlans,
    required this.completedPlans,
    required this.cancelledPlans,
    required this.renewalsDueCount,
    required this.recurringMonthlyRevenueByCurrency,
    required this.activeNominalValueByCurrency,
  });
}

abstract class IServicePlanRepository {
  Future<List<ServicePlan>> getPlans({
    String? clientId,
    PlanStatus? status,
    PlanCadence? cadence,
    String? serviceNiche,
    bool includeSynthetic = true,
    String? searchQuery,
  });

  Future<List<ServicePlanWithClient>> getPlansWithClient({
    String? clientId,
    PlanStatus? status,
    PlanCadence? cadence,
    String? serviceNiche,
    bool includeSynthetic = true,
    String? searchQuery,
  });

  Future<ServicePlan?> getPlanById(String id);
  Future<void> createPlan(ServicePlan plan);
  Future<void> updatePlan(ServicePlan plan);
  Future<void> deletePlan(String id);
  Future<void> updatePlanStatus(String id, PlanStatus status);
  Future<Map<PlanStatus, int>> getPlanCountsByStatus({bool includeSynthetic = true});
  Future<ServicePlanSummary> getPlanSummary({
    bool includeSynthetic = true,
    DateTime? referenceDate,
  });
}

class ServicePlanRepository implements IServicePlanRepository {
  final Database db;

  ServicePlanRepository(this.db);

  @override
  Future<List<ServicePlan>> getPlans({
    String? clientId,
    PlanStatus? status,
    PlanCadence? cadence,
    String? serviceNiche,
    bool includeSynthetic = true,
    String? searchQuery,
  }) async {
    final where = <String>[];
    final args = <dynamic>[];

    if (!includeSynthetic) {
      where.add('is_synthetic = 0');
    }
    if (clientId != null) {
      where.add('client_id = ?');
      args.add(clientId);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status.dbValue);
    }
    if (cadence != null) {
      where.add('cadence = ?');
      args.add(cadence.dbValue);
    }
    if (serviceNiche != null && serviceNiche.isNotEmpty && serviceNiche != 'All niches') {
      where.add('service_niche = ?');
      args.add(serviceNiche);
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final pattern = '%${searchQuery.trim()}%';
      where.add('(title LIKE ? OR notes LIKE ? OR deliverables_json LIKE ?)');
      args.addAll([pattern, pattern, pattern]);
    }

    final rows = await db.query(
      'service_plans',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'CASE status WHEN \'active\' THEN 1 WHEN \'draft\' THEN 2 WHEN \'paused\' THEN 3 ELSE 4 END, created_at DESC',
    );
    return rows.map(ServicePlan.fromDbMap).toList();
  }

  @override
  Future<List<ServicePlanWithClient>> getPlansWithClient({
    String? clientId,
    PlanStatus? status,
    PlanCadence? cadence,
    String? serviceNiche,
    bool includeSynthetic = true,
    String? searchQuery,
  }) async {
    final where = <String>[];
    final args = <dynamic>[];

    if (!includeSynthetic) {
      where.add('p.is_synthetic = 0');
    }
    if (clientId != null) {
      where.add('p.client_id = ?');
      args.add(clientId);
    }
    if (status != null) {
      where.add('p.status = ?');
      args.add(status.dbValue);
    }
    if (cadence != null) {
      where.add('p.cadence = ?');
      args.add(cadence.dbValue);
    }
    if (serviceNiche != null && serviceNiche.isNotEmpty && serviceNiche != 'All niches') {
      where.add('p.service_niche = ?');
      args.add(serviceNiche);
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final pattern = '%${searchQuery.trim()}%';
      where.add('(p.title LIKE ? OR p.notes LIKE ? OR c.name LIKE ?)');
      args.addAll([pattern, pattern, pattern]);
    }

    final whereClause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    final sql = '''
      SELECT 
        p.*,
        c.name AS client_name,
        c.initials AS client_initials,
        c.company AS client_company
      FROM service_plans p
      LEFT JOIN clients c ON p.client_id = c.id
      $whereClause
      ORDER BY 
        CASE p.status WHEN 'active' THEN 1 WHEN 'draft' THEN 2 WHEN 'paused' THEN 3 ELSE 4 END,
        p.created_at DESC;
    ''';

    final rows = await db.rawQuery(sql, args);
    return rows.map((r) => ServicePlanWithClient(
      plan: ServicePlan.fromDbMap(r),
      clientName: r['client_name'] as String?,
      clientInitials: r['client_initials'] as String?,
      clientCompany: r['client_company'] as String?,
    )).toList();
  }

  @override
  Future<ServicePlan?> getPlanById(String id) async {
    final rows = await db.query('service_plans', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ServicePlan.fromDbMap(rows.first);
  }

  @override
  Future<void> createPlan(ServicePlan plan) async {
    await db.insert('service_plans', plan.toDbMap());
  }

  @override
  Future<void> updatePlan(ServicePlan plan) async {
    await db.update('service_plans', plan.toDbMap(), where: 'id = ?', whereArgs: [plan.id]);
  }

  @override
  Future<void> deletePlan(String id) async {
    await db.delete('service_plans', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> updatePlanStatus(String id, PlanStatus status) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'service_plans',
      {'status': status.dbValue, 'updated_at': nowIso},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<Map<PlanStatus, int>> getPlanCountsByStatus({bool includeSynthetic = true}) async {
    final synFilter = includeSynthetic ? '' : 'WHERE is_synthetic = 0';
    final rows = await db.rawQuery('''
      SELECT status, COUNT(*) as count 
      FROM service_plans 
      $synFilter 
      GROUP BY status
    ''');
    final map = <PlanStatus, int>{for (final s in PlanStatus.values) s: 0};
    for (final row in rows) {
      final status = PlanStatus.fromString(row['status'] as String);
      map[status] = (row['count'] as int?) ?? 0;
    }
    return map;
  }

  @override
  Future<ServicePlanSummary> getPlanSummary({
    bool includeSynthetic = true,
    DateTime? referenceDate,
  }) async {
    final plans = await getPlans(includeSynthetic: includeSynthetic);
    final ref = referenceDate ?? DateTime.now();
    final todayStr = ServicePlan.formatCalendarDate(ref);

    int active = 0;
    int paused = 0;
    int draft = 0;
    int completed = 0;
    int cancelled = 0;
    int renewalsDue = 0;

    final Map<String, int> monthlyRevenueByCurrency = {};
    final Map<String, int> nominalValueByCurrency = {};

    for (final p in plans) {
      switch (p.status) {
        case PlanStatus.active:
          active++;
          final curr = p.price.currency;
          nominalValueByCurrency[curr] = (nominalValueByCurrency[curr] ?? 0) + p.price.minorUnits;
          
          // Calculate monthly normalized revenue without summing across currencies
          final monthlyAmount = (p.price.minorUnits * p.cadence.monthlyFactor).round();
          monthlyRevenueByCurrency[curr] = (monthlyRevenueByCurrency[curr] ?? 0) + monthlyAmount;

          if (p.renewalDate != null) {
            final renewStr = ServicePlan.formatCalendarDate(p.renewalDate!);
            if (renewStr.compareTo(todayStr) <= 0) {
              renewalsDue++;
            }
          }
          break;
        case PlanStatus.paused:
          paused++;
          break;
        case PlanStatus.draft:
          draft++;
          break;
        case PlanStatus.completed:
          completed++;
          break;
        case PlanStatus.cancelled:
          cancelled++;
          break;
      }
    }

    return ServicePlanSummary(
      totalPlans: plans.length,
      activePlans: active,
      pausedPlans: paused,
      draftPlans: draft,
      completedPlans: completed,
      cancelledPlans: cancelled,
      renewalsDueCount: renewalsDue,
      recurringMonthlyRevenueByCurrency: monthlyRevenueByCurrency,
      activeNominalValueByCurrency: nominalValueByCurrency,
    );
  }
}
