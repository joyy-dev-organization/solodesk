import 'package:solodesk/db/lead_repository.dart';
import 'package:solodesk/models/lead.dart';

class FakeLeadRepository implements ILeadRepository {
  final List<Lead> _leads = [];

  List<Lead> get leads => List.unmodifiable(_leads);

  void seedLeads(List<Lead> leads) {
    _leads.clear();
    _leads.addAll(leads);
  }

  @override
  Future<List<Lead>> getLeads({
    LeadStage? stage,
    String? serviceNiche,
    LeadFollowUpTiming? timing,
    bool includeSynthetic = true,
    String? searchQuery,
    DateTime? referenceDate,
  }) async {
    final ref = referenceDate ?? DateTime.now();
    var result = List<Lead>.from(_leads);

    if (!includeSynthetic) {
      result = result.where((l) => !l.isSynthetic).toList();
    }
    if (stage != null) {
      result = result.where((l) => l.stage == stage).toList();
    }
    if (serviceNiche != null && serviceNiche.isNotEmpty && serviceNiche != 'All niches') {
      result = result.where((l) => l.serviceNiche == serviceNiche).toList();
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      result = result.where((l) {
        final matchesName = l.contactName.toLowerCase().contains(q);
        final matchesCompany = l.company?.toLowerCase().contains(q) ?? false;
        final matchesNotes = l.notes?.toLowerCase().contains(q) ?? false;
        return matchesName || matchesCompany || matchesNotes;
      }).toList();
    }
    if (timing != null) {
      result = result.where((l) => l.timingRelativeTo(ref) == timing).toList();
    }

    result.sort((a, b) {
      if (a.nextFollowUpDate == null && b.nextFollowUpDate == null) {
        return b.createdAt.compareTo(a.createdAt);
      }
      if (a.nextFollowUpDate == null) return 1;
      if (b.nextFollowUpDate == null) return -1;
      return a.nextFollowUpDate!.compareTo(b.nextFollowUpDate!);
    });

    return result;
  }

  @override
  Future<Lead?> getLeadById(String id) async {
    final match = _leads.where((l) => l.id == id);
    return match.isNotEmpty ? match.first : null;
  }

  @override
  Future<void> createLead(Lead lead) async {
    _leads.add(lead);
  }

  @override
  Future<void> updateLead(Lead lead) async {
    final idx = _leads.indexWhere((l) => l.id == lead.id);
    if (idx != -1) {
      _leads[idx] = lead;
    }
  }

  @override
  Future<void> deleteLead(String id) async {
    _leads.removeWhere((l) => l.id == id);
  }

  @override
  Future<void> updateLeadStage(String id, LeadStage newStage) async {
    final idx = _leads.indexWhere((l) => l.id == id);
    if (idx != -1) {
      _leads[idx] = _leads[idx].copyWith(stage: newStage);
    }
  }

  @override
  Future<void> rescheduleFollowUp(String id, DateTime? newFollowUpDate) async {
    final idx = _leads.indexWhere((l) => l.id == id);
    if (idx != -1) {
      _leads[idx] = _leads[idx].copyWith(
        nextFollowUpDate: newFollowUpDate,
        clearNextFollowUpDate: newFollowUpDate == null,
      );
    }
  }

  @override
  Future<Map<LeadStage, int>> getLeadCountsByStage({bool includeSynthetic = true}) async {
    final map = <LeadStage, int>{for (final s in LeadStage.values) s: 0};
    for (final l in _leads) {
      if (!includeSynthetic && l.isSynthetic) continue;
      map[l.stage] = (map[l.stage] ?? 0) + 1;
    }
    return map;
  }

  @override
  Future<LeadPipelineSummary> getPipelineSummary({
    bool includeSynthetic = true,
    DateTime? referenceDate,
  }) async {
    final ref = referenceDate ?? DateTime.now();
    final active = _leads.where((l) => (!l.isSynthetic || includeSynthetic) && l.stage.isActive).toList();
    final won = _leads.where((l) => (!l.isSynthetic || includeSynthetic) && l.stage == LeadStage.won).toList();
    final lost = _leads.where((l) => (!l.isSynthetic || includeSynthetic) && l.stage == LeadStage.lost).toList();

    int overdue = 0;
    int dueToday = 0;
    int upcoming = 0;
    final Map<String, int> valueByCurrency = {};

    for (final l in active) {
      final timing = l.timingRelativeTo(ref);
      if (timing == LeadFollowUpTiming.overdue) overdue++;
      if (timing == LeadFollowUpTiming.dueToday) dueToday++;
      if (timing == LeadFollowUpTiming.upcoming) upcoming++;

      if (l.estimatedValue != null) {
        final c = l.estimatedValue!.currency;
        valueByCurrency[c] = (valueByCurrency[c] ?? 0) + l.estimatedValue!.minorUnits;
      }
    }

    return LeadPipelineSummary(
      totalActiveLeads: active.length,
      followUpsDue: overdue + dueToday,
      overdueCount: overdue,
      dueTodayCount: dueToday,
      upcomingCount: upcoming,
      wonCount: won.length,
      lostCount: lost.length,
      quotedValueMinorUnitsByCurrency: valueByCurrency,
    );
  }
}
