import 'package:flutter/widgets.dart';
import 'preference_repository.dart';
import 'client_repository.dart';
import 'project_repository.dart';
import 'scope_repository.dart';
import 'demo_data_repository.dart';
import 'invoice_repository.dart';
import 'lead_repository.dart';
import 'service_plan_repository.dart';
import '../models/lead.dart';
import '../models/service_plan.dart';

class RepositoryScope extends InheritedWidget {
  final IPreferenceRepository preferenceRepo;
  final IClientRepository clientRepo;
  final IProjectRepository projectRepo;
  final IScopeRepository scopeRepo;
  final IDemoDataRepository demoDataRepo;
  final IInvoiceRepository invoiceRepo;
  final ILeadRepository leadRepo;
  final IServicePlanRepository servicePlanRepo;

  RepositoryScope({
    super.key,
    required this.preferenceRepo,
    required this.clientRepo,
    required this.projectRepo,
    required this.scopeRepo,
    required this.demoDataRepo,
    required this.invoiceRepo,
    ILeadRepository? leadRepo,
    IServicePlanRepository? servicePlanRepo,
    required super.child,
  })  : leadRepo = leadRepo ?? _defaultLeadRepo,
        servicePlanRepo = servicePlanRepo ?? _defaultServicePlanRepo;

  static final ILeadRepository _defaultLeadRepo = _NoopLeadRepository();
  static final IServicePlanRepository _defaultServicePlanRepo = _NoopServicePlanRepository();

  static RepositoryScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RepositoryScope>();
    if (scope == null) {
      throw StateError('No RepositoryScope found in BuildContext widget tree');
    }
    return scope;
  }

  @override
  bool updateShouldNotify(RepositoryScope oldWidget) => false;
}

class _NoopLeadRepository implements ILeadRepository {
  @override
  Future<void> createLead(Lead lead) async {}
  @override
  Future<void> deleteLead(String id) async {}
  @override
  Future<Lead?> getLeadById(String id) async => null;
  @override
  Future<Map<LeadStage, int>> getLeadCountsByStage({bool includeSynthetic = true}) async => {};
  @override
  Future<List<Lead>> getLeads({
    LeadStage? stage,
    String? serviceNiche,
    LeadFollowUpTiming? timing,
    bool includeSynthetic = true,
    String? searchQuery,
    DateTime? referenceDate,
  }) async => [];
  @override
  Future<LeadPipelineSummary> getPipelineSummary({bool includeSynthetic = true, DateTime? referenceDate}) async =>
      const LeadPipelineSummary(
        totalActiveLeads: 0,
        followUpsDue: 0,
        overdueCount: 0,
        dueTodayCount: 0,
        upcomingCount: 0,
        wonCount: 0,
        lostCount: 0,
        quotedValueMinorUnitsByCurrency: {},
      );
  @override
  Future<void> rescheduleFollowUp(String id, DateTime? newFollowUpDate) async {}
  @override
  Future<void> updateLead(Lead lead) async {}
  @override
  Future<void> updateLeadStage(String id, LeadStage newStage) async {}
}

class _NoopServicePlanRepository implements IServicePlanRepository {
  @override
  Future<void> createPlan(ServicePlan plan) async {}
  @override
  Future<void> deletePlan(String id) async {}
  @override
  Future<ServicePlan?> getPlanById(String id) async => null;
  @override
  Future<Map<PlanStatus, int>> getPlanCountsByStatus({bool includeSynthetic = true}) async => {};
  @override
  Future<List<ServicePlan>> getPlans({
    String? clientId,
    PlanStatus? status,
    PlanCadence? cadence,
    String? serviceNiche,
    bool includeSynthetic = true,
    String? searchQuery,
  }) async => [];
  @override
  Future<List<ServicePlanWithClient>> getPlansWithClient({
    String? clientId,
    PlanStatus? status,
    PlanCadence? cadence,
    String? serviceNiche,
    bool includeSynthetic = true,
    String? searchQuery,
  }) async => [];
  @override
  Future<ServicePlanSummary> getPlanSummary({
    bool includeSynthetic = true,
    DateTime? referenceDate,
  }) async =>
      const ServicePlanSummary(
        totalPlans: 0,
        activePlans: 0,
        pausedPlans: 0,
        draftPlans: 0,
        completedPlans: 0,
        cancelledPlans: 0,
        renewalsDueCount: 0,
        recurringMonthlyRevenueByCurrency: {},
        activeNominalValueByCurrency: {},
      );
  @override
  Future<void> updatePlan(ServicePlan plan) async {}
  @override
  Future<void> updatePlanStatus(String id, PlanStatus status) async {}
}
