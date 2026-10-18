import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/lead.dart';

class LeadPipelineSummary {
  final int totalActiveLeads;
  final int followUpsDue;
  final int overdueCount;
  final int dueTodayCount;
  final int upcomingCount;
  final int wonCount;
  final int lostCount;
  final Map<String, int> quotedValueMinorUnitsByCurrency;

  const LeadPipelineSummary({
    required this.totalActiveLeads,
    required this.followUpsDue,
    required this.overdueCount,
    required this.dueTodayCount,
    required this.upcomingCount,
    required this.wonCount,
    required this.lostCount,
    required this.quotedValueMinorUnitsByCurrency,
  });
}

abstract class ILeadRepository {
  Future<List<Lead>> getLeads({
    LeadStage? stage,
    String? serviceNiche,
    LeadFollowUpTiming? timing,
    bool includeSynthetic = true,
    String? searchQuery,
    DateTime? referenceDate,
  });

  Future<Lead?> getLeadById(String id);
  Future<void> createLead(Lead lead);
  Future<void> updateLead(Lead lead);
  Future<void> deleteLead(String id);
  Future<void> updateLeadStage(String id, LeadStage newStage);
  Future<void> rescheduleFollowUp(String id, DateTime? newFollowUpDate);
  Future<Map<LeadStage, int>> getLeadCountsByStage({bool includeSynthetic = true});
  Future<LeadPipelineSummary> getPipelineSummary({bool includeSynthetic = true, DateTime? referenceDate});
}

class LeadRepository implements ILeadRepository {
  final Database db;

  LeadRepository(this.db);

  @override
  Future<List<Lead>> getLeads({
    LeadStage? stage,
    String? serviceNiche,
    LeadFollowUpTiming? timing,
    bool includeSynthetic = true,
    String? searchQuery,
    DateTime? referenceDate,
  }) async {
    final where = <String>[];
    final args = <dynamic>[];

    if (!includeSynthetic) {
      where.add('is_synthetic = 0');
    }
    if (stage != null) {
      where.add('stage = ?');
      args.add(stage.dbValue);
    }
    if (serviceNiche != null && serviceNiche.isNotEmpty && serviceNiche != 'All niches') {
      where.add('service_niche = ?');
      args.add(serviceNiche);
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final pattern = '%${searchQuery.trim()}%';
      where.add('(contact_name LIKE ? OR company LIKE ? OR notes LIKE ?)');
      args.addAll([pattern, pattern, pattern]);
    }

    final ref = referenceDate ?? DateTime.now();
    final todayStr = Lead.formatCalendarDate(ref);

    if (timing != null) {
      switch (timing) {
        case LeadFollowUpTiming.overdue:
          where.add('stage NOT IN (\'won\', \'lost\') AND next_follow_up_date IS NOT NULL AND next_follow_up_date < ?');
          args.add(todayStr);
          break;
        case LeadFollowUpTiming.dueToday:
          where.add('stage NOT IN (\'won\', \'lost\') AND next_follow_up_date = ?');
          args.add(todayStr);
          break;
        case LeadFollowUpTiming.upcoming:
          where.add('stage NOT IN (\'won\', \'lost\') AND next_follow_up_date IS NOT NULL AND next_follow_up_date > ?');
          args.add(todayStr);
          break;
        case LeadFollowUpTiming.none:
          where.add('next_follow_up_date IS NULL');
          break;
      }
    }

    final rows = await db.query(
      'leads',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'CASE WHEN next_follow_up_date IS NULL THEN 1 ELSE 0 END, next_follow_up_date ASC, created_at DESC',
    );
    return rows.map(Lead.fromDbMap).toList();
  }

  @override
  Future<Lead?> getLeadById(String id) async {
    final rows = await db.query('leads', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Lead.fromDbMap(rows.first);
  }

  @override
  Future<void> createLead(Lead lead) async {
    await db.insert('leads', lead.toDbMap());
  }

  @override
  Future<void> updateLead(Lead lead) async {
    await db.update('leads', lead.toDbMap(), where: 'id = ?', whereArgs: [lead.id]);
  }

  @override
  Future<void> deleteLead(String id) async {
    await db.delete('leads', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> updateLeadStage(String id, LeadStage newStage) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'leads',
      {'stage': newStage.dbValue, 'updated_at': nowIso},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> rescheduleFollowUp(String id, DateTime? newFollowUpDate) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final dateStr = newFollowUpDate != null ? Lead.formatCalendarDate(newFollowUpDate) : null;
    await db.update(
      'leads',
      {'next_follow_up_date': dateStr, 'updated_at': nowIso},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<Map<LeadStage, int>> getLeadCountsByStage({bool includeSynthetic = true}) async {
    final synFilter = includeSynthetic ? '' : 'WHERE is_synthetic = 0';
    final rows = await db.rawQuery('''
      SELECT stage, COUNT(*) as count 
      FROM leads 
      $synFilter 
      GROUP BY stage
    ''');
    final map = <LeadStage, int>{for (final s in LeadStage.values) s: 0};
    for (final row in rows) {
      final stage = LeadStage.fromString(row['stage'] as String);
      map[stage] = (row['count'] as int?) ?? 0;
    }
    return map;
  }

  @override
  Future<LeadPipelineSummary> getPipelineSummary({
    bool includeSynthetic = true,
    DateTime? referenceDate,
  }) async {
    final ref = referenceDate ?? DateTime.now();
    final todayStr = Lead.formatCalendarDate(ref);

    final leads = await getLeads(includeSynthetic: includeSynthetic, referenceDate: ref);
    final active = leads.where((l) => l.stage.isActive).toList();
    final won = leads.where((l) => l.stage == LeadStage.won).toList();
    final lost = leads.where((l) => l.stage == LeadStage.lost).toList();

    int overdue = 0;
    int dueToday = 0;
    int upcoming = 0;
    final Map<String, int> valueByCurrency = {};

    for (final l in active) {
      if (l.nextFollowUpDate != null) {
        final followStr = Lead.formatCalendarDate(l.nextFollowUpDate!);
        if (followStr == todayStr) {
          dueToday++;
        } else if (followStr.compareTo(todayStr) < 0) {
          overdue++;
        } else {
          upcoming++;
        }
      }

      if (l.estimatedValue != null) {
        final curr = l.estimatedValue!.currency;
        valueByCurrency[curr] = (valueByCurrency[curr] ?? 0) + l.estimatedValue!.minorUnits;
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
