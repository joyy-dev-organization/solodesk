import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../db/repository_scope.dart';
import '../db/lead_repository.dart';
import '../models/lead.dart';
import '../models/money.dart';
import '../models/client.dart';
import '../models/service_preference.dart';
import '../theme/colors.dart';
import '../widgets/stat_card.dart';

class LeadLoopScreen extends StatefulWidget {
  final bool isSyntheticDemoActive;
  final ValueChanged<int>? onNavigate;

  const LeadLoopScreen({
    super.key,
    this.isSyntheticDemoActive = false,
    this.onNavigate,
  });

  @override
  State<LeadLoopScreen> createState() => _LeadLoopScreenState();
}

class _LeadLoopScreenState extends State<LeadLoopScreen> {
  List<Lead> _leads = [];
  LeadPipelineSummary? _summary;
  Map<LeadStage, int> _stageCounts = {};
  LeadStage? _selectedStage;
  LeadFollowUpTiming? _selectedTiming;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  ServicePreference _preference = ServicePreference.initial();
  List<Client> _availableClients = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => loadData());
  }

  @override
  void didUpdateWidget(covariant LeadLoopScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSyntheticDemoActive != widget.isSyntheticDemoActive) {
      loadData();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final scope = RepositoryScope.of(context);
      final pref = await scope.preferenceRepo.getPreferences();
      final clients = await scope.clientRepo.getClients(
        includeSynthetic: widget.isSyntheticDemoActive,
      );
      final leads = await scope.leadRepo.getLeads(
        stage: _selectedStage,
        timing: _selectedTiming,
        searchQuery: _searchQuery,
        includeSynthetic: widget.isSyntheticDemoActive,
      );
      final summary = await scope.leadRepo.getPipelineSummary(
        includeSynthetic: widget.isSyntheticDemoActive,
      );
      final counts = await scope.leadRepo.getLeadCountsByStage(
        includeSynthetic: widget.isSyntheticDemoActive,
      );

      if (mounted) {
        setState(() {
          _preference = pref;
          _availableClients = clients;
          _leads = leads;
          _summary = summary;
          _stageCounts = counts;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showAddLeadDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _CreateLeadDialog(
        preference: _preference,
        availableClients: _availableClients,
        isSynthetic: widget.isSyntheticDemoActive,
        onCreated: (lead) async {
          final scope = RepositoryScope.of(context);
          await scope.leadRepo.createLead(lead);
          await loadData();
        },
      ),
    );
  }

  void _showEditLeadDialog(Lead lead) {
    showDialog(
      context: context,
      builder: (ctx) => _EditLeadDialog(
        lead: lead,
        preference: _preference,
        availableClients: _availableClients,
        onUpdated: (updated) async {
          final scope = RepositoryScope.of(context);
          await scope.leadRepo.updateLead(updated);
          await loadData();
        },
      ),
    );
  }

  void _showFollowUpDraftModal(Lead lead) {
    showDialog(
      context: context,
      builder: (ctx) => _FollowUpDraftModal(lead: lead),
    );
  }

  Future<void> _advanceLeadStage(Lead lead) async {
    LeadStage? nextStage;
    switch (lead.stage) {
      case LeadStage.discovery:
        nextStage = LeadStage.proposalSent;
        break;
      case LeadStage.proposalSent:
        nextStage = LeadStage.inDiscussion;
        break;
      case LeadStage.inDiscussion:
        nextStage = LeadStage.won;
        break;
      case LeadStage.won:
      case LeadStage.lost:
        return;
    }

    final scope = RepositoryScope.of(context);
    await scope.leadRepo.updateLeadStage(lead.id, nextStage);
    await loadData();
  }

  Future<void> _deleteLead(Lead lead) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Lead'),
        content: Text('Are you sure you want to delete "${lead.displayName}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: SoloDeskColors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final scope = RepositoryScope.of(context);
      await scope.leadRepo.deleteLead(lead.id);
      await loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary ??
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

    return Scaffold(
      backgroundColor: SoloDeskColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildBoundaryBanner(),
            const SizedBox(height: 24),
            _buildMetricsGrid(summary),
            const SizedBox(height: 24),
            _buildFiltersAndSearchBar(),
            const SizedBox(height: 16),
            _buildLeadsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PROSPECT PIPELINE · LOCAL PLANNING ONLY',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                  color: SoloDeskColors.primaryLight,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Text(
                    'LeadLoop ✦',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: SoloDeskColors.ink,
                    ),
                  ),
                  if (widget.isSyntheticDemoActive) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: SoloDeskColors.primaryPale,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: SoloDeskColors.primaryLight.withValues(alpha: 0.3)),
                      ),
                      child: const Text(
                        'DEMO ACTIVE',
                        style: TextStyle(
                          color: SoloDeskColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Track inbound client conversations, schedule follow-ups, and review pipeline stages locally.',
                style: TextStyle(fontSize: 13, color: SoloDeskColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Row(
          children: [
            OutlinedButton.icon(
              icon: _isLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
              onPressed: _isLoading ? null : loadData,
              style: OutlinedButton.styleFrom(
                foregroundColor: SoloDeskColors.ink,
                side: const BorderSide(color: SoloDeskColors.borderLine),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Lead'),
              onPressed: _showAddLeadDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: SoloDeskColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBoundaryBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: SoloDeskColors.primaryPale,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SoloDeskColors.primaryLight.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: const [
          Icon(Icons.shield_outlined, color: SoloDeskColors.primary, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'SoloDesk Boundary Policy: SoloDesk never sends messages, contacts leads, or assigns probability/forecasted revenue claims. All pipeline records, quoted values, and follow-up drafts are strictly for your local planning and manual review.',
              style: TextStyle(fontSize: 12, color: SoloDeskColors.ink, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(LeadPipelineSummary summary) {
    // Format segregated pipeline totals
    String quotedDisplay = 'None';
    if (summary.quotedValueMinorUnitsByCurrency.isNotEmpty) {
      final formatted = summary.quotedValueMinorUnitsByCurrency.entries.map((e) {
        final money = Money(minorUnits: e.value, currency: e.key);
        return money.formattedGrouped;
      }).join(' · ');
      quotedDisplay = formatted;
    }

    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Open leads',
            value: summary.totalActiveLeads.toString().padLeft(2, '0'),
            note: widget.isSyntheticDemoActive ? 'Includes demo records' : 'Real saved records',
            icon: Icons.people_outline,
            iconColor: SoloDeskColors.blue,
            iconBgColor: SoloDeskColors.blueBg,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            label: 'Follow-ups due',
            value: summary.followUpsDue.toString().padLeft(2, '0'),
            note: summary.overdueCount > 0
                ? '${summary.overdueCount} overdue · ${summary.dueTodayCount} due today'
                : 'Today or earlier',
            icon: Icons.access_time_outlined,
            iconColor: summary.followUpsDue > 0 ? SoloDeskColors.red : SoloDeskColors.amber,
            iconBgColor: summary.followUpsDue > 0 ? SoloDeskColors.redBg : SoloDeskColors.amberBg,
          ),
        ),
        Expanded(
          flex: 2,
          child: StatCard(
            label: 'Quoted pipeline',
            value: quotedDisplay,
            note: 'Unweighted nominal quotes (no probability claims)',
            icon: Icons.receipt_long_outlined,
            iconColor: SoloDeskColors.primary,
            iconBgColor: SoloDeskColors.primaryPale,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            label: 'Won deals',
            value: summary.wonCount.toString().padLeft(2, '0'),
            note: 'Closed successfully',
            icon: Icons.check_circle_outline,
            iconColor: SoloDeskColors.green,
            iconBgColor: SoloDeskColors.greenBg,
          ),
        ),
      ],
    );
  }

  Widget _buildFiltersAndSearchBar() {
    final allCount = _stageCounts.values.fold<int>(0, (a, b) => a + b);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildStageFilterChip(label: 'All ($allCount)', stage: null),
                    _buildStageFilterChip(
                      label: 'Discovery (${_stageCounts[LeadStage.discovery] ?? 0})',
                      stage: LeadStage.discovery,
                    ),
                    _buildStageFilterChip(
                      label: 'Proposal sent (${_stageCounts[LeadStage.proposalSent] ?? 0})',
                      stage: LeadStage.proposalSent,
                    ),
                    _buildStageFilterChip(
                      label: 'In discussion (${_stageCounts[LeadStage.inDiscussion] ?? 0})',
                      stage: LeadStage.inDiscussion,
                    ),
                    _buildStageFilterChip(
                      label: 'Won (${_stageCounts[LeadStage.won] ?? 0})',
                      stage: LeadStage.won,
                    ),
                    _buildStageFilterChip(
                      label: 'Lost (${_stageCounts[LeadStage.lost] ?? 0})',
                      stage: LeadStage.lost,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: SoloDeskColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SoloDeskColors.borderLine),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<LeadFollowUpTiming?>(
                  value: _selectedTiming,
                  hint: const Text('All timing', style: TextStyle(fontSize: 12)),
                  icon: const Icon(Icons.arrow_drop_down, size: 18),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All timing', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(
                      value: LeadFollowUpTiming.overdue,
                      child: Text('Overdue', style: TextStyle(fontSize: 12, color: SoloDeskColors.red)),
                    ),
                    DropdownMenuItem(
                      value: LeadFollowUpTiming.dueToday,
                      child: Text('Due today', style: TextStyle(fontSize: 12, color: SoloDeskColors.amber)),
                    ),
                    DropdownMenuItem(
                      value: LeadFollowUpTiming.upcoming,
                      child: Text('Upcoming', style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: LeadFollowUpTiming.none,
                      child: Text('No date set', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedTiming = val);
                    loadData();
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search leads by contact name, company or notes...',
            prefixIcon: const Icon(Icons.search, size: 18, color: SoloDeskColors.muted),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                      loadData();
                    },
                  )
                : null,
            filled: true,
            fillColor: SoloDeskColors.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: SoloDeskColors.borderLine),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: SoloDeskColors.borderLine),
            ),
          ),
          onChanged: (val) {
            setState(() => _searchQuery = val);
            loadData();
          },
        ),
      ],
    );
  }

  Widget _buildStageFilterChip({required String label, required LeadStage? stage}) {
    final isSelected = _selectedStage == stage;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Text(label),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? SoloDeskColors.primary : SoloDeskColors.ink,
        ),
        backgroundColor: SoloDeskColors.surface,
        selectedColor: SoloDeskColors.primaryPale,
        side: BorderSide(
          color: isSelected ? SoloDeskColors.primary : SoloDeskColors.borderLine,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onSelected: (_) {
          setState(() => _selectedStage = stage);
          loadData();
        },
      ),
    );
  }

  Widget _buildLeadsList() {
    if (_leads.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          color: SoloDeskColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SoloDeskColors.borderLine),
        ),
        child: Column(
          children: [
            const Icon(Icons.people_outline, size: 48, color: SoloDeskColors.muted),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty || _selectedStage != null || _selectedTiming != null
                  ? 'No leads match your filter or search criteria'
                  : 'No leads in your pipeline yet',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: SoloDeskColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty || _selectedStage != null || _selectedTiming != null
                  ? 'Try clearing your search query or selecting a different stage.'
                  : 'Add prospective client conversations to track follow-up dates locally on your Windows desktop.',
              style: const TextStyle(fontSize: 13, color: SoloDeskColors.muted),
            ),
            const SizedBox(height: 16),
            if (_searchQuery.isNotEmpty || _selectedStage != null || _selectedTiming != null)
              OutlinedButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _selectedStage = null;
                    _selectedTiming = null;
                  });
                  loadData();
                },
                child: const Text('Clear Filters'),
              )
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add your first lead'),
                onPressed: _showAddLeadDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: SoloDeskColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _leads.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (ctx, index) {
        final lead = _leads[index];
        return _buildLeadCard(lead);
      },
    );
  }

  Widget _buildLeadCard(Lead lead) {
    final timing = lead.timingRelativeTo(DateTime.now());
    final isOverdue = timing == LeadFollowUpTiming.overdue;
    final isDueToday = timing == LeadFollowUpTiming.dueToday;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SoloDeskColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOverdue
              ? SoloDeskColors.redBorder
              : (isDueToday ? SoloDeskColors.amberBorder : SoloDeskColors.borderLine),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: SoloDeskColors.blueBg,
                child: Text(
                  lead.contactName.isNotEmpty
                      ? lead.contactName.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join()
                      : '?',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: SoloDeskColors.blue,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          lead.displayName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: SoloDeskColors.ink,
                          ),
                        ),
                        if (lead.isSynthetic) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: SoloDeskColors.primaryPale,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: SoloDeskColors.primaryLight.withValues(alpha: 0.3)),
                            ),
                            child: const Text(
                              'DEMO RECORD',
                              style: TextStyle(
                                color: SoloDeskColors.primary,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: SoloDeskColors.background,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            lead.serviceNiche,
                            style: const TextStyle(
                              fontSize: 11,
                              color: SoloDeskColors.muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (lead.email != null && lead.email!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            '· ${lead.email}',
                            style: const TextStyle(fontSize: 11, color: SoloDeskColors.muted),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              _buildStageChip(lead),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18, color: SoloDeskColors.muted),
                onSelected: (val) {
                  switch (val) {
                    case 'edit':
                      _showEditLeadDialog(lead);
                      break;
                    case 'draft':
                      _showFollowUpDraftModal(lead);
                      break;
                    case 'delete':
                      _deleteLead(lead);
                      break;
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit lead details')),
                  const PopupMenuItem(value: 'draft', child: Text('Draft follow-up message')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete lead', style: TextStyle(color: SoloDeskColors.red)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: SoloDeskColors.borderLine),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.attach_money, size: 16, color: SoloDeskColors.muted),
                  const SizedBox(width: 4),
                  Text(
                    lead.estimatedValue != null
                        ? 'Quoted: ${lead.estimatedValue!.formattedGrouped}'
                        : 'No quoted value discussed yet',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: lead.estimatedValue != null ? FontWeight.w600 : FontWeight.w400,
                      color: lead.estimatedValue != null ? SoloDeskColors.ink : SoloDeskColors.muted,
                    ),
                  ),
                ],
              ),
              _buildFollowUpUrgencyBadge(lead),
            ],
          ),
          if (lead.notes != null && lead.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: SoloDeskColors.background,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                lead.notes!,
                style: const TextStyle(fontSize: 12, color: SoloDeskColors.ink, height: 1.3),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.mail_outline, size: 14),
                label: const Text('Draft Follow-up', style: TextStyle(fontSize: 12)),
                onPressed: () => _showFollowUpDraftModal(lead),
                style: TextButton.styleFrom(foregroundColor: SoloDeskColors.primary),
              ),
              if (lead.stage.isActive && lead.stage != LeadStage.won) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_forward, size: 14),
                  label: const Text('Advance Stage', style: TextStyle(fontSize: 12)),
                  onPressed: () => _advanceLeadStage(lead),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SoloDeskColors.ink,
                    side: const BorderSide(color: SoloDeskColors.borderLine),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStageChip(Lead lead) {
    Color bg;
    Color fg;
    Color border;

    switch (lead.stage) {
      case LeadStage.discovery:
        bg = SoloDeskColors.blueBg;
        fg = SoloDeskColors.blue;
        border = SoloDeskColors.blueBorder;
        break;
      case LeadStage.proposalSent:
        bg = SoloDeskColors.primaryPale;
        fg = SoloDeskColors.primary;
        border = SoloDeskColors.primaryLight.withValues(alpha: 0.3);
        break;
      case LeadStage.inDiscussion:
        bg = SoloDeskColors.amberBg;
        fg = SoloDeskColors.amber;
        border = SoloDeskColors.amberBorder;
        break;
      case LeadStage.won:
        bg = SoloDeskColors.greenBg;
        fg = SoloDeskColors.green;
        border = SoloDeskColors.greenBorder;
        break;
      case LeadStage.lost:
        bg = SoloDeskColors.background;
        fg = SoloDeskColors.muted;
        border = SoloDeskColors.borderLine;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        lead.stage.displayName,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _buildFollowUpUrgencyBadge(Lead lead) {
    if (lead.nextFollowUpDate == null) {
      return const Text(
        'No follow-up date',
        style: TextStyle(fontSize: 12, color: SoloDeskColors.muted),
      );
    }

    final dateStr = Lead.formatCalendarDate(lead.nextFollowUpDate!);
    final timing = lead.timingRelativeTo(DateTime.now());

    Color bg;
    Color fg;
    String prefix;

    switch (timing) {
      case LeadFollowUpTiming.overdue:
        bg = SoloDeskColors.redBg;
        fg = SoloDeskColors.red;
        prefix = 'OVERDUE · ';
        break;
      case LeadFollowUpTiming.dueToday:
        bg = SoloDeskColors.amberBg;
        fg = SoloDeskColors.amber;
        prefix = 'DUE TODAY · ';
        break;
      case LeadFollowUpTiming.upcoming:
        bg = SoloDeskColors.blueBg;
        fg = SoloDeskColors.blue;
        prefix = 'Follow-up: ';
        break;
      case LeadFollowUpTiming.none:
        bg = SoloDeskColors.background;
        fg = SoloDeskColors.muted;
        prefix = '';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$prefix$dateStr',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create Lead Dialog
// ---------------------------------------------------------------------------
class _CreateLeadDialog extends StatefulWidget {
  final ServicePreference preference;
  final List<Client> availableClients;
  final bool isSynthetic;
  final ValueChanged<Lead> onCreated;

  const _CreateLeadDialog({
    required this.preference,
    required this.availableClients,
    required this.isSynthetic,
    required this.onCreated,
  });

  @override
  State<_CreateLeadDialog> createState() => _CreateLeadDialogState();
}

class _CreateLeadDialogState extends State<_CreateLeadDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _companyController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  late String _selectedNiche;
  LeadStage _selectedStage = LeadStage.discovery;
  late String _selectedCurrency;
  DateTime? _selectedFollowUpDate;
  String? _selectedClientId;

  @override
  void initState() {
    super.initState();
    _selectedNiche = widget.preference.niches.isNotEmpty
        ? widget.preference.niches.first
        : 'Design & branding';
    _selectedCurrency = widget.preference.defaultCurrency;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Money? estimatedValue;
    final amountText = _amountController.text.trim();
    if (amountText.isNotEmpty) {
      final val = double.tryParse(amountText);
      if (val != null) {
        estimatedValue = Money(
          minorUnits: (val * 100).round(),
          currency: _selectedCurrency,
        );
      }
    }

    final now = DateTime.now().toUtc();
    final lead = Lead(
      id: const Uuid().v4(),
      clientId: _selectedClientId,
      contactName: _nameController.text.trim(),
      company: _companyController.text.trim().isNotEmpty ? _companyController.text.trim() : null,
      email: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
      phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
      serviceNiche: _selectedNiche,
      stage: _selectedStage,
      estimatedValue: estimatedValue,
      nextFollowUpDate: _selectedFollowUpDate,
      notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
      isSynthetic: widget.isSynthetic,
      createdAt: now,
      updatedAt: now,
    );

    widget.onCreated(lead);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final allNiches = {
      ...widget.preference.niches,
      'Design & branding',
      'Writing & content',
      'Software & development',
      'Marketing & social media',
      'Consulting & coaching',
      'Photography & video',
      'Other',
    }.toList();
    if (!allNiches.contains(_selectedNiche)) {
      allNiches.add(_selectedNiche);
    }

    final currencyMap = <String, String>{
      'NGN': 'NGN (₦)',
      'USD': 'USD (\$)',
      'EUR': 'EUR (€)',
      'GBP': 'GBP (£)',
      'KES': 'KES (KSh)',
      'GHS': 'GHS (GH₵)',
      'ZAR': 'ZAR (R)',
      'CAD': 'CAD (CA\$)',
      'AUD': 'AUD (A\$)',
    };
    if (!currencyMap.containsKey(_selectedCurrency)) {
      currencyMap[_selectedCurrency] = _selectedCurrency;
    }

    return AlertDialog(
      title: const Text('Add Prospective Lead'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Contact / Prospect Name *',
                    hintText: 'e.g. Amina Musa or Studio Contact',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Contact name is required'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _companyController,
                        decoration: const InputDecoration(
                          labelText: 'Company / Brand (Optional)',
                          hintText: 'e.g. Musa Brand Lab',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedNiche,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Service Niche *'),
                        items: allNiches
                            .map((n) => DropdownMenuItem(value: n, child: Text(n, style: const TextStyle(fontSize: 13))))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedNiche = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<LeadStage>(
                        initialValue: _selectedStage,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Pipeline Stage *'),
                        items: LeadStage.values
                            .map((s) => DropdownMenuItem(value: s, child: Text(s.displayName)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedStage = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: widget.availableClients.any((c) => c.id == _selectedClientId)
                            ? _selectedClientId
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Link Existing Client (Optional)'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('None (New Prospect)')),
                          ...widget.availableClients.map(
                            (c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                          ),
                        ],
                        onChanged: (val) => setState(() => _selectedClientId = val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Quoted / Estimated Value (Optional)',
                          hintText: 'e.g. 150000',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final clean = v.trim();
                          if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(clean)) {
                            return 'Enter a valid non-negative amount (max 2 decimals)';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedCurrency,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Currency'),
                        items: currencyMap.entries
                            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedCurrency = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(
                          _selectedFollowUpDate != null
                              ? 'Follow-up: ${Lead.formatCalendarDate(_selectedFollowUpDate!)}'
                              : 'Set Follow-up Date (Optional)',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedFollowUpDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setState(() => _selectedFollowUpDate = Lead.toCalendarDate(picked));
                          }
                        },
                      ),
                    ),
                    if (_selectedFollowUpDate != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _selectedFollowUpDate = null),
                        tooltip: 'Clear follow-up date',
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Enquiry Notes (Optional)',
                    hintText: 'e.g. Scope discussed, client requested review before quote.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: SoloDeskColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save Lead'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Edit Lead Dialog
// ---------------------------------------------------------------------------
class _EditLeadDialog extends StatefulWidget {
  final Lead lead;
  final ServicePreference preference;
  final List<Client> availableClients;
  final ValueChanged<Lead> onUpdated;

  const _EditLeadDialog({
    required this.lead,
    required this.preference,
    required this.availableClients,
    required this.onUpdated,
  });

  @override
  State<_EditLeadDialog> createState() => _EditLeadDialogState();
}

class _EditLeadDialogState extends State<_EditLeadDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _companyController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;

  late String _selectedNiche;
  late LeadStage _selectedStage;
  late String _selectedCurrency;
  DateTime? _selectedFollowUpDate;
  String? _selectedClientId;

  @override
  void initState() {
    super.initState();
    final l = widget.lead;
    _nameController = TextEditingController(text: l.contactName);
    _companyController = TextEditingController(text: l.company ?? '');
    _emailController = TextEditingController(text: l.email ?? '');
    _phoneController = TextEditingController(text: l.phone ?? '');
    _amountController = TextEditingController(
      text: l.estimatedValue != null ? (l.estimatedValue!.minorUnits / 100).toStringAsFixed(2) : '',
    );
    _notesController = TextEditingController(text: l.notes ?? '');

    _selectedNiche = l.serviceNiche;
    _selectedStage = l.stage;
    _selectedCurrency = l.estimatedValue?.currency ?? widget.preference.defaultCurrency;
    _selectedFollowUpDate = l.nextFollowUpDate;
    _selectedClientId = l.clientId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Money? estimatedValue;
    final amountText = _amountController.text.trim();
    if (amountText.isNotEmpty) {
      final val = double.tryParse(amountText);
      if (val != null) {
        estimatedValue = Money(
          minorUnits: (val * 100).round(),
          currency: _selectedCurrency,
        );
      }
    }

    final updated = widget.lead.copyWith(
      clientId: _selectedClientId,
      contactName: _nameController.text.trim(),
      company: _companyController.text.trim().isNotEmpty ? _companyController.text.trim() : null,
      email: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
      phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
      serviceNiche: _selectedNiche,
      stage: _selectedStage,
      estimatedValue: estimatedValue,
      clearEstimatedValue: estimatedValue == null,
      nextFollowUpDate: _selectedFollowUpDate,
      clearNextFollowUpDate: _selectedFollowUpDate == null,
      notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
    );

    widget.onUpdated(updated);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final allNiches = {
      ...widget.preference.niches,
      'Design & branding',
      'Writing & content',
      'Software & development',
      'Marketing & social media',
      'Consulting & coaching',
      'Photography & video',
      'Other',
    }.toList();
    if (!allNiches.contains(_selectedNiche)) {
      allNiches.add(_selectedNiche);
    }

    final currencyMap = <String, String>{
      'NGN': 'NGN (₦)',
      'USD': 'USD (\$)',
      'EUR': 'EUR (€)',
      'GBP': 'GBP (£)',
      'KES': 'KES (KSh)',
      'GHS': 'GHS (GH₵)',
      'ZAR': 'ZAR (R)',
      'CAD': 'CAD (CA\$)',
      'AUD': 'AUD (A\$)',
    };
    if (!currencyMap.containsKey(_selectedCurrency)) {
      currencyMap[_selectedCurrency] = _selectedCurrency;
    }

    return AlertDialog(
      title: const Text('Edit Lead Details'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Contact / Prospect Name *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Contact name is required' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _companyController,
                        decoration: const InputDecoration(labelText: 'Company / Brand (Optional)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: allNiches.contains(_selectedNiche) ? _selectedNiche : 'Other',
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Service Niche *'),
                        items: allNiches
                            .map((n) => DropdownMenuItem(value: n, child: Text(n, style: const TextStyle(fontSize: 13))))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedNiche = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<LeadStage>(
                        initialValue: _selectedStage,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Pipeline Stage *'),
                        items: LeadStage.values
                            .map((s) => DropdownMenuItem(value: s, child: Text(s.displayName)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedStage = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: widget.availableClients.any((c) => c.id == _selectedClientId)
                            ? _selectedClientId
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Link Client (Optional)'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('None (Prospect)')),
                          ...widget.availableClients.map(
                            (c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                          ),
                        ],
                        onChanged: (val) => setState(() => _selectedClientId = val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Quoted / Estimated Value (Optional)',
                          hintText: 'e.g. 150000',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final clean = v.trim();
                          if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(clean)) {
                            return 'Enter a valid non-negative amount (max 2 decimals)';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedCurrency,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Currency'),
                        items: currencyMap.entries
                            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedCurrency = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(
                          _selectedFollowUpDate != null
                              ? 'Follow-up: ${Lead.formatCalendarDate(_selectedFollowUpDate!)}'
                              : 'Set Follow-up Date (Optional)',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedFollowUpDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setState(() => _selectedFollowUpDate = Lead.toCalendarDate(picked));
                          }
                        },
                      ),
                    ),
                    if (_selectedFollowUpDate != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _selectedFollowUpDate = null),
                        tooltip: 'Clear date',
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Enquiry Notes (Optional)'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: SoloDeskColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save Changes'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Follow-up Draft Modal
// ---------------------------------------------------------------------------
class _FollowUpDraftModal extends StatefulWidget {
  final Lead lead;

  const _FollowUpDraftModal({required this.lead});

  @override
  State<_FollowUpDraftModal> createState() => _FollowUpDraftModalState();
}

class _FollowUpDraftModalState extends State<_FollowUpDraftModal> {
  late final TextEditingController _draftController;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    final firstName = widget.lead.contactName.trim().split(' ').first;
    final niche = widget.lead.serviceNiche;
    final draft =
        'Hi $firstName, I hope you\'re having a productive week.\n\n'
        'Following up on our conversation regarding $niche. '
        'Please let me know if you have any questions or if you would like to review next steps and milestones together.\n\n'
        'Best regards,';
    _draftController = TextEditingController(text: draft);
  }

  @override
  void dispose() {
    _draftController.dispose();
    super.dispose();
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _draftController.text));
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Follow-up draft copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.mail_outline, color: SoloDeskColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Draft Follow-up · ${widget.lead.displayName}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: SoloDeskColors.primaryPale,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SoloDeskColors.primaryLight.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: SoloDeskColors.primary, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'SoloDesk Boundary Policy: Review and edit this draft before sending. SoloDesk never communicates directly with clients or sends messages.',
                      style: TextStyle(fontSize: 11, color: SoloDeskColors.ink, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _draftController,
              maxLines: 7,
              decoration: const InputDecoration(
                labelText: 'Editable Message Draft',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        ElevatedButton.icon(
          icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
          label: Text(_copied ? 'Copied' : 'Copy to Clipboard'),
          onPressed: _copyToClipboard,
          style: ElevatedButton.styleFrom(
            backgroundColor: SoloDeskColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
