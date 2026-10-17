import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../db/repository_scope.dart';
import '../models/project.dart';
import '../models/scope_version.dart';
import '../theme/colors.dart';

class ScopeShieldScreen extends StatefulWidget {
  final bool isSyntheticDemoActive;

  const ScopeShieldScreen({
    super.key,
    required this.isSyntheticDemoActive,
  });

  @override
  State<ScopeShieldScreen> createState() => _ScopeShieldScreenState();
}

class _ScopeShieldScreenState extends State<ScopeShieldScreen> {
  final TextEditingController _requestController = TextEditingController(
    text: 'Could you also create 5 social media templates and a packaging label? We need them for the launch next week.',
  );
  final TextEditingController _replyController = TextEditingController(
    text: '“Thanks for sharing these additional launch needs. The social templates and packaging label are not listed in our agreed scope. '
        'I can prepare a separate estimate and timeline for these items so we can agree on them before I begin.”',
  );

  List<Project> _projects = [];
  Project? _selectedProject;
  ScopeVersionWithItems? _currentScope;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => loadProjects());
  }

  @override
  void didUpdateWidget(covariant ScopeShieldScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSyntheticDemoActive != widget.isSyntheticDemoActive) {
      loadProjects();
    }
  }

  @override
  void dispose() {
    _requestController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  Future<void> loadProjects() async {
    if (!mounted) return;
    final scope = RepositoryScope.of(context);
    final projects = await scope.projectRepo.getProjects(
      includeSynthetic: widget.isSyntheticDemoActive,
    );

    if (mounted) {
      setState(() {
        _projects = projects;
        if (_projects.isNotEmpty) {
          _selectedProject = _projects.first;
          _loadScopeForProject(_selectedProject!.id);
        } else {
          _selectedProject = null;
          _currentScope = null;
          _isLoading = false;
        }
      });
    }
  }

  Future<void> _loadScopeForProject(String projectId) async {
    final scope = RepositoryScope.of(context);
    final approved = await scope.scopeRepo.getLatestApprovedVersion(projectId);
    if (mounted) {
      setState(() {
        _currentScope = approved;
        _isLoading = false;
      });
    }
  }

  void _branchNewRevision() async {
    if (_currentScope == null) return;

    final repo = RepositoryScope.of(context).scopeRepo;
    final revision = await repo.createRevisionFromApproved(
      _currentScope!.version.id,
      newTitle: '${_currentScope!.version.title} (Revision)',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Branched new draft Version ${revision.version.versionNumber} for editing.'),
          backgroundColor: SoloDeskColors.primary,
        ),
      );
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
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SCOPESHIELD · PROJECT BOUNDARIES',
                    style: TextStyle(
                      color: SoloDeskColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Make changes visible before they become unpaid work.',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      color: SoloDeskColors.ink,
                      letterSpacing: -0.9,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Compare client requests against agreed deliverables stored in local SQLite.',
                    style: TextStyle(fontSize: 13, color: SoloDeskColors.muted),
                  ),
                ],
              ),
              if (_currentScope != null && _currentScope!.version.isApproved)
                OutlinedButton.icon(
                  onPressed: _branchNewRevision,
                  icon: const Icon(Icons.fork_right_outlined, size: 16),
                  label: const Text('Branch New Revision'),
                ),
            ],
          ),

          const SizedBox(height: 24),

          if (_projects.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: SoloDeskColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: SoloDeskColors.borderLine),
              ),
              child: const Center(
                child: Column(
                  children: [
                    Icon(Icons.shield_outlined, size: 48, color: SoloDeskColors.muted),
                    SizedBox(height: 12),
                    Text(
                      'No saved project scopes to evaluate',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Approve a scope in BriefCheck or toggle "Load Demo Data" to test ScopeShield.',
                      style: TextStyle(fontSize: 12, color: SoloDeskColors.muted),
                    ),
                  ],
                ),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Agreement & New Request
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
                          'Project agreement',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: SoloDeskColors.ink),
                        ),
                        const SizedBox(height: 14),

                        // Project selector
                        const Text('Active Project', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: SoloDeskColors.borderLine),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<Project>(
                              value: _selectedProject,
                              isExpanded: true,
                              items: _projects.map((p) {
                                return DropdownMenuItem(
                                  value: p,
                                  child: Text('${p.name} (${p.niche})'),
                                );
                              }).toList(),
                              onChanged: (proj) {
                                if (proj != null) {
                                  setState(() => _selectedProject = proj);
                                  _loadScopeForProject(proj.id);
                                }
                              },
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Deliverables chips
                        Row(
                          children: [
                            const Text('Agreed deliverables', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            const SizedBox(width: 8),
                            if (_currentScope != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: SoloDeskColors.greenBg,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'v${_currentScope!.version.versionNumber} Approved',
                                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: SoloDeskColors.green),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        if (_currentScope == null || _currentScope!.items.isEmpty)
                          const Text('No approved deliverables found for this project.', style: TextStyle(fontSize: 11, color: SoloDeskColors.muted))
                        else
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _currentScope!.items.map((item) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                decoration: BoxDecoration(
                                  color: SoloDeskColors.greenBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: SoloDeskColors.greenBorder),
                                ),
                                child: Text(
                                  '✓ ${item.description}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: SoloDeskColors.green,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),

                        const SizedBox(height: 18),
                        const Divider(),
                        const SizedBox(height: 14),

                        // Request input
                        const Text('New client request', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _requestController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText: 'Paste incoming email or WhatsApp message from client...',
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('ScopeShield comparison preview updated.')),
                            );
                          },
                          icon: const Icon(Icons.shield_outlined, size: 16),
                          label: const Text('⛨ Compare with agreed scope'),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 20),

                // Right: Comparison Results & Reply Draft
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
                              'Scope comparison',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: SoloDeskColors.ink),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: SoloDeskColors.amberBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Potentially out of scope',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: SoloDeskColors.amber),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Delta Chips
                        const Text(
                          'Identified deliverables not in agreement:',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SoloDeskColors.ink),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: SoloDeskColors.amberBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: SoloDeskColors.amberBorder),
                              ),
                              child: const Text(
                                '＋ 5 social media templates',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SoloDeskColors.amber),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: SoloDeskColors.amberBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: SoloDeskColors.amberBorder),
                              ),
                              child: const Text(
                                '＋ Packaging label',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SoloDeskColors.amber),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),
                        const Text(
                          'The approved scope includes primary logo, colour palette, typography guide, 2 revision rounds, and brand PDF. '
                          'It does not list social templates or packaging design.',
                          style: TextStyle(fontSize: 11, color: SoloDeskColors.muted, height: 1.4),
                        ),

                        const SizedBox(height: 18),

                        // Response Draft Box
                        const Text(
                          'Suggested response draft (editable)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SoloDeskColors.ink),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _replyController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText: 'Edit your suggested response...',
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _replyController.text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Response copied to clipboard!')),
                            );
                          },
                          icon: const Icon(Icons.copy_outlined, size: 14),
                          label: const Text('▣ Copy suggested reply'),
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
