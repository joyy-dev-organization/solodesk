import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../db/repository_scope.dart';
import '../db/service_plan_repository.dart';
import '../models/client.dart';
import '../models/money.dart';
import '../models/service_plan.dart';
import '../models/service_plan_offer_models.dart';
import '../services/service_plan_offer_client.dart';
import '../services/service_plan_offer_exceptions.dart';
import '../theme/colors.dart';
import '../widgets/stat_card.dart';

class RepeatWorkScreen extends StatefulWidget {
  final bool isSyntheticDemoActive;
  final void Function(int index)? onNavigate;
  final ServicePlanOfferClient? offerClient;

  const RepeatWorkScreen({
    super.key,
    this.isSyntheticDemoActive = false,
    this.onNavigate,
    this.offerClient,
  });

  @override
  State<RepeatWorkScreen> createState() => _RepeatWorkScreenState();
}

class _RepeatWorkScreenState extends State<RepeatWorkScreen> {
  late final ServicePlanOfferClient _client;

  bool _isLoading = true;
  List<ServicePlanWithClient> _plans = [];
  List<Client> _clients = [];
  ServicePlanSummary _summary = const ServicePlanSummary(
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

  // Filters
  String _selectedCadence = 'All cadences';
  String _selectedStatus = 'All status';
  final TextEditingController _searchController = TextEditingController();

  // Drafting Studio Form
  ServicePlan? _selectedPlan;
  final TextEditingController _draftClientController = TextEditingController();
  final TextEditingController _draftTitleController = TextEditingController();
  final TextEditingController _draftDeliverablesController = TextEditingController();
  final TextEditingController _draftExclusionsController = TextEditingController();
  final TextEditingController _draftRevisionsController = TextEditingController(text: '2 rounds per deliverable');
  final TextEditingController _draftPriceController = TextEditingController();
  final TextEditingController _draftNotesController = TextEditingController();
  final TextEditingController _previewController = TextEditingController();

  String _draftCadence = 'monthly';
  String _draftCurrency = 'NGN';
  OfferTone _draftTone = OfferTone.collaborative;
  bool _isRenewal = false;

  bool _isGenerating = false;
  int _elapsedSeconds = 0;
  Timer? _generationTimer;
  String? _generationError;

  @override
  void initState() {
    super.initState();
    _client = widget.offerClient ?? ServicePlanOfferClient();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void didUpdateWidget(RepeatWorkScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSyntheticDemoActive != widget.isSyntheticDemoActive) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _generationTimer?.cancel();
    _searchController.dispose();
    _draftClientController.dispose();
    _draftTitleController.dispose();
    _draftDeliverablesController.dispose();
    _draftExclusionsController.dispose();
    _draftRevisionsController.dispose();
    _draftPriceController.dispose();
    _draftNotesController.dispose();
    _previewController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final scope = RepositoryScope.of(context);
      final clients = await scope.clientRepo.getClients(includeSynthetic: widget.isSyntheticDemoActive);

      PlanCadence? cadenceFilter;
      if (_selectedCadence != 'All cadences') {
        cadenceFilter = PlanCadence.fromString(_selectedCadence);
      }

      PlanStatus? statusFilter;
      if (_selectedStatus != 'All status') {
        statusFilter = PlanStatus.fromString(_selectedStatus);
      }

      final plans = await scope.servicePlanRepo.getPlansWithClient(
        status: statusFilter,
        cadence: cadenceFilter,
        includeSynthetic: widget.isSyntheticDemoActive,
        searchQuery: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
      );

      final summary = await scope.servicePlanRepo.getPlanSummary(
        includeSynthetic: widget.isSyntheticDemoActive,
      );

      if (mounted) {
        setState(() {
          _clients = clients;
          _plans = plans;
          _summary = summary;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _prefillDraftFromPlan(ServicePlan plan, String? clientName) {
    setState(() {
      _selectedPlan = plan;
      _draftClientController.text = clientName ?? '';
      _draftTitleController.text = plan.title;
      _draftDeliverablesController.text = plan.deliverables.join('\n');
      _draftExclusionsController.text = plan.exclusions.join('\n');
      _draftRevisionsController.text = plan.revisionLimit;
      _draftPriceController.text = plan.price.formatted;
      _draftCadence = plan.cadence.dbValue;
      _draftCurrency = plan.price.currency;
      _isRenewal = plan.status.isActive;
    });
  }

  Future<void> _generateOffer() async {
    final clientName = _draftClientController.text.trim().isEmpty ? 'there' : _draftClientController.text.trim();
    final planTitle = _draftTitleController.text.trim().isEmpty ? 'Repeat Service Package' : _draftTitleController.text.trim();

    final deliverables = _draftDeliverablesController.text
        .split('\n')
        .map((s) => s.replaceAll(RegExp(r'^[•\-\*]\s*'), '').trim())
        .filter((s) => s.isNotEmpty)
        .toList();

    if (deliverables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please specify at least one deliverable for this offer.')),
      );
      return;
    }

    final exclusions = _draftExclusionsController.text
        .split('\n')
        .map((s) => s.replaceAll(RegExp(r'^[•\-\*]\s*'), '').trim())
        .filter((s) => s.isNotEmpty)
        .toList();

    final revisionLimits = _draftRevisionsController.text.trim().isEmpty
        ? '2 rounds per deliverable'
        : _draftRevisionsController.text.trim();

    final priceFormatted = _draftPriceController.text.trim().isEmpty
        ? 'Agreed package fee'
        : _draftPriceController.text.trim();

    setState(() {
      _isGenerating = true;
      _elapsedSeconds = 0;
      _generationError = null;
    });

    _generationTimer?.cancel();
    _generationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });

    try {
      final result = await _client.generateOfferDraft(
        clientName: clientName,
        serviceNiche: _selectedPlan?.serviceNiche ?? 'General',
        planTitle: planTitle,
        deliverables: deliverables,
        exclusions: exclusions,
        revisionLimits: revisionLimits,
        priceFormatted: priceFormatted,
        currency: _draftCurrency,
        cadence: _draftCadence,
        tone: _draftTone.toBackendString(),
        isRenewal: _isRenewal,
        optionalNotes: _draftNotesController.text.trim().isEmpty ? null : _draftNotesController.text.trim(),
      );

      _generationTimer?.cancel();
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _previewController.text = result.offerText;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offer proposal drafted successfully.')),
        );
      }
    } catch (e) {
      _generationTimer?.cancel();
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _generationError = e is ServicePlanOfferException ? e.message : e.toString();
        });
      }
    }
  }

  void _cancelGeneration() {
    _client.cancelActiveRequest();
    _generationTimer?.cancel();
    setState(() {
      _isGenerating = false;
      _generationError = 'Inference cancelled by user.';
    });
  }

  Future<void> _openCreatePlanDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CreateServicePlanDialog(
        clients: _clients,
        initialCurrency: _summary.recurringMonthlyRevenueByCurrency.keys.isNotEmpty
            ? _summary.recurringMonthlyRevenueByCurrency.keys.first
            : 'NGN',
        onSave: (newPlan) async {
          final scope = RepositoryScope.of(context);
          await scope.servicePlanRepo.createPlan(newPlan);
        },
      ),
    );
    if (result == true) {
      _loadData();
    }
  }

  Future<void> _openEditPlanDialog(ServicePlan plan) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EditServicePlanDialog(
        plan: plan,
        clients: _clients,
        onSave: (updatedPlan) async {
          final scope = RepositoryScope.of(context);
          await scope.servicePlanRepo.updatePlan(updatedPlan);
        },
      ),
    );
    if (result == true) {
      _loadData();
    }
  }

  Future<void> _confirmDeletePlan(ServicePlan plan) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Service Plan'),
        content: Text('Are you sure you want to delete "${plan.title}"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: SoloDeskColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final scope = RepositoryScope.of(context);
      await scope.servicePlanRepo.deletePlan(plan.id);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service plan deleted.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Format MRR summary string
    String mrrLabel = 'None';
    if (_summary.recurringMonthlyRevenueByCurrency.isNotEmpty) {
      mrrLabel = _summary.recurringMonthlyRevenueByCurrency.entries.map((e) {
        final amountK = (e.value / 100000).round();
        final symbol = e.key == 'NGN' ? '₦' : e.key == 'USD' ? '\$' : '${e.key} ';
        return '$symbol${amountK}k/mo';
      }).join(' · ');
    }

    return Scaffold(
      backgroundColor: SoloDeskColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'REPEAT WORK · RETAINERS & RENEWALS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: SoloDeskColors.primary,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Make the next project easier to win.',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: SoloDeskColors.ink,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Turn a good client relationship into recurring work that fits your niche.',
                        style: TextStyle(
                          fontSize: 13,
                          color: SoloDeskColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _openCreatePlanDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SoloDeskColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text(
                    '+ New service plan',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // SoloDesk Boundary Policy Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: SoloDeskColors.blueBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: SoloDeskColors.blueBorder),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, size: 20, color: SoloDeskColors.blue),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'SoloDesk Policy: Repeat-work retainers and model-assisted offers are strictly advisory drafts for your review and manual dispatch. SoloDesk never contacts clients or renews agreements automatically.',
                      style: TextStyle(fontSize: 12, color: SoloDeskColors.ink, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // KPI Stat Row
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = (constraints.maxWidth - 32) / 3;
                return Row(
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: StatCard(
                        label: 'Active retainers',
                        value: _summary.activePlans.toString().padLeft(2, '0'),
                        note: widget.isSyntheticDemoActive ? 'Demo active plans' : 'Active recurring contracts',
                        icon: Icons.autorenew_outlined,
                        iconColor: SoloDeskColors.primary,
                        iconBgColor: SoloDeskColors.primaryPale,
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: cardWidth,
                      child: StatCard(
                        label: 'Monthly recurring',
                        value: mrrLabel,
                        note: 'Normalized monthly income',
                        icon: Icons.account_balance_wallet_outlined,
                        iconColor: SoloDeskColors.green,
                        iconBgColor: SoloDeskColors.greenBg,
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: cardWidth,
                      child: StatCard(
                        label: 'Renewals due soon',
                        value: _summary.renewalsDueCount.toString().padLeft(2, '0'),
                        note: 'Due today or upcoming',
                        icon: Icons.calendar_today_outlined,
                        iconColor: SoloDeskColors.amber,
                        iconBgColor: SoloDeskColors.amberBg,
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 22),

            // AI Niche Guidance Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF3F1FF), Color(0xFFFBFAFF)],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDFDCFF)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: SoloDeskColors.primaryPale,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Icon(Icons.auto_awesome, size: 20, color: SoloDeskColors.primary),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Not just website maintenance',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: SoloDeskColors.ink),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Retainers can mean monthly content, design hours, editing, marketing, coaching sessions, support, or another repeat service.',
                          style: TextStyle(fontSize: 12, color: SoloDeskColors.muted),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: SoloDeskColors.primaryLight.withValues(alpha: 0.4)),
                    ),
                    child: const Text(
                      'NICHE-FLEXIBLE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: SoloDeskColors.primary),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Filter Chips & Search Bar
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('All cadences', _selectedCadence, (val) {
                          setState(() => _selectedCadence = val);
                          _loadData();
                        }),
                        _buildFilterChip('Monthly', _selectedCadence, (val) {
                          setState(() => _selectedCadence = val);
                          _loadData();
                        }),
                        _buildFilterChip('Quarterly', _selectedCadence, (val) {
                          setState(() => _selectedCadence = val);
                          _loadData();
                        }),
                        _buildFilterChip('Bi-weekly', _selectedCadence, (val) {
                          setState(() => _selectedCadence = val);
                          _loadData();
                        }),
                        const VerticalDivider(width: 24),
                        _buildFilterChip('All status', _selectedStatus, (val) {
                          setState(() => _selectedStatus = val);
                          _loadData();
                        }),
                        _buildFilterChip('Active', _selectedStatus, (val) {
                          setState(() => _selectedStatus = val);
                          _loadData();
                        }),
                        _buildFilterChip('Draft', _selectedStatus, (val) {
                          setState(() => _selectedStatus = val);
                          _loadData();
                        }),
                        _buildFilterChip('Paused', _selectedStatus, (val) {
                          setState(() => _selectedStatus = val);
                          _loadData();
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 220,
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search plans...',
                      hintStyle: const TextStyle(fontSize: 12, color: SoloDeskColors.muted),
                      prefixIcon: const Icon(Icons.search, size: 16, color: SoloDeskColors.muted),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: SoloDeskColors.borderLine),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: SoloDeskColors.borderLine),
                      ),
                    ),
                    onSubmitted: (_) => _loadData(),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Service Plans Card Grid
            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 16.0;
                  final columnCount = constraints.maxWidth > 900 ? 3 : 2;
                  final itemWidth = (constraints.maxWidth - (columnCount - 1) * spacing) / columnCount;

                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      ..._plans.map((p) => SizedBox(
                        width: itemWidth,
                        child: _ServicePlanCard(
                          planWithClient: p,
                          onDraftRenewal: () => _prefillDraftFromPlan(p.plan, p.clientName),
                          onEdit: () => _openEditPlanDialog(p.plan),
                          onDelete: () => _confirmDeletePlan(p.plan),
                        ),
                      )),
                      SizedBox(
                        width: itemWidth,
                        child: _AddServicePlanDashedCard(onTap: _openCreatePlanDialog),
                      ),
                    ],
                  );
                },
              ),

            const SizedBox(height: 36),

            // Two-Column Recurring Offer Drafting Studio
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Draft Form
                Expanded(
                  flex: 5,
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: SoloDeskColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: SoloDeskColors.borderLine),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Draft a new recurring offer',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: SoloDeskColors.ink),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Describe the repeat service you provide in your own niche.',
                          style: TextStyle(fontSize: 12, color: SoloDeskColors.muted),
                        ),
                        const SizedBox(height: 16),

                        // Client Input
                        _buildFormField(
                          label: 'Client / Prospect',
                          controller: _draftClientController,
                          hintText: 'e.g. Amina Musa or Northstar Media',
                        ),
                        const SizedBox(height: 14),

                        // Service Title
                        _buildFormField(
                          label: 'Service Plan Title',
                          controller: _draftTitleController,
                          hintText: 'e.g. Monthly Content Package',
                        ),
                        const SizedBox(height: 14),

                        // Deliverables
                        _buildFormField(
                          label: 'Deliverables (one per line)',
                          controller: _draftDeliverablesController,
                          hintText: '• 4 Articles\n• 2 Newsletters\n• SEO optimization',
                          maxLines: 3,
                        ),
                        const SizedBox(height: 14),

                        // Exclusions
                        _buildFormField(
                          label: 'Scope Exclusions (one per line)',
                          controller: _draftExclusionsController,
                          hintText: '• Video editing\n• Ad spend management',
                          maxLines: 2,
                        ),
                        const SizedBox(height: 14),

                        // Revision Limits & Price Row
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: _buildFormField(
                                label: 'Price / Investment',
                                controller: _draftPriceController,
                                hintText: 'e.g. ₦180,000 / month',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Cadence', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: SoloDeskColors.ink)),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    initialValue: _draftCadence,
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    items: PlanCadence.values.map((c) => DropdownMenuItem(value: c.dbValue, child: Text(c.displayName, style: const TextStyle(fontSize: 12)))).toList(),
                                    onChanged: (val) {
                                      if (val != null) setState(() => _draftCadence = val);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Tone Selector
                        const Text('Tone & Framing', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: SoloDeskColors.ink)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: OfferTone.values.map((t) {
                            final isSel = _draftTone == t;
                            return ChoiceChip(
                              label: Text(t.displayName, style: TextStyle(fontSize: 11, color: isSel ? Colors.white : SoloDeskColors.ink)),
                              selected: isSel,
                              selectedColor: SoloDeskColors.primary,
                              onSelected: (_) => setState(() => _draftTone = t),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 14),

                        // Is Renewal Switch
                        Row(
                          children: [
                            Checkbox(
                              value: _isRenewal,
                              activeColor: SoloDeskColors.primary,
                              onChanged: (v) => setState(() => _isRenewal = v ?? false),
                            ),
                            const Expanded(
                              child: Text('Frame as ongoing renewal invitation', style: TextStyle(fontSize: 12, color: SoloDeskColors.ink)),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Generate CTA / Loading / Cancel Button
                        if (_isGenerating)
                          Row(
                            children: [
                              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text('Generating draft with local model (${_elapsedSeconds}s)...', style: const TextStyle(fontSize: 12, color: SoloDeskColors.muted)),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: _cancelGeneration,
                                child: const Text('Cancel', style: TextStyle(color: SoloDeskColors.red)),
                              ),
                            ],
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: _generateOffer,
                            icon: const Icon(Icons.auto_awesome, size: 16),
                            label: const Text('Generate offer draft'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: SoloDeskColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),

                        if (_generationError != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: SoloDeskColors.redBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: SoloDeskColors.redBorder),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, size: 16, color: SoloDeskColors.red),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_generationError!, style: const TextStyle(fontSize: 12, color: SoloDeskColors.red))),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 20),

                // Right Column: Preview & Copy
                Expanded(
                  flex: 5,
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: SoloDeskColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: SoloDeskColors.borderLine),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Offer preview',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: SoloDeskColors.ink),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'A clear plan makes expectations easier to manage.',
                          style: TextStyle(fontSize: 12, color: SoloDeskColors.muted),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _previewController,
                          maxLines: 15,
                          style: const TextStyle(fontSize: 13, height: 1.5, color: SoloDeskColors.ink),
                          decoration: InputDecoration(
                            hintText: 'Your drafted offer will appear here. You can edit any details before copying...',
                            hintStyle: const TextStyle(fontSize: 12, color: SoloDeskColors.muted),
                            filled: true,
                            fillColor: const Color(0xFFFAFAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: SoloDeskColors.borderLine)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: SoloDeskColors.borderLine)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () {
                                final text = _previewController.text.trim();
                                if (text.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to copy yet.')));
                                  return;
                                }
                                Clipboard.setData(ClipboardData(text: text));
                                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer copied to clipboard.')));
                              },
                              icon: const Icon(Icons.copy, size: 16),
                              label: const Text('Copy offer'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: SoloDeskColors.surface,
                                foregroundColor: SoloDeskColors.ink,
                                side: const BorderSide(color: SoloDeskColors.borderLine),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const Text(
                              'Advisory draft · Review before sending',
                              style: TextStyle(fontSize: 11, color: SoloDeskColors.muted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String currentVal, ValueChanged<String> onSelected) {
    final isSel = currentVal == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.w700 : FontWeight.w500, color: isSel ? SoloDeskColors.primary : SoloDeskColors.ink)),
        selected: isSel,
        backgroundColor: Colors.white,
        selectedColor: SoloDeskColors.primaryPale,
        checkmarkColor: SoloDeskColors.primary,
        side: BorderSide(color: isSel ? SoloDeskColors.primary : SoloDeskColors.borderLine),
        onSelected: (_) => onSelected(label),
      ),
    );
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: SoloDeskColors.ink)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(fontSize: 12, color: SoloDeskColors.muted),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: SoloDeskColors.borderLine)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: SoloDeskColors.borderLine)),
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// SERVICE PLAN CARD WIDGET
// ----------------------------------------------------------------------------
class _ServicePlanCard extends StatelessWidget {
  final ServicePlanWithClient planWithClient;
  final VoidCallback onDraftRenewal;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ServicePlanCard({
    required this.planWithClient,
    required this.onDraftRenewal,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final plan = planWithClient.plan;
    final clientName = planWithClient.clientName ?? 'Independent package';

    Color statusBg = SoloDeskColors.greenBg;
    Color statusColor = SoloDeskColors.green;
    if (plan.status == PlanStatus.draft) {
      statusBg = const Color(0xFFF0F1F5);
      statusColor = SoloDeskColors.muted;
    } else if (plan.status == PlanStatus.paused) {
      statusBg = SoloDeskColors.amberBg;
      statusColor = SoloDeskColors.amber;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SoloDeskColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SoloDeskColors.borderLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
                child: Text(plan.status.displayName, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18, color: SoloDeskColors.muted),
                onSelected: (val) {
                  if (val == 'draft') onDraftRenewal();
                  if (val == 'edit') onEdit();
                  if (val == 'delete') onDelete();
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'draft', child: Text('Draft offer')),
                  const PopupMenuItem(value: 'edit', child: Text('Edit plan')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete plan', style: TextStyle(color: SoloDeskColors.red))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(plan.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: SoloDeskColors.ink)),
          const SizedBox(height: 2),
          Text('$clientName · ${plan.serviceNiche}', style: const TextStyle(fontSize: 12, color: SoloDeskColors.muted)),
          const SizedBox(height: 12),
          Text(
            '${plan.price.formatted} / ${plan.cadence.dbValue}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: SoloDeskColors.primary),
          ),
          const SizedBox(height: 10),
          Text(
            plan.deliverables.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: SoloDeskColors.ink, height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            'Limits: ${plan.revisionLimit}',
            style: const TextStyle(fontSize: 11, color: SoloDeskColors.muted),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: SoloDeskColors.borderLine),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                plan.renewalDate != null ? 'Renews ${ServicePlan.formatCalendarDate(plan.renewalDate!)}' : 'No set renewal',
                style: const TextStyle(fontSize: 11, color: SoloDeskColors.muted),
              ),
              TextButton(
                onPressed: onDraftRenewal,
                child: const Text('Draft renewal ↗', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SoloDeskColors.primary)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// DASHED CREATION CARD WIDGET
// ----------------------------------------------------------------------------
class _AddServicePlanDashedCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddServicePlanDashedCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(minHeight: 220),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SoloDeskColors.primaryLight.withValues(alpha: 0.5), style: BorderStyle.solid, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: SoloDeskColors.primaryPale,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.add, color: SoloDeskColors.primary, size: 20),
            ),
            const SizedBox(height: 10),
            const Text(
              'Package your repeat service',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: SoloDeskColors.ink),
            ),
            const SizedBox(height: 4),
            const Text(
              'Define what is included, how often you deliver, revision limits, price and renewal date.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: SoloDeskColors.muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: SoloDeskColors.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Create service plan', style: TextStyle(fontSize: 12, color: SoloDeskColors.primary)),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// CREATE SERVICE PLAN DIALOG
// ----------------------------------------------------------------------------
class _CreateServicePlanDialog extends StatefulWidget {
  final List<Client> clients;
  final String initialCurrency;
  final Future<void> Function(ServicePlan plan) onSave;

  const _CreateServicePlanDialog({
    required this.clients,
    required this.initialCurrency,
    required this.onSave,
  });

  @override
  State<_CreateServicePlanDialog> createState() => _CreateServicePlanDialogState();
}

class _CreateServicePlanDialogState extends State<_CreateServicePlanDialog> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();

  String? _selectedClientId;
  final _titleController = TextEditingController();
  String _serviceNiche = 'Design & branding';
  PlanCadence _cadence = PlanCadence.monthly;
  final _priceController = TextEditingController();
  late String _currency;
  final _deliverablesController = TextEditingController();
  final _exclusionsController = TextEditingController();
  final _revisionsController = TextEditingController(text: '2 rounds per deliverable');
  DateTime? _renewalDate;
  PlanStatus _status = PlanStatus.active;
  final _notesController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currency = widget.initialCurrency;
    _renewalDate = DateTime.now().add(const Duration(days: 30));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _deliverablesController.dispose();
    _exclusionsController.dispose();
    _revisionsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final priceParsed = double.tryParse(_priceController.text.replaceAll(',', '').trim()) ?? 0;
    final minorUnits = (priceParsed * 100).round();

    final deliverables = _deliverablesController.text
        .split('\n')
        .map((s) => s.replaceAll(RegExp(r'^[•\-\*]\s*'), '').trim())
        .filter((s) => s.isNotEmpty)
        .toList();

    if (deliverables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one deliverable is required.')),
      );
      return;
    }

    final exclusions = _exclusionsController.text
        .split('\n')
        .map((s) => s.replaceAll(RegExp(r'^[•\-\*]\s*'), '').trim())
        .filter((s) => s.isNotEmpty)
        .toList();

    final now = DateTime.now().toUtc();
    final newPlan = ServicePlan(
      id: _uuid.v4(),
      clientId: _selectedClientId,
      title: _titleController.text.trim(),
      serviceNiche: _serviceNiche,
      cadence: _cadence,
      price: Money(minorUnits: minorUnits, currency: _currency),
      status: _status,
      deliverables: deliverables,
      exclusions: exclusions,
      revisionLimit: _revisionsController.text.trim().isEmpty ? '2 rounds per deliverable' : _revisionsController.text.trim(),
      renewalDate: _renewalDate,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      createdAt: now,
      updatedAt: now,
    );

    setState(() => _isSaving = true);
    try {
      await widget.onSave(newPlan);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('New Service Plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, false)),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Client Selector
                        const Text('Client', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String?>(
                          initialValue: _selectedClientId,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('None / General package')),
                            ...widget.clients.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                          ],
                          onChanged: (val) => setState(() => _selectedClientId = val),
                        ),
                        const SizedBox(height: 14),

                        // Title
                        const Text('Plan Title *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            hintText: 'e.g. Monthly Content Package',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Title is required' : null,
                        ),
                        const SizedBox(height: 14),

                        // Niche and Cadence Row
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Niche', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    initialValue: _serviceNiche,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    items: [
                                      'Design & branding',
                                      'Writing & content',
                                      'Consulting & coaching',
                                      'Photography & video',
                                      'Software & development',
                                    ].map((n) => DropdownMenuItem(value: n, child: Text(n, style: const TextStyle(fontSize: 12)))).toList(),
                                    onChanged: (v) => setState(() => _serviceNiche = v ?? _serviceNiche),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Cadence', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<PlanCadence>(
                                    initialValue: _cadence,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    items: PlanCadence.values.map((c) => DropdownMenuItem(value: c, child: Text(c.displayName, style: const TextStyle(fontSize: 12)))).toList(),
                                    onChanged: (v) => setState(() => _cadence = v ?? _cadence),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Price and Currency Row
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Price per Cadence *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _priceController,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      hintText: 'e.g. 150000',
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) return 'Price required';
                                      final p = double.tryParse(v.replaceAll(',', '').trim());
                                      if (p == null || p < 0) return 'Valid positive number required';
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Currency', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    initialValue: _currency,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    items: ['NGN', 'USD', 'EUR', 'GBP'].map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12)))).toList(),
                                    onChanged: (v) => setState(() => _currency = v ?? _currency),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Deliverables
                        const Text('Deliverables (one per line) *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _deliverablesController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: '• 4 Blog articles\n• 2 Newsletters',
                            contentPadding: const EdgeInsets.all(12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'At least one deliverable is required' : null,
                        ),
                        const SizedBox(height: 14),

                        // Exclusions
                        const Text('Scope Exclusions (one per line)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _exclusionsController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: '• Video editing\n• Ad spend management',
                            contentPadding: const EdgeInsets.all(12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Revision Limits & Renewal Date Row
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Revision Limit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _revisionsController,
                                    decoration: InputDecoration(
                                      hintText: '2 rounds per deliverable',
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Renewal / Next Review', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  InkWell(
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: _renewalDate ?? DateTime.now().add(const Duration(days: 30)),
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2030),
                                      );
                                      if (picked != null) setState(() => _renewalDate = picked);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey.shade400),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _renewalDate != null ? ServicePlan.formatCalendarDate(_renewalDate!) : 'Select date',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          const Icon(Icons.calendar_today, size: 14),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Status
                        const Text('Status', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: PlanStatus.values.map((s) {
                            return ChoiceChip(
                              label: Text(s.displayName, style: TextStyle(fontSize: 11, color: _status == s ? Colors.white : SoloDeskColors.ink)),
                              selected: _status == s,
                              selectedColor: SoloDeskColors.primary,
                              onSelected: (_) => setState(() => _status = s),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _submit,
                      style: ElevatedButton.styleFrom(backgroundColor: SoloDeskColors.primary, foregroundColor: Colors.white),
                      child: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save Plan'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// EDIT SERVICE PLAN DIALOG
// ----------------------------------------------------------------------------
class _EditServicePlanDialog extends StatefulWidget {
  final ServicePlan plan;
  final List<Client> clients;
  final Future<void> Function(ServicePlan plan) onSave;

  const _EditServicePlanDialog({
    required this.plan,
    required this.clients,
    required this.onSave,
  });

  @override
  State<_EditServicePlanDialog> createState() => _EditServicePlanDialogState();
}

class _EditServicePlanDialogState extends State<_EditServicePlanDialog> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedClientId;
  late final TextEditingController _titleController;
  late String _serviceNiche;
  late PlanCadence _cadence;
  late final TextEditingController _priceController;
  late String _currency;
  late final TextEditingController _deliverablesController;
  late final TextEditingController _exclusionsController;
  late final TextEditingController _revisionsController;
  DateTime? _renewalDate;
  late PlanStatus _status;
  late final TextEditingController _notesController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedClientId = widget.plan.clientId;
    _titleController = TextEditingController(text: widget.plan.title);
    _serviceNiche = widget.plan.serviceNiche;
    _cadence = widget.plan.cadence;
    _priceController = TextEditingController(text: (widget.plan.price.minorUnits / 100).toStringAsFixed(0));
    _currency = widget.plan.price.currency;
    _deliverablesController = TextEditingController(text: widget.plan.deliverables.join('\n'));
    _exclusionsController = TextEditingController(text: widget.plan.exclusions.join('\n'));
    _revisionsController = TextEditingController(text: widget.plan.revisionLimit);
    _renewalDate = widget.plan.renewalDate;
    _status = widget.plan.status;
    _notesController = TextEditingController(text: widget.plan.notes ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _deliverablesController.dispose();
    _exclusionsController.dispose();
    _revisionsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final priceParsed = double.tryParse(_priceController.text.replaceAll(',', '').trim()) ?? 0;
    final minorUnits = (priceParsed * 100).round();

    final deliverables = _deliverablesController.text
        .split('\n')
        .map((s) => s.replaceAll(RegExp(r'^[•\-\*]\s*'), '').trim())
        .filter((s) => s.isNotEmpty)
        .toList();

    if (deliverables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one deliverable is required.')),
      );
      return;
    }

    final exclusions = _exclusionsController.text
        .split('\n')
        .map((s) => s.replaceAll(RegExp(r'^[•\-\*]\s*'), '').trim())
        .filter((s) => s.isNotEmpty)
        .toList();

    final updated = widget.plan.copyWith(
      clientId: _selectedClientId,
      clearClientId: _selectedClientId == null,
      title: _titleController.text.trim(),
      serviceNiche: _serviceNiche,
      cadence: _cadence,
      price: Money(minorUnits: minorUnits, currency: _currency),
      status: _status,
      deliverables: deliverables,
      exclusions: exclusions,
      revisionLimit: _revisionsController.text.trim(),
      renewalDate: _renewalDate,
      clearRenewalDate: _renewalDate == null,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    );

    setState(() => _isSaving = true);
    try {
      await widget.onSave(updated);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Edit Service Plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, false)),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Client', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String?>(
                          initialValue: _selectedClientId,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('None / General package')),
                            ...widget.clients.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                          ],
                          onChanged: (val) => setState(() => _selectedClientId = val),
                        ),
                        const SizedBox(height: 14),

                        const Text('Plan Title *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _titleController,
                          validator: (v) => v == null || v.trim().isEmpty ? 'Title is required' : null,
                        ),
                        const SizedBox(height: 14),

                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Price per Cadence *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _priceController,
                                    keyboardType: TextInputType.number,
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) return 'Price required';
                                      final p = double.tryParse(v.replaceAll(',', '').trim());
                                      if (p == null || p < 0) return 'Positive number required';
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Cadence', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<PlanCadence>(
                                    initialValue: _cadence,
                                    items: PlanCadence.values.map((c) => DropdownMenuItem(value: c, child: Text(c.displayName, style: const TextStyle(fontSize: 12)))).toList(),
                                    onChanged: (v) => setState(() => _cadence = v ?? _cadence),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        const Text('Deliverables (one per line) *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _deliverablesController,
                          maxLines: 3,
                          validator: (v) => v == null || v.trim().isEmpty ? 'At least one deliverable is required' : null,
                        ),
                        const SizedBox(height: 14),

                        const Text('Scope Exclusions (one per line)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _exclusionsController,
                          maxLines: 2,
                        ),
                        const SizedBox(height: 14),

                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Revision Limit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  TextFormField(controller: _revisionsController),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Renewal Date', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  InkWell(
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: _renewalDate ?? DateTime.now(),
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2030),
                                      );
                                      if (picked != null) setState(() => _renewalDate = picked);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
                                      child: Text(_renewalDate != null ? ServicePlan.formatCalendarDate(_renewalDate!) : 'None'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        const Text('Status', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: PlanStatus.values.map((s) {
                            return ChoiceChip(
                              label: Text(s.displayName, style: TextStyle(fontSize: 11, color: _status == s ? Colors.white : SoloDeskColors.ink)),
                              selected: _status == s,
                              selectedColor: SoloDeskColors.primary,
                              onSelected: (_) => setState(() => _status = s),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _submit,
                      style: ElevatedButton.styleFrom(backgroundColor: SoloDeskColors.primary, foregroundColor: Colors.white),
                      child: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Update Plan'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension _IterableFilter<T> on Iterable<T> {
  Iterable<T> filter(bool Function(T element) test) sync* {
    for (final element in this) {
      if (test(element)) yield element;
    }
  }
}
