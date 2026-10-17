import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../db/repository_scope.dart';
import '../models/client.dart';
import '../models/project.dart';
import '../models/money.dart';
import '../models/scope_item.dart';
import '../theme/colors.dart';

class BriefCheckScreen extends StatefulWidget {
  final VoidCallback? onScopeApproved;

  const BriefCheckScreen({super.key, this.onScopeApproved});

  @override
  State<BriefCheckScreen> createState() => _BriefCheckScreenState();
}

class _BriefCheckScreenState extends State<BriefCheckScreen> {
  final TextEditingController _briefController = TextEditingController(
    text: 'Hi, we are launching an organic coffee brand called MorningGlow next month. '
        'We need a modern, minimalist logo and some brand assets so we can start printing cups '
        'and setting up our website. Please keep it clean and earthy.',
  );

  String _selectedNiche = 'Design & branding';
  List<String> _userNiches = ['Design & branding', 'Writing & content'];

  // Starter Scope Deliverables (Editable in M2 shell)
  final List<String> _starterDeliverables = [
    'Primary logo concept with vector masters (SVG/EPS/PDF)',
    'Brand color palette with exact hex codes',
    'Typography pairing guidelines',
    '2 revision rounds included',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreferences());
  }

  @override
  void dispose() {
    _briefController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    if (!mounted) return;
    final repo = RepositoryScope.of(context).preferenceRepo;
    final prefs = await repo.getPreferences();
    if (mounted) {
      setState(() {
        _userNiches = prefs.niches;
        if (!_userNiches.contains(_selectedNiche) && _userNiches.isNotEmpty) {
          _selectedNiche = _userNiches.first;
        }
      });
    }
  }

  void _addDeliverable() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Scope Deliverable'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Packaging label design template',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                setState(() => _starterDeliverables.add(text));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _approveScope() {
    final clientNameController = TextEditingController(text: 'MorningGlow Coffee');
    final projectTitleController = TextEditingController(text: 'Brand Identity & Assets');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve & Save Starting Scope'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Approving this scope will create an immutable Version 1 in your local SQLite database.',
                style: TextStyle(fontSize: 12, color: SoloDeskColors.muted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: clientNameController,
                decoration: const InputDecoration(
                  labelText: 'Client Name *',
                  hintText: 'e.g. MorningGlow Coffee',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: projectTitleController,
                decoration: const InputDecoration(
                  labelText: 'Project Title *',
                  hintText: 'e.g. Brand Identity & Assets',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Included Deliverables (${_starterDeliverables.length}):',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
              const SizedBox(height: 6),
              ..._starterDeliverables.map(
                (d) => Text('• $d', style: const TextStyle(fontSize: 11, color: SoloDeskColors.ink)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final clientName = clientNameController.text.trim();
              final projectTitle = projectTitleController.text.trim();
              if (clientName.isEmpty || projectTitle.isEmpty) return;

              final scope = RepositoryScope.of(context);
              final now = DateTime.now().toUtc();
              final clientId = const Uuid().v4();
              final projectId = const Uuid().v4();

              // 1. Create client
              await scope.clientRepo.createClient(Client(
                id: clientId,
                name: clientName,
                initials: Client.computeInitials(clientName),
                createdAt: now,
                updatedAt: now,
              ));

              // 2. Create project
              final prefs = await scope.preferenceRepo.getPreferences();
              await scope.projectRepo.createProject(Project(
                id: projectId,
                clientId: clientId,
                name: projectTitle,
                niche: _selectedNiche,
                budget: Money(minorUnits: 15000000, currency: prefs.defaultCurrency),
                status: 'active',
                createdAt: now,
                updatedAt: now,
              ));

              // 3. Create draft and approve it
              final items = _starterDeliverables
                  .map((d) => ScopeItem(
                        id: const Uuid().v4(),
                        scopeVersionId: '',
                        category: 'included',
                        description: d,
                      ))
                  .toList();

              final draft = await scope.scopeRepo.createDraft(
                projectId: projectId,
                title: 'Starting Scope',
                items: items,
              );

              // 4. Approve (locks via SQLite immutability triggers)
              await scope.scopeRepo.approveVersion(draft.version.id);

              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Scope approved! Saved as immutable Version 1 for "$projectTitle".'),
                    backgroundColor: SoloDeskColors.green,
                  ),
                );
                widget.onScopeApproved?.call();
              }
            },
            child: const Text('Approve Scope (V1)'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BRIEFCHECK · AI REQUIREMENTS REVIEW',
                    style: TextStyle(
                      color: SoloDeskColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Understand the work before you quote.',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      color: SoloDeskColors.ink,
                      letterSpacing: -0.9,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Turn a vague client request into clear questions and an approved starting scope.',
                    style: TextStyle(fontSize: 13, color: SoloDeskColors.muted),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: SoloDeskColors.primaryPale,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: SoloDeskColors.primaryLight),
                ),
                child: const Text(
                  'LOCAL MODEL READY',
                  style: TextStyle(
                    color: SoloDeskColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 2-Column Layout
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Client Brief Input
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
                        'Client brief',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: SoloDeskColors.ink),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Paste message, project notes, or email from the client.',
                        style: TextStyle(fontSize: 11, color: SoloDeskColors.muted),
                      ),
                      const SizedBox(height: 16),

                      const Text('Service category', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: SoloDeskColors.borderLine),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _userNiches.contains(_selectedNiche) ? _selectedNiche : (_userNiches.isNotEmpty ? _userNiches.first : null),
                            isExpanded: true,
                            items: _userNiches.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedNiche = val);
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      const Text('What did the client ask for?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _briefController,
                        maxLines: 7,
                        decoration: const InputDecoration(
                          hintText: 'Paste brief text here...',
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Row(
                        children: [
                          Icon(Icons.lock_outline, size: 14, color: SoloDeskColors.muted),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Privacy mode: Client text is processed locally on loopback 127.0.0.1:3141.',
                              style: TextStyle(fontSize: 10, color: SoloDeskColors.muted),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Brief checked! Review findings and starter scope deliverables.')),
                          );
                        },
                        icon: const Icon(Icons.auto_awesome, size: 16),
                        label: const Text('✧ Analyze brief'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 20),

              // Right: Analysis Preview & Scope Deliverables
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Questions & Starting Scope',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: SoloDeskColors.ink),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: SoloDeskColors.amberBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Needs clarification',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: SoloDeskColors.amber),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Questions Box
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBFAFF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFDCD8FF)),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Key details to confirm before quoting:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SoloDeskColors.ink),
                            ),
                            SizedBox(height: 8),
                            Text('• Deliverables: What exact cup and website asset formats are needed?', style: TextStyle(fontSize: 11)),
                            SizedBox(height: 4),
                            Text('• Timeline: What is the specific launch deadline next month?', style: TextStyle(fontSize: 11)),
                            SizedBox(height: 4),
                            Text('• Boundaries: Does website setup include development or graphics only?', style: TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Editable Deliverables List
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Starter Scope Deliverables',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: SoloDeskColors.ink),
                          ),
                          TextButton.icon(
                            onPressed: _addDeliverable,
                            icon: const Icon(Icons.add, size: 14),
                            label: const Text('Add item', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _starterDeliverables.length,
                        onReorderItem: (oldIdx, newIdx) {
                          setState(() {
                            final item = _starterDeliverables.removeAt(oldIdx);
                            _starterDeliverables.insert(newIdx, item);
                          });
                        },
                        itemBuilder: (ctx, idx) {
                          final item = _starterDeliverables[idx];
                          return Container(
                            key: ValueKey(item),
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: SoloDeskColors.borderLine),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_outline, size: 14, color: SoloDeskColors.green),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item,
                                    style: const TextStyle(fontSize: 11, color: SoloDeskColors.ink),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 14, color: SoloDeskColors.muted),
                                  onPressed: () => setState(() => _starterDeliverables.removeAt(idx)),
                                  tooltip: 'Remove deliverable',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 16),

                      // Action Button to Approve
                      ElevatedButton.icon(
                        onPressed: _starterDeliverables.isEmpty ? null : _approveScope,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SoloDeskColors.green,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.verified_outlined, size: 16),
                        label: const Text('✓ Approve Starting Scope'),
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
