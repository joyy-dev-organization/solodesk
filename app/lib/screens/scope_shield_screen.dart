import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/repository_scope.dart';
import '../models/project.dart';
import '../models/scope_check_models.dart';
import '../models/scope_version.dart';
import '../services/scope_check_client.dart';
import '../services/scope_check_exceptions.dart';
import '../theme/colors.dart';

enum ScopeShieldUiState {
  idle,
  loading,
  success,
  error,
}

class ScopeShieldScreen extends StatefulWidget {
  final bool isSyntheticDemoActive;
  final ScopeCheckClient? client;

  const ScopeShieldScreen({
    super.key,
    required this.isSyntheticDemoActive,
    this.client,
  });

  @override
  State<ScopeShieldScreen> createState() => _ScopeShieldScreenState();
}

class _ScopeShieldScreenState extends State<ScopeShieldScreen> {
  late final ScopeCheckClient _client;

  final TextEditingController _requestController = TextEditingController(
    text: 'Could you also create 5 social media templates and a packaging label? We need them for the launch next week.',
  );
  final TextEditingController _replyController = TextEditingController();

  List<Project> _projects = [];
  Project? _selectedProject;
  List<ScopeVersionWithItems> _projectApprovedScopes = [];
  ScopeVersionWithItems? _currentScope;
  bool _isLoadingProjects = true;

  ScopeShieldUiState _uiState = ScopeShieldUiState.idle;
  ScopeCheckResult? _analysisResult;
  String? _errorMessage;
  String? _errorCode;

  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;
  int? _lastInferenceDurationMs;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? ScopeCheckClient();
    _requestController.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => loadProjects());
  }

  void _onTextChanged() {
    setState(() {});
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
    _elapsedTimer?.cancel();
    _requestController.removeListener(_onTextChanged);
    _requestController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  Future<void> loadProjects() async {
    if (!mounted) return;
    setState(() => _isLoadingProjects = true);

    final scope = RepositoryScope.of(context);
    final allProjects = await scope.projectRepo.getProjects(
      includeSynthetic: widget.isSyntheticDemoActive,
    );

    // Filter projects that have approved scope versions
    final validProjects = <Project>[];
    Project? firstValidProject;
    final firstScopes = <ScopeVersionWithItems>[];

    for (final p in allProjects) {
      final allVersions = await scope.scopeRepo.getVersionsForProject(p.id);
      final approved = allVersions.where((v) => v.isApproved).toList();
      if (approved.isNotEmpty) {
        validProjects.add(p);
        if (firstValidProject == null) {
          firstValidProject = p;
          for (final v in approved) {
            final full = await scope.scopeRepo.getVersionWithItems(v.id);
            if (full != null) firstScopes.add(full);
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _projects = validProjects;
        _selectedProject = firstValidProject;
        _projectApprovedScopes = firstScopes;
        _currentScope = firstScopes.isNotEmpty ? firstScopes.last : null;
        _isLoadingProjects = false;
      });
    }
  }

  Future<void> _loadScopeForProject(String projectId) async {
    final scope = RepositoryScope.of(context);
    final allVersions = await scope.scopeRepo.getVersionsForProject(projectId);
    final approved = allVersions.where((v) => v.isApproved).toList();
    final fullScopes = <ScopeVersionWithItems>[];
    for (final v in approved) {
      final full = await scope.scopeRepo.getVersionWithItems(v.id);
      if (full != null) fullScopes.add(full);
    }

    if (mounted) {
      setState(() {
        _projectApprovedScopes = fullScopes;
        _currentScope = fullScopes.isNotEmpty ? fullScopes.last : null;
      });
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

  Future<void> _runScopeCheck() async {
    final requestText = _requestController.text.trim();
    if (requestText.isEmpty || requestText.length > 8000) return;
    if (_currentScope == null || _currentScope!.items.isEmpty) return;

    setState(() {
      _uiState = ScopeShieldUiState.loading;
      _errorMessage = null;
      _errorCode = null;
    });
    _startTimer();

    final stopwatch = Stopwatch()..start();

    try {
      final result = await _client.checkScope(
        requestText: requestText,
        scopeVersionId: _currentScope!.version.id,
        scopeItems: _currentScope!.items,
        niche: _selectedProject?.niche ?? 'general',
      );

      stopwatch.stop();
      _stopTimer();

      if (!mounted) return;

      setState(() {
        _analysisResult = result;
        _lastInferenceDurationMs = stopwatch.elapsedMilliseconds;
        _replyController.text = result.replyDraft;
        _uiState = ScopeShieldUiState.success;
      });
    } on ScopeCheckValidationException catch (e) {
      _handleError('Validation Error', e.message, e.code);
    } on ScopeCheckConcurrencyException catch (e) {
      _handleError('Local Model Busy', e.message, e.code);
    } on ScopeCheckModelOfflineException catch (e) {
      _handleError('Local Ollama Offline', e.message, e.code);
    } on ScopeCheckTimeoutException catch (e) {
      _handleError('Inference Timed Out', e.message, e.code);
    } on ScopeCheckAuthException catch (e) {
      _handleError('Service Authentication Error', e.message, e.code);
    } on ScopeCheckNetworkException catch (e) {
      _handleError('Service Unreachable', e.message, e.code);
    } catch (e) {
      _handleError('Comparison Error', e.toString(), 'UNKNOWN');
    }
  }

  void _handleError(String title, String message, String? code) {
    _stopTimer();
    if (!mounted) return;
    setState(() {
      _uiState = ScopeShieldUiState.error;
      _errorMessage = '$title: $message';
      _errorCode = code;
    });
  }

  void _cancelAnalysis() {
    _stopTimer();
    setState(() {
      _uiState = ScopeShieldUiState.idle;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scope evaluation cancelled.')),
    );
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

  void _copyReply() {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reply copied to clipboard! Ready to paste into email or messaging app.'),
        backgroundColor: SoloDeskColors.ink,
      ),
    );
  }

  Widget _buildRightPanel() {
    switch (_uiState) {
      case ScopeShieldUiState.idle:
        return _buildIdlePanel();
      case ScopeShieldUiState.loading:
        return _buildLoadingPanel();
      case ScopeShieldUiState.success:
        return _buildSuccessPanel();
      case ScopeShieldUiState.error:
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
              Icon(Icons.shield_outlined, size: 20, color: SoloDeskColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Scope Boundary Evaluation',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: SoloDeskColors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Paste an incoming message from your client on the left. ScopeShield compares each request item against your approved SQLite deliverables using local qwen3:1.7b.',
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
                  'ScopeShield Boundary Policy:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SoloDeskColors.ink),
                ),
                SizedBox(height: 10),
                Text('✓ Included: Tasks covered by baseline deliverables or agreed revision limits.', style: TextStyle(fontSize: 11, color: SoloDeskColors.ink)),
                SizedBox(height: 6),
                Text('✓ Potentially Out of Scope: New deliverables, extra features, or explicit exclusions.', style: TextStyle(fontSize: 11, color: SoloDeskColors.ink)),
                SizedBox(height: 6),
                Text('✓ Needs Clarification: Vague or subjective requests ("make it pop", "more energy").', style: TextStyle(fontSize: 11, color: SoloDeskColors.ink)),
                SizedBox(height: 6),
                Text('✓ Human Control: Nothing is sent, charged, or added to approved scope automatically.', style: TextStyle(fontSize: 11, color: SoloDeskColors.muted)),
              ],
            ),
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
            'Comparing request against approved scope ($_elapsedSeconds s)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: SoloDeskColors.ink),
          ),
          const SizedBox(height: 8),
          const Text(
            'Running local Mastra workflow on loopback 127.0.0.1:3141.\n'
            'Evaluating item-level boundaries with local qwen3:1.7b. Zero client data leaves this machine.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: SoloDeskColors.muted, height: 1.4),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: _cancelAnalysis,
            child: const Text('Cancel Evaluation'),
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
                'Scope Evaluation Failed',
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
            _errorMessage ?? 'An error occurred during scope evaluation.',
            style: const TextStyle(fontSize: 13, color: SoloDeskColors.ink, height: 1.4),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your client request text is safe and preserved on the left. You can adjust the text or retry.',
            style: TextStyle(fontSize: 11, color: SoloDeskColors.muted),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _runScopeCheck,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry Comparison'),
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
    final result = _analysisResult!;

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
          // Header & summary badges
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Scope Comparison Results',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: SoloDeskColors.ink),
                ),
              ),
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

          const SizedBox(height: 12),

          // Count breakdown pills
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (result.includedCount > 0)
                _buildCountBadge(result.includedCount, 'Included', SoloDeskColors.green, SoloDeskColors.greenBg),
              if (result.outsideCount > 0)
                _buildCountBadge(result.outsideCount, 'Potentially Outside', SoloDeskColors.amber, SoloDeskColors.amberBg),
              if (result.clarificationCount > 0)
                _buildCountBadge(result.clarificationCount, 'Needs Clarification', SoloDeskColors.primary, SoloDeskColors.primaryPale),
            ],
          ),

          const SizedBox(height: 16),

          // Itemized Findings List
          const Text(
            'Itemized Evaluations:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SoloDeskColors.ink),
          ),
          const SizedBox(height: 8),

          ...result.findings.map((finding) {
            // Deliverable reference resolution
            String scopeRefText = 'No matching scope deliverable found in approved agreement';
            bool hasMatch = false;

            if (finding.matchedScopeItemId != null && _currentScope != null) {
              final match = _currentScope!.items
                  .where((item) => item.id == finding.matchedScopeItemId)
                  .firstOrNull;
              if (match != null) {
                scopeRefText = 'Agreed Scope: ${match.description}';
                hasMatch = true;
              } else if (finding.matchedScopeItemDescription != null &&
                  finding.matchedScopeItemDescription!.isNotEmpty &&
                  !finding.matchedScopeItemDescription!.toLowerCase().contains('no matching')) {
                scopeRefText = 'Agreed Scope: ${finding.matchedScopeItemDescription}';
                hasMatch = true;
              }
            } else if (finding.matchedScopeItemDescription != null &&
                finding.matchedScopeItemDescription!.isNotEmpty &&
                !finding.matchedScopeItemDescription!.toLowerCase().contains('no matching')) {
              scopeRefText = 'Agreed Scope: ${finding.matchedScopeItemDescription}';
              hasMatch = true;
            }

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: SoloDeskColors.borderLine),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: finding.classification.backgroundColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          finding.classification.label,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: finding.classification.foregroundColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '“${finding.requestExcerpt}”',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontStyle: FontStyle.italic,
                            color: SoloDeskColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        hasMatch ? Icons.check_circle_outline : Icons.info_outline,
                        size: 13,
                        color: hasMatch ? SoloDeskColors.green : SoloDeskColors.amber,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          hasMatch ? '✓ $scopeRefText' : scopeRefText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: hasMatch ? SoloDeskColors.green : SoloDeskColors.amber,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (finding.explanation.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      finding.explanation,
                      style: const TextStyle(fontSize: 11, color: SoloDeskColors.muted, height: 1.3),
                    ),
                  ],
                ],
              ),
            );
          }),

          const SizedBox(height: 18),

          // Suggested Response Draft
          const Text(
            'Suggested Response Draft (Editable)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SoloDeskColors.ink),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _replyController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Review and adjust your response to the client...',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _copyReply,
                icon: const Icon(Icons.copy_outlined, size: 14),
                label: const Text('▣ Copy suggested reply'),
              ),
              const Text(
                'Nothing sent automatically',
                style: TextStyle(fontSize: 11, color: SoloDeskColors.muted),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: SoloDeskColors.borderLine),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline, size: 14, color: SoloDeskColors.muted),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'SoloDesk Boundary Policy: Nothing is sent, charged, or added to approved scope automatically. Review before sending to your client.',
                    style: TextStyle(fontSize: 10, color: SoloDeskColors.muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountBadge(int count, String label, Color foreground, Color background) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: foreground),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingProjects) {
      return const Center(child: CircularProgressIndicator());
    }

    final charCount = _requestController.text.length;
    final isOverLimit = charCount > 8000;
    final isEmpty = _requestController.text.trim().isEmpty;
    final isAnalyzing = _uiState == ScopeShieldUiState.loading;
    final hasNoScope = _currentScope == null || _currentScope!.items.isEmpty;

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
              ),
              const SizedBox(width: 16),
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
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.shield_outlined, size: 48, color: SoloDeskColors.muted),
                    const SizedBox(height: 12),
                    const Text(
                      'No saved project scopes to evaluate',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Approve a scope in BriefCheck or toggle "Load Demo Data" to test ScopeShield.',
                      style: TextStyle(fontSize: 12, color: SoloDeskColors.muted),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            DefaultTabController.of(context).animateTo(2);
                          },
                          child: const Text('Go to BriefCheck'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Agreement & New Request Input
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
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${p.name} (${p.niche})',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (p.isSynthetic) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFFCBD5E1)),
                                          ),
                                          child: const Text(
                                            'DEMO RECORD',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF475569),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: isAnalyzing
                                  ? null
                                  : (proj) {
                                      if (proj != null) {
                                        setState(() => _selectedProject = proj);
                                        _loadScopeForProject(proj.id);
                                      }
                                    },
                            ),
                          ),
                        ),

                        if (_projectApprovedScopes.length > 1) ...[
                          const SizedBox(height: 12),
                          const Text('Approved Scope Version', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: SoloDeskColors.borderLine),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<ScopeVersionWithItems>(
                                value: _currentScope,
                                isExpanded: true,
                                items: _projectApprovedScopes.map((s) {
                                  return DropdownMenuItem(
                                    value: s,
                                    child: Text('Version ${s.version.versionNumber}: ${s.version.title} (${s.items.length} deliverables)'),
                                  );
                                }).toList(),
                                onChanged: isAnalyzing
                                    ? null
                                    : (val) {
                                        if (val != null) {
                                          setState(() => _currentScope = val);
                                        }
                                      },
                              ),
                            ),
                          ),
                        ],

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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('New client request', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
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
                          controller: _requestController,
                          maxLines: 4,
                          enabled: !isAnalyzing,
                          decoration: InputDecoration(
                            hintText: 'Paste incoming email or WhatsApp message from client...',
                            errorText: isOverLimit ? 'Request exceeds 8,000 character limit' : null,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Preset buttons
                        const Text('Load Quick Sample:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SoloDeskColors.muted)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                textStyle: const TextStyle(fontSize: 10),
                              ),
                              onPressed: isAnalyzing
                                  ? null
                                  : () {
                                      setState(() {
                                        _requestController.text =
                                            'Thanks for the first logo draft! Can we tweak the green shade to a darker forest green and test the subtitle in uppercase? This is our first round of revisions.';
                                      });
                                    },
                              child: const Text('Load Included Request'),
                            ),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                textStyle: const TextStyle(fontSize: 10),
                              ),
                              onPressed: isAnalyzing
                                  ? null
                                  : () {
                                      setState(() {
                                        _requestController.text =
                                            'The landing page looks great! Can we also add a Stripe checkout so visitors can buy our \$50 consulting package directly on this page?';
                                      });
                                    },
                              child: const Text('Load Scope Creep Request'),
                            ),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                textStyle: const TextStyle(fontSize: 10),
                              ),
                              onPressed: isAnalyzing
                                  ? null
                                  : () {
                                      setState(() {
                                        _requestController.text =
                                            'We love draft #2! Please adjust the subheader on section 3 (that is revision 1). Also, our team decided we need a custom mobile app built in Flutter for internal auditing.';
                                      });
                                    },
                              child: const Text('Load Mixed Request'),
                            ),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                textStyle: const TextStyle(fontSize: 10),
                              ),
                              onPressed: isAnalyzing
                                  ? null
                                  : () {
                                      setState(() {
                                        _requestController.text =
                                            'The back label feels a bit flat. Can we add something premium to make it really pop and stand out from competitors on the shelf?';
                                      });
                                    },
                              child: const Text('Load Ambiguous Request'),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),
                        ElevatedButton.icon(
                          onPressed: (isEmpty || isOverLimit || isAnalyzing || hasNoScope)
                              ? null
                              : _runScopeCheck,
                          icon: const Icon(Icons.shield_outlined, size: 16),
                          label: Text(isAnalyzing ? 'Evaluating...' : '⛨ Compare with agreed scope'),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 20),

                // Right: Comparison Results & Reply Draft
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
