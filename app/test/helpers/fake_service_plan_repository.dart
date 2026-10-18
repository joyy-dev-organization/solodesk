import 'package:solodesk/db/service_plan_repository.dart';
import 'package:solodesk/models/service_plan.dart';

class FakeServicePlanRepository implements IServicePlanRepository {
  final List<ServicePlan> plans = [];
  Map<String, String> clientNamesById = {};

  void seedPlans(List<ServicePlan> initialPlans) {
    plans.addAll(initialPlans);
  }

  @override
  Future<void> createPlan(ServicePlan plan) async {
    plans.removeWhere((p) => p.id == plan.id);
    plans.add(plan);
  }

  @override
  Future<void> deletePlan(String id) async {
    plans.removeWhere((p) => p.id == id);
  }

  @override
  Future<ServicePlan?> getPlanById(String id) async {
    try {
      return plans.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<PlanStatus, int>> getPlanCountsByStatus({bool includeSynthetic = true}) async {
    final map = <PlanStatus, int>{for (final s in PlanStatus.values) s: 0};
    for (final p in plans) {
      if (!includeSynthetic && p.isSynthetic) continue;
      map[p.status] = (map[p.status] ?? 0) + 1;
    }
    return map;
  }

  @override
  Future<List<ServicePlan>> getPlans({
    String? clientId,
    PlanStatus? status,
    PlanCadence? cadence,
    String? serviceNiche,
    bool includeSynthetic = true,
    String? searchQuery,
  }) async {
    return plans.where((p) {
      if (!includeSynthetic && p.isSynthetic) return false;
      if (clientId != null && p.clientId != clientId) return false;
      if (status != null && p.status != status) return false;
      if (cadence != null && p.cadence != cadence) return false;
      if (serviceNiche != null && serviceNiche.isNotEmpty && serviceNiche != 'All niches' && p.serviceNiche != serviceNiche) {
        return false;
      }
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.toLowerCase();
        final matchTitle = p.title.toLowerCase().contains(q);
        final matchNotes = (p.notes ?? '').toLowerCase().contains(q);
        final matchDeliv = p.deliverables.any((d) => d.toLowerCase().contains(q));
        if (!matchTitle && !matchNotes && !matchDeliv) return false;
      }
      return true;
    }).toList();
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
    final matchingPlans = await getPlans(
      clientId: clientId,
      status: status,
      cadence: cadence,
      serviceNiche: serviceNiche,
      includeSynthetic: includeSynthetic,
      searchQuery: searchQuery,
    );

    return matchingPlans.map((p) {
      final name = p.clientId != null ? clientNamesById[p.clientId!] : null;
      return ServicePlanWithClient(
        plan: p,
        clientName: name,
        clientInitials: name != null && name.isNotEmpty ? name.substring(0, 1).toUpperCase() : null,
      );
    }).toList();
  }

  @override
  Future<ServicePlanSummary> getPlanSummary({
    bool includeSynthetic = true,
    DateTime? referenceDate,
  }) async {
    final matching = await getPlans(includeSynthetic: includeSynthetic);
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

    for (final p in matching) {
      switch (p.status) {
        case PlanStatus.active:
          active++;
          final curr = p.price.currency;
          nominalValueByCurrency[curr] = (nominalValueByCurrency[curr] ?? 0) + p.price.minorUnits;
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
      totalPlans: matching.length,
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

  @override
  Future<void> updatePlan(ServicePlan plan) async {
    final idx = plans.indexWhere((p) => p.id == plan.id);
    if (idx != -1) {
      plans[idx] = plan;
    }
  }

  @override
  Future<void> updatePlanStatus(String id, PlanStatus status) async {
    final idx = plans.indexWhere((p) => p.id == id);
    if (idx != -1) {
      plans[idx] = plans[idx].copyWith(status: status);
    }
  }
}
