import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../db/repository_scope.dart';
import '../models/brief_check_models.dart';
import '../models/client.dart';
import '../models/project.dart';
import '../models/money.dart';
import '../models/scope_item.dart';
import '../services/brief_check_client.dart';
import '../services/brief_check_exceptions.dart';
import '../theme/colors.dart';

enum BriefCheckUiState {
  idle,
  loading,
  success,
  error,
}

class EditableDeliverableItem {
  String title;
  String description;
  String category; // 'included', 'excluded', 'allowance'

  EditableDeliverableItem({
    required this.title,
    this.description = '',
    this.category = 'included',
  });

  String get fullText =>
      description.isNotEmpty ? '$title: $description' : title;
}

class BriefCheckScreen extends StatefulWidget {
  final VoidCallback? onScopeApproved;
  final BriefCheckClient? client;

  const BriefCheckScreen({
    super.key,
    this.onScopeApproved,
    this.client,
  });

  @override
  State<BriefCheckScreen> createState() => _BriefCheckScreenState();
}

class _BriefCheckScreenState extends State<BriefCheckScreen> {
  late final BriefCheckClient _client;

  final TextEditingController _briefController = TextEditingController(
    text: 'Hi, we are launching an organic coffee brand called MorningGlow next month. '
        'We need a modern, minimalist logo and some brand assets so we can start printing cups '
        'and setting up our website. Please keep it clean and earthy.',
  );

  String _selectedNiche = 'Design & branding';
  List<String> _userNiches = ['Design & branding', 'Writing & content'];

  BriefCheckUiState _uiState = BriefCheckUiState.idle;
  BriefCheckResult? _analysisResult;
  String? _errorMessage;
  String? _errorCode;

  // Elapsed timer during local inference
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;
  int? _lastInferenceDurationMs;

  // Editable deliverables
  final List<EditableDeliverableItem> _deliverables = [];

  // Approval state
  bool _isApproved = false;
  String? _approvedProjectTitle;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? BriefCheckClient();
    _briefController.addListener(_onBriefTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreferences());
  }

  void _onBriefTextChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _briefController.removeListener(_onBriefTextChanged);
    _briefController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    if (!mounted) return;
    try {
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
    } catch (_) {
      // Retain defaults if db not yet seeded
    }
  }

  void _startTimer() {
    _elapsedTimer?.cancel();
    _elapsedSeconds = 0;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  void _stopTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  Future<void> _runAnalysis() async {
    final briefText = _briefController.text.trim();
    if (briefText.isEmpty || briefText.length > 8000) return;

    setState(() {
      _uiState = BriefCheckUiState.loading;
      _errorMessage = null;
      _errorCode = null;
      _isApproved = false;
      _approvedProjectTitle = null;
    });
    _startTimer();

    final stopwatch = Stopwatch()..start();

    try {
      final scope = RepositoryScope.of(context);
      final prefs = await scope.preferenceRepo.getPreferences();

      final result = await _client.checkBrief(
        briefText: briefText,
        niche: _selectedNiche,
        preferences: prefs,
      );

      stopwatch.stop();
      _stopTimer();

      if (!mounted) return;

      setState(() {
        _analysisResult = result;
        _lastInferenceDurationMs = stopwatch.elapsedMilliseconds;
        _deliverables.clear();
        for (final item in result.starterScopeItems) {
          _deliverables.add(EditableDeliverableItem(
            title: item.title,
            description: item.description,
            category: 'included',
          ));
        }
        _uiState = BriefCheckUiState.success;
      });
    } on BriefCheckValidationException catch (e) {
      _handleError('Validation Error', e.message, e.code);
    } on BriefCheckConcurrencyException catch (e) {
      _handleError('Local Model Busy', e.message, e.code);
    } on BriefCheckModelOfflineException catch (e) {
      _handleError('Local Ollama Offline', e.message, e.code);
    } on BriefCheckTimeoutException catch (e) {
      _handleError('Analysis Timed Out', e.message, e.code);
    } on BriefCheckAuthException catch (e) {
      _handleError('Service Authentication Error', e.message, e.code);
    } on BriefCheckNetworkException catch (e) {
      _handleError('Service Unreachable', e.message, e.code);
    } catch (e) {
      _handleError('Analysis Error', e.toString(), 'UNKNOWN');
    }
  }

  void _handleError(String title, String message, String? code) {
    _stopTimer();
    if (!mounted) return;
    setState(() {
      _uiState = BriefCheckUiState.error;
      _errorMessage = '$title: $message';
      _errorCode = code;
    });
  }

  void _cancelAnalysis() {
    _stopTimer();
    setState(() {
      _uiState = BriefCheckUiState.idle;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Analysis cancelled.')),
    );
  }

  void _copyQuestions() {
    if (_analysisResult == null) return;
    final buffer = StringBuffer();
    buffer.writeln('Clarifying Questions for Brief:');
    for (final q in _analysisResult!.suggestedQuestions) {
      buffer.writeln('• $q');
    }
    if (_analysisResult!.omissions.isNotEmpty) {
      buffer.writeln('\nPotential Omissions:');
      for (final o in _analysisResult!.omissions) {
        buffer.writeln('• $o');
      }
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Questions copied to clipboard!'),
        backgroundColor: SoloDeskColors.ink,
      ),
    );
  }

  void _addDeliverable() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    String category = 'included';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Scope Deliverable'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Deliverable Title *',
                    hintText: 'e.g. Vector Logo Masters',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'e.g. Delivered as SVG, EPS, and high-res PNG',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Category:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Included'),
                      selected: category == 'included',
                      onSelected: (_) => setDialogState(() => category = 'included'),
                      selectedColor: SoloDeskColors.green.withValues(alpha: 0.2),
                    ),
                    ChoiceChip(
                      label: const Text('Excluded'),
                      selected: category == 'excluded',
                      onSelected: (_) => setDialogState(() => category = 'excluded'),
                      selectedColor: SoloDeskColors.amber.withValues(alpha: 0.2),
                    ),
                    ChoiceChip(
                      label: const Text('Allowance'),
                      selected: category == 'allowance',
                      onSelected: (_) => setDialogState(() => category = 'allowance'),
                      selectedColor: SoloDeskColors.primaryLight,
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isNotEmpty) {
                  setState(() {
                    _deliverables.add(EditableDeliverableItem(
                      title: title,
                      description: descController.text.trim(),
                      category: category,
                    ));
                  });
                }
                Navigator.pop(ctx);
              },
              child: const Text('Add Deliverable'),
            ),
          ],
        ),
      ),
    );
  }

  void _editDeliverable(int index) {
    final item = _deliverables[index];
    final titleController = TextEditingController(text: item.title);
    final descController = TextEditingController(text: item.description);
    String category = item.category;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit Deliverable'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Deliverable Title *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Description (optional)'),
                ),
                const SizedBox(height: 16),
                const Text('Category:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Included'),
                      selected: category == 'included',
                      onSelected: (_) => setDialogState(() => category = 'included'),
                      selectedColor: SoloDeskColors.green.withValues(alpha: 0.2),
                    ),
                    ChoiceChip(
                      label: const Text('Excluded'),
                      selected: category == 'excluded',
                      onSelected: (_) => setDialogState(() => category = 'excluded'),
                      selectedColor: SoloDeskColors.amber.withValues(alpha: 0.2),
                    ),
                    ChoiceChip(
                      label: const Text('Allowance'),
                      selected: category == 'allowance',
                      onSelected: (_) => setDialogState(() => category = 'allowance'),
                      selectedColor: SoloDeskColors.primaryLight,
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _deliverables.removeAt(index));
                Navigator.pop(ctx);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isNotEmpty) {
                  setState(() {
                    item.title = title;
                    item.description = descController.text.trim();
                    item.category = category;
                  });
                }
                Navigator.pop(ctx);
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _approveScope() {
    final clientNameController = TextEditingController(
      text: _extractClientNameCandidate(),
    );
    final projectTitleController = TextEditingController(
      text: _extractProjectTitleCandidate(),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve & Save Starting Scope'),
        content: SizedBox(
          width: 480,
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
                'Included Deliverables (${_deliverables.where((d) => d.category == 'included').length}):',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: ListView(
                  shrinkWrap: true,
                  children: _deliverables.map((d) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '• [${d.category.toUpperCase()}] ${d.title}',
                        style: const TextStyle(fontSize: 11, color: SoloDeskColors.ink),
                      ),
                    );
                  }).toList(),
                ),
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
              final items = _deliverables
                  .map((d) => ScopeItem(
                        id: const Uuid().v4(),
                        scopeVersionId: '',
                        category: d.category,
                        description: d.fullText,
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
                setState(() {
                  _isApproved = true;
                  _approvedProjectTitle = projectTitle;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Scope approved! Saved as immutable Version 1 for "$projectTitle".',
                    ),
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

  String _extractClientNameCandidate() {
    final text = _briefController.text;
    final brandMatch = RegExp(r'called\s+([A-Za-z0-9_-]+)', caseSensitive: false).firstMatch(text);
    if (brandMatch != null && brandMatch.group(1) != null) {
      return brandMatch.group(1)!;
    }
    return 'Client Account';
  }

  String _extractProjectTitleCandidate() {
    if (_analysisResult != null && _analysisResult!.starterScopeItems.isNotEmpty) {
      return _analysisResult!.starterScopeItems.first.title;
    }
    return 'Brand & Deliverables Scope';
  }

  Widget _buildRightPanel() {
    switch (_uiState) {
      case BriefCheckUiState.idle:
        return _buildIdlePanel();
      case BriefCheckUiState.loading:
        return _buildLoadingPanel();
      case BriefCheckUiState.success:
        return _buildSuccessPanel();
      case BriefCheckUiState.error:
        return _buildErrorPanel();
    }
  }

  Widget _buildIdlePanel() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: SoloDeskColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SoloDeskColors.borderLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 20, color: SoloDeskColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI Requirements & Starting Scope',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: SoloDeskColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Paste your client brief on the left and click "Analyze brief" to run local analysis with qwen3:1.7b.',
            style: TextStyle(fontSize: 13, color: SoloDeskColors.muted, height: 1.4),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SoloDeskColors.borderLine),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What BriefCheck will extract:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SoloDeskColors.ink),
                ),
                SizedBox(height: 10),
                Text('✓ Stated Requirements: Real client needs extracted without fabrication', style: TextStyle(fontSize: 11, color: SoloDeskColors.ink)),
                SizedBox(height: 6),
                Text('✓ Omissions & Questions: Missing details (timeline, budget, assets) flagged for quote accuracy', style: TextStyle(fontSize: 11, color: SoloDeskColors.ink)),
                SizedBox(height: 6),
                Text('✓ Starter Deliverables: Modular scope items ready for editing and approval', style: TextStyle(fontSize: 11, color: SoloDeskColors.ink)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Quick Test Briefs:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.palette_outlined, size: 14),
                label: const Text('Load Vague Design Brief', style: TextStyle(fontSize: 11)),
                onPressed: () {
                  setState(() {
                    _selectedNiche = 'Design & branding';
                    _briefController.text =
                        'We need a complete rebrand for our fintech startup called VaultFlow. Make it modern and trustworthy.';
                  });
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_note, size: 14),
                label: const Text('Load Specified Writing Brief', style: TextStyle(fontSize: 11)),
                onPressed: () {
                  setState(() {
                    _selectedNiche = 'Writing & content';
                    _briefController.text =
                        'Write four 1200-word SEO blog posts for our B2B SaaS product. Tone must be authoritative and targeted at engineering managers. Keyword list and content brief attached.';
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingPanel() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: SoloDeskColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SoloDeskColors.borderLine),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 3.5,
              valueColor: AlwaysStoppedAnimation<Color>(SoloDeskColors.primary),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Analyzing brief with local model ($_elapsedSeconds s)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: SoloDeskColors.ink),
          ),
          const SizedBox(height: 8),
          const Text(
            'Running local Mastra workflow on loopback 127.0.0.1:3141.\n'
            'Inference typically takes 20–35s on CPU. Your client data never leaves this machine.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: SoloDeskColors.muted, height: 1.4),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: _cancelAnalysis,
            child: const Text('Cancel Analysis'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD1D1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, size: 22, color: Colors.red),
              const SizedBox(width: 8),
              const Text(
                'Analysis Failed',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.red),
              ),
              const Spacer(),
              if (_errorCode != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _errorCode!,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.red),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? 'An error occurred during analysis.',
            style: const TextStyle(fontSize: 13, color: SoloDeskColors.ink, height: 1.4),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your original brief text is safe and preserved on the left. You can adjust the text or retry.',
            style: TextStyle(fontSize: 11, color: SoloDeskColors.muted),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _runAnalysis,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry Analysis'),
            style: ElevatedButton.styleFrom(
              backgroundColor: SoloDeskColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessPanel() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: SoloDeskColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SoloDeskColors.borderLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & duration badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Requirements & Starting Scope',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: SoloDeskColors.ink),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  if (_lastInferenceDurationMs != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: SoloDeskColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: SoloDeskColors.borderLine),
                      ),
                      child: Text(
                        '${(_lastInferenceDurationMs! / 1000).toStringAsFixed(1)}s',
                        style: const TextStyle(fontSize: 10, color: SoloDeskColors.muted),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: SoloDeskColors.greenBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'AI Verified',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: SoloDeskColors.green),
                    ),
                  ),
                ],
              ),
            ],
          ),

          if (_isApproved && _approvedProjectTitle != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SoloDeskColors.greenBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: SoloDeskColors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 18, color: SoloDeskColors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Scope Approved! Saved as immutable Version 1 for "$_approvedProjectTitle".',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SoloDeskColors.green),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Goal summary card
          if (_analysisResult != null && _analysisResult!.goalSummary.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: SoloDeskColors.borderLine),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Extracted Client Goal:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SoloDeskColors.muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _analysisResult!.goalSummary,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SoloDeskColors.ink),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Clarifying Questions Box
          if (_analysisResult != null &&
              (_analysisResult!.suggestedQuestions.isNotEmpty || _analysisResult!.omissions.isNotEmpty)) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFBFAFF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDCD8FF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Details to confirm before quoting:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SoloDeskColors.ink),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 14, color: SoloDeskColors.primary),
                        tooltip: 'Copy all questions to clipboard',
                        onPressed: _copyQuestions,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ..._analysisResult!.suggestedQuestions.map((q) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• $q', style: const TextStyle(fontSize: 11, color: SoloDeskColors.ink)),
                      )),
                  if (_analysisResult!.omissions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    ..._analysisResult!.omissions.map((o) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('• Omission: $o', style: const TextStyle(fontSize: 11, color: SoloDeskColors.amber)),
                        )),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],

          // Starter Scope Deliverables Editor
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Starter Deliverables (${_deliverables.length})',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: SoloDeskColors.ink),
              ),
              if (!_isApproved)
                TextButton.icon(
                  onPressed: _addDeliverable,
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Add deliverable', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 6),

          // Deliverables List
          if (_deliverables.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No deliverables extracted. Click "+ Add deliverable" to create one manually.',
                style: TextStyle(fontSize: 12, color: SoloDeskColors.muted),
              ),
            )
          else
            ...List.generate(_deliverables.length, (idx) {
              final d = _deliverables[idx];
              Color chipColor = SoloDeskColors.green;
              if (d.category == 'excluded') chipColor = SoloDeskColors.amber;
              if (d.category == 'allowance') chipColor = SoloDeskColors.primary;

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SoloDeskColors.borderLine),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: chipColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        d.category.toUpperCase(),
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: chipColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.title,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SoloDeskColors.ink),
                          ),
                          if (d.description.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              d.description,
                              style: const TextStyle(fontSize: 10, color: SoloDeskColors.muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!_isApproved) ...[
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 14, color: SoloDeskColors.muted),
                        onPressed: () => _editDeliverable(idx),
                        tooltip: 'Edit deliverable',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, size: 14, color: SoloDeskColors.muted),
                        onPressed: () => setState(() => _deliverables.removeAt(idx)),
                        tooltip: 'Remove deliverable',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ],
                ),
              );
            }),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),

          // Action Button to Approve
          ElevatedButton.icon(
            onPressed: (_deliverables.isEmpty || _isApproved) ? null : _approveScope,
            style: ElevatedButton.styleFrom(
              backgroundColor: SoloDeskColors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            icon: const Icon(Icons.verified_outlined, size: 16),
            label: Text(_isApproved ? '✓ Scope Approved (V1)' : '✓ Approve Starting Scope (V1)'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final charCount = _briefController.text.length;
    final isOverLimit = charCount > 8000;
    final isEmpty = _briefController.text.trim().isEmpty;
    final isAnalyzing = _uiState == BriefCheckUiState.loading;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
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
              ),
              const SizedBox(width: 16),
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
                            value: _userNiches.contains(_selectedNiche)
                                ? _selectedNiche
                                : (_userNiches.isNotEmpty ? _userNiches.first : null),
                            isExpanded: true,
                            items: _userNiches.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
                            onChanged: isAnalyzing
                                ? null
                                : (val) {
                                    if (val != null) setState(() => _selectedNiche = val);
                                  },
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('What did the client ask for?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          Text(
                            '$charCount / 8,000',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isOverLimit ? Colors.red : SoloDeskColors.muted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _briefController,
                        maxLines: 7,
                        enabled: !isAnalyzing,
                        decoration: InputDecoration(
                          hintText: 'Paste brief text here...',
                          errorText: isOverLimit ? 'Brief exceeds 8,000 character limit' : null,
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
                        onPressed: (isEmpty || isOverLimit || isAnalyzing) ? null : _runAnalysis,
                        icon: const Icon(Icons.auto_awesome, size: 16),
                        label: Text(isAnalyzing ? 'Analyzing...' : '✧ Analyze brief'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 20),

              // Right: Analysis Preview & Scope Deliverables
              Expanded(
                flex: 5,
                child: _buildRightPanel(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
