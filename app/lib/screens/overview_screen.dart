import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../db/repository_scope.dart';
import '../models/client.dart';
import '../models/project.dart';
import '../models/money.dart';
import '../theme/colors.dart';
import '../widgets/stat_card.dart';

class OverviewScreen extends StatefulWidget {
  final ValueChanged<int> onNavigate;
  final bool isSyntheticDemoActive;

  const OverviewScreen({
    super.key,
    required this.onNavigate,
    required this.isSyntheticDemoActive,
  });

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  int _activeProjectsCount = 0;
  int _totalClientsCount = 0;
  int _approvedScopesCount = 0;
  int _unpaidInvoicesCount = 0;
  int _activeLeadsCount = 0;
  int _followUpsDueCount = 0;
  int _activePlansCount = 0;
  List<Project> _recentProjects = [];
  Map<String, Client> _clientMap = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => loadData());
  }

  @override
  void didUpdateWidget(covariant OverviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSyntheticDemoActive != widget.isSyntheticDemoActive) {
      loadData();
    }
  }

  Future<void> loadData() async {
    if (!mounted) return;
    final scope = RepositoryScope.of(context);
    final metrics = await scope.demoDataRepo.getMetrics(
      includeSynthetic: widget.isSyntheticDemoActive,
    );
    final projects = await scope.projectRepo.getProjects(
      includeSynthetic: widget.isSyntheticDemoActive,
    );
    final clients = await scope.clientRepo.getClients(
      includeSynthetic: widget.isSyntheticDemoActive,
    );

    final map = {for (final c in clients) c.id: c};

    if (mounted) {
      setState(() {
        _activeProjectsCount = metrics.activeProjects;
        _totalClientsCount = metrics.totalClients;
        _approvedScopesCount = metrics.approvedScopes;
        _unpaidInvoicesCount = metrics.unpaidInvoices;
        _activeLeadsCount = metrics.activeLeads;
        _followUpsDueCount = metrics.followUpsDue;
        _activePlansCount = metrics.activeServicePlans;
        _recentProjects = projects.take(5).toList();
        _clientMap = map;
        _isLoading = false;
      });
    }
  }

  void _showAddClientDialog() {
    final nameController = TextEditingController();
    final companyController = TextEditingController();
    final emailController = TextEditingController();
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Client'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Client or Contact Name *',
                  hintText: 'e.g. Amina Musa',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: companyController,
                decoration: const InputDecoration(
                  labelText: 'Company / Brand (Optional)',
                  hintText: 'e.g. Musa Brand Lab',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Email Address (Optional)',
                  hintText: 'e.g. client@example.com',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                  hintText: 'Project or discovery call notes',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              final repo = RepositoryScope.of(context).clientRepo;
              final now = DateTime.now().toUtc();
              final client = Client(
                id: const Uuid().v4(),
                name: name,
                initials: Client.computeInitials(name),
                company: companyController.text.trim().isEmpty ? null : companyController.text.trim(),
                email: emailController.text.trim().isEmpty ? null : emailController.text.trim(),
                notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                isSynthetic: false,
                createdAt: now,
                updatedAt: now,
              );
              await repo.createClient(client);
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (mounted) {
                loadData();
              }
            },
            child: const Text('Save Client'),
          ),
        ],
      ),
    );
  }

  void _showEditClientDialog(Client client) {
    final nameController = TextEditingController(text: client.name);
    final companyController = TextEditingController(text: client.company ?? '');
    final emailController = TextEditingController(text: client.email ?? '');
    final notesController = TextEditingController(text: client.notes ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Client'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Client or Contact Name *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: companyController,
                decoration: const InputDecoration(labelText: 'Company / Brand (Optional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email Address (Optional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes (Optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final repo = RepositoryScope.of(context).clientRepo;
              final updated = client.copyWith(
                name: name,
                company: companyController.text.trim().isEmpty ? null : companyController.text.trim(),
                email: emailController.text.trim().isEmpty ? null : emailController.text.trim(),
                notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
              );
              await repo.updateClient(updated);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) loadData();
            },
            child: const Text('Update Client'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteClient(Client client) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${client.name}?'),
        content: const Text(
          'Are you sure you want to delete this client? If they have approved scopes, deletion will be blocked by SQLite immutability rules.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: SoloDeskColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final repo = RepositoryScope.of(context).clientRepo;
      await repo.deleteClient(client.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Client ${client.name} deleted.')),
        );
        loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: SoloDeskColors.red,
          ),
        );
      }
    }
  }

  void _showAddProjectDialog() async {
    final repoScope = RepositoryScope.of(context);
    final clients = await repoScope.clientRepo.getClients(includeSynthetic: widget.isSyntheticDemoActive);
    if (clients.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a client before creating a project.')),
      );
      _showAddClientDialog();
      return;
    }

    final nameController = TextEditingController();
    final budgetController = TextEditingController(text: '150000');
    String selectedClientId = clients.first.id;
    String selectedNiche = 'Design & branding';
    String selectedStatus = 'active';

    final prefs = await repoScope.preferenceRepo.getPreferences();
    final niches = prefs.niches.isNotEmpty ? prefs.niches : const ['Design & branding', 'Writing & content'];
    if (!niches.contains(selectedNiche)) {
      selectedNiche = niches.first;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Add Project'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Project Name *',
                    hintText: 'e.g. Brand Identity Package',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedClientId,
                  decoration: const InputDecoration(labelText: 'Client *'),
                  items: clients.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedClientId = val);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedNiche,
                  decoration: const InputDecoration(labelText: 'Service Category *'),
                  items: niches.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedNiche = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: budgetController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Budget (${prefs.defaultCurrency}) *',
                    hintText: 'e.g. 150000',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                final rawBudget = double.tryParse(budgetController.text.trim()) ?? 0.0;
                final minorUnits = (rawBudget * 100).round();
                final budget = Money(minorUnits: minorUnits, currency: prefs.defaultCurrency);
                final now = DateTime.now().toUtc();

                final project = Project(
                  id: const Uuid().v4(),
                  clientId: selectedClientId,
                  name: name,
                  niche: selectedNiche,
                  budget: budget,
                  status: selectedStatus,
                  isSynthetic: false,
                  createdAt: now,
                  updatedAt: now,
                );

                await repoScope.projectRepo.createProject(project);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) loadData();
              },
              child: const Text('Save Project'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditProjectDialog(Project proj) async {
    final nameController = TextEditingController(text: proj.name);
    final budgetController = TextEditingController(text: proj.budget.toMajorUnits().toStringAsFixed(0));
    String selectedStatus = proj.status;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: Text('Edit ${proj.name}'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Project Name *'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedStatus,
                  decoration: const InputDecoration(labelText: 'Status *'),
                  items: const [
                    DropdownMenuItem(value: 'lead', child: Text('Lead')),
                    DropdownMenuItem(value: 'drafting', child: Text('Drafting')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'completed', child: Text('Completed')),
                    DropdownMenuItem(value: 'archived', child: Text('Archived')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedStatus = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: budgetController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Budget (${proj.budget.currency}) *',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final rawBudget = double.tryParse(budgetController.text.trim()) ?? 0.0;
                final minorUnits = (rawBudget * 100).round();
                final budget = Money(minorUnits: minorUnits, currency: proj.budget.currency);

                final updated = proj.copyWith(
                  name: name,
                  status: selectedStatus,
                  budget: budget,
                );

                final repo = RepositoryScope.of(context).projectRepo;
                await repo.updateProject(updated);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) loadData();
              },
              child: const Text('Update Project'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteProject(Project proj) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${proj.name}?'),
        content: const Text(
          'Are you sure you want to delete this project? If it has an approved scope version, deletion will be blocked by SQLite immutability rules.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: SoloDeskColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final repo = RepositoryScope.of(context).projectRepo;
      await repo.deleteProject(proj.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Project ${proj.name} deleted.')),
        );
        loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: SoloDeskColors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Page Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Text(
                    'WORKSPACE · YOUR BUSINESS AT A GLANCE',
                    style: TextStyle(
                      color: SoloDeskColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Workspace Overview ✦',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      color: SoloDeskColors.ink,
                      letterSpacing: -0.9,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Counts and agreements stored securely in local SQLite outside git.',
                    style: TextStyle(fontSize: 13, color: SoloDeskColors.muted),
                  ),
                ],
              ),
            ),
            Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _showAddClientDialog,
                    icon: const Icon(Icons.person_add_outlined, size: 16),
                    label: const Text('＋ Add client'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _showAddProjectDialog,
                    icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                    label: const Text('＋ Add project'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => widget.onNavigate(2), // BriefCheck
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('✧ Analyze a brief'),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 2. Metrics Grid (5 Stat Cards)
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Active projects',
                  value: _activeProjectsCount.toString().padLeft(2, '0'),
                  note: widget.isSyntheticDemoActive ? 'Includes demo records' : 'Real saved records',
                  icon: Icons.folder_open_outlined,
                  iconColor: SoloDeskColors.primary,
                  iconBgColor: SoloDeskColors.primaryPale,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Total clients',
                  value: _totalClientsCount.toString().padLeft(2, '0'),
                  note: 'Recorded in SQLite',
                  icon: Icons.people_outline,
                  iconColor: SoloDeskColors.blue,
                  iconBgColor: SoloDeskColors.blueBg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Approved scopes',
                  value: _approvedScopesCount.toString().padLeft(2, '0'),
                  note: 'Immutable versions',
                  icon: Icons.verified_outlined,
                  iconColor: SoloDeskColors.green,
                  iconBgColor: SoloDeskColors.greenBg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Follow-ups due',
                  value: _followUpsDueCount.toString().padLeft(2, '0'),
                  note: widget.isSyntheticDemoActive ? '$_activeLeadsCount active leads (demo)' : '$_activeLeadsCount active leads',
                  icon: Icons.person_search_outlined,
                  iconColor: SoloDeskColors.blue,
                  iconBgColor: SoloDeskColors.blueBg,
                  onTap: () => widget.onNavigate(1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Invoices due',
                  value: _unpaidInvoicesCount.toString().padLeft(2, '0'),
                  note: widget.isSyntheticDemoActive ? 'Includes demo invoices' : 'Unpaid in SQLite',
                  icon: Icons.attach_money_outlined,
                  iconColor: SoloDeskColors.amber,
                  iconBgColor: SoloDeskColors.amberBg,
                  onTap: () => widget.onNavigate(4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Active retainers',
                  value: _activePlansCount.toString().padLeft(2, '0'),
                  note: widget.isSyntheticDemoActive ? 'Demo repeat plans' : 'Active service plans',
                  icon: Icons.autorenew_outlined,
                  iconColor: SoloDeskColors.green,
                  iconBgColor: SoloDeskColors.greenBg,
                  onTap: () => widget.onNavigate(5),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 3. Copilot Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF3F1FF), Color(0xFFFBFAFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0xFFDFDCFF)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: SoloDeskColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('✧', style: TextStyle(color: Colors.white, fontSize: 18)),
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your freelance copilot',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: SoloDeskColors.ink,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Turn client messages into clearer next steps. You review every suggestion before it is sent.',
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
                    border: Border.all(color: const Color(0xFFD7D3FF)),
                  ),
                  child: const Text(
                    'LOCAL MODEL · qwen3:1.7b',
                    style: TextStyle(
                      color: SoloDeskColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 4. Two-Column Dashboard Content
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Client Work Table
              Expanded(
                flex: 6,
                child: Container(
                  padding: const EdgeInsets.all(20),
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
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Client work',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: SoloDeskColors.ink,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Projects and agreements saved to your device.',
                                  style: TextStyle(fontSize: 11, color: SoloDeskColors.muted),
                                ),
                              ],
                            ),
                          ),
                          if (_recentProjects.isNotEmpty)
                            TextButton(
                              onPressed: () => widget.onNavigate(3), // ScopeShield
                              child: const Text('View ScopeShield →'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      if (_recentProjects.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 36),
                          child: Center(
                            child: Column(
                              children: [
                                const Icon(Icons.inbox_outlined, size: 40, color: SoloDeskColors.muted),
                                const SizedBox(height: 10),
                                const Text(
                                  'No saved projects yet',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: SoloDeskColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Analyze a client brief or click "Load Demo Data" to explore.',
                                  style: TextStyle(fontSize: 12, color: SoloDeskColors.muted),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () => widget.onNavigate(2),
                                  child: const Text('✧ Analyze a Brief'),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _recentProjects.length,
                          separatorBuilder: (_, _) => const Divider(),
                          itemBuilder: (ctx, index) {
                            final proj = _recentProjects[index];
                            final client = _clientMap[proj.clientId];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: SoloDeskColors.primaryPale,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        client?.initials ?? '??',
                                        style: const TextStyle(
                                          color: SoloDeskColors.primary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          proj.name,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: SoloDeskColors.ink,
                                          ),
                                        ),
                                        Text(
                                          '${client?.name ?? "Unknown"} · ${proj.niche}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: SoloDeskColors.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (proj.isSynthetic)
                                    Container(
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: SoloDeskColors.primaryPale,
                                        borderRadius: BorderRadius.circular(4),
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
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: SoloDeskColors.greenBg,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      proj.status.toUpperCase(),
                                      style: const TextStyle(
                                        color: SoloDeskColors.green,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: () => widget.onNavigate(3), // ScopeShield
                                    child: const Text('Review Scope'),
                                  ),
                                  PopupMenuButton<String>(
                                    tooltip: 'Project actions',
                                    icon: const Icon(Icons.more_vert, size: 18),
                                    onSelected: (action) {
                                      if (action == 'edit_proj') {
                                        _showEditProjectDialog(proj);
                                      } else if (action == 'del_proj') {
                                        _confirmDeleteProject(proj);
                                      } else if (action == 'edit_client' && client != null) {
                                        _showEditClientDialog(client);
                                      } else if (action == 'del_client' && client != null) {
                                        _confirmDeleteClient(client);
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      const PopupMenuItem(
                                        value: 'edit_proj',
                                        child: Text('Edit project'),
                                      ),
                                      if (client != null)
                                        const PopupMenuItem(
                                          value: 'edit_client',
                                          child: Text('Edit client'),
                                        ),
                                      const PopupMenuDivider(),
                                      const PopupMenuItem(
                                        value: 'del_proj',
                                        child: Text('Delete project', style: TextStyle(color: SoloDeskColors.red)),
                                      ),
                                      if (client != null)
                                        const PopupMenuItem(
                                          value: 'del_client',
                                          child: Text('Delete client', style: TextStyle(color: SoloDeskColors.red)),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 20),

              // Right: Quick Actions
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: SoloDeskColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: SoloDeskColors.borderLine),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Quick actions',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: SoloDeskColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Move one thing forward.',
                        style: TextStyle(fontSize: 11, color: SoloDeskColors.muted),
                      ),
                      const SizedBox(height: 16),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.4,
                        children: [
                          _QuickActionButton(
                            icon: Icons.person_add_outlined,
                            title: 'Add a client',
                            subtitle: 'Save a contact',
                            onTap: _showAddClientDialog,
                          ),
                          _QuickActionButton(
                            icon: Icons.people_outline,
                            title: 'Track leads',
                            subtitle: 'Follow-up pipeline',
                            onTap: () => widget.onNavigate(1),
                          ),
                          _QuickActionButton(
                            icon: Icons.assignment_outlined,
                            title: 'Check brief',
                            subtitle: 'Find gaps',
                            onTap: () => widget.onNavigate(2),
                          ),
                          _QuickActionButton(
                            icon: Icons.shield_outlined,
                            title: 'Review scope',
                            subtitle: 'Check agreement',
                            onTap: () => widget.onNavigate(3),
                          ),
                          _QuickActionButton(
                            icon: Icons.attach_money_outlined,
                            title: 'Track invoices',
                            subtitle: 'Polite reminders',
                            onTap: () => widget.onNavigate(4),
                          ),
                          _QuickActionButton(
                            icon: Icons.autorenew_outlined,
                            title: 'Repeat work',
                            subtitle: 'Retainers & renewals',
                            onTap: () => widget.onNavigate(5),
                          ),
                          _QuickActionButton(
                            icon: Icons.settings_outlined,
                            title: 'My services',
                            subtitle: 'Categories & currency',
                            onTap: () => widget.onNavigate(6),
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
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: SoloDeskColors.borderLine),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: SoloDeskColors.primary),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: SoloDeskColors.ink,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10,
                color: SoloDeskColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
