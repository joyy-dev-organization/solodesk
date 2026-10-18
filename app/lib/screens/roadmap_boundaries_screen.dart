import 'package:flutter/material.dart';
import '../theme/colors.dart';

class RoadmapBoundariesScreen extends StatelessWidget {
  const RoadmapBoundariesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SoloDeskColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top breadcrumb & title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: SoloDeskColors.blueBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: SoloDeskColors.blueBorder),
                  ),
                  child: const Text(
                    'RELEASE SPECIFICATION · M8 FREEZE',
                    style: TextStyle(
                      color: SoloDeskColors.blue,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: SoloDeskColors.amberBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: SoloDeskColors.amberBorder),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.ac_unit, size: 12, color: SoloDeskColors.amber),
                      SizedBox(width: 4),
                      Text(
                        'FEATURE FREEZE ACTIVE',
                        style: TextStyle(
                          color: SoloDeskColors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Release Scope & Boundaries',
              style: TextStyle(
                color: SoloDeskColors.ink,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'SoloDesk v0.1.0-challenge — Honest delineation of verified working capabilities versus explicitly excluded features per Handbook Section 01, line 48.',
              style: TextStyle(
                color: SoloDeskColors.muted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),

            // Two-column layout
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Included in v0.1.0-challenge
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: SoloDeskColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: SoloDeskColors.borderLine),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: SoloDeskColors.greenBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.check_circle_outline, color: SoloDeskColors.green, size: 20),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Included in v0.1.0-challenge',
                                    style: TextStyle(
                                      color: SoloDeskColors.ink,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Verified working end-to-end with local open model',
                                    style: TextStyle(color: SoloDeskColors.muted, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Divider(color: SoloDeskColors.borderLine, height: 1),
                        const SizedBox(height: 16),
                        _buildFeatureItem(
                          icon: Icons.business,
                          title: 'My Services & Business Setup',
                          description: 'Select service categories, rates, business identity, and currency. Persisted locally in SQLite outside repository.',
                        ),
                        _buildFeatureItem(
                          icon: Icons.checklist_rounded,
                          title: 'BriefCheck Workflow',
                          description: 'Transforms vague briefs into grounded requirements, unstated omissions, clarifying questions, and human-approved immutable scope versions.',
                        ),
                        _buildFeatureItem(
                          icon: Icons.shield_outlined,
                          title: 'ScopeShield Evaluation',
                          description: 'Compares incoming requests against approved scope versions; itemized classifications (Included, Potentially Outside, Needs Clarification) with evidence excerpts.',
                        ),
                        _buildFeatureItem(
                          icon: Icons.receipt_long,
                          title: 'PolitePay Multi-Currency Accounting',
                          description: 'Integer minor-unit arithmetic, calendar due dates, zero cross-currency summing, and model-assisted polite payment reminders.',
                        ),
                        _buildFeatureItem(
                          icon: Icons.loop_rounded,
                          title: 'LeadLoop Opportunity Pipeline',
                          description: 'Local prospect tracking, unweighted pipeline sums, follow-up calendar alerts, and offline message draft templates.',
                        ),
                        _buildFeatureItem(
                          icon: Icons.autorenew_rounded,
                          title: 'Repeat Work Retainer Plans',
                          description: 'Retainer service plans with cadence-adjusted monthly income per currency and model-assisted renewal offer proposals.',
                        ),
                        _buildFeatureItem(
                          icon: Icons.computer_rounded,
                          title: 'Local Loopback Mastra Architecture',
                          description: 'Binds strictly to 127.0.0.1:3141, ephemeral Bearer token auth, single concurrency inference lock, and bounded timeout.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),

                // Right Column: Explicitly Excluded (Handbook Section 01, Line 48)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: SoloDeskColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: SoloDeskColors.borderLine),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: SoloDeskColors.redBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.block_rounded, color: SoloDeskColors.red, size: 20),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Excluded from this Submission',
                                    style: TextStyle(
                                      color: SoloDeskColors.ink,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Handbook Section 01, line 48 non-features',
                                    style: TextStyle(color: SoloDeskColors.muted, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Divider(color: SoloDeskColors.borderLine, height: 1),
                        const SizedBox(height: 16),
                        _buildExcludedItem('No client portal', 'Clients do not log in or view shared boards; SoloDesk is private to the freelancer.'),
                        _buildExcludedItem('No payment processing', 'No Stripe, PayPal, or card charging. SoloDesk is an accounting tracker, not a payment gateway.'),
                        _buildExcludedItem('No email / WhatsApp auto-dispatch', 'Drafts are copied to the clipboard for manual sending; SoloDesk never messages clients autonomously.'),
                        _buildExcludedItem('No cloud sync or cloud database', 'Data lives 100% in local SQLite on your PC; no remote servers sync records.'),
                        _buildExcludedItem('No team accounts or collaboration', 'Designed specifically as a solo tool for independent freelancers.'),
                        _buildExcludedItem('No currency conversion', 'Multi-currency sums are strictly segregated by ISO code; rates are never combined across currencies.'),
                        _buildExcludedItem('No legal determinations', 'Boundary classifications are editorial guidance for discussions, not binding legal advice or contract interpretation.'),
                        _buildExcludedItem('No automatic pricing or fees', 'Missing fees or change costs stay missing unless explicitly provided by the user.'),
                        _buildExcludedItem('No model fine-tuning or cloud fallback', 'Runs purely against local open-weight models (qwen3:1.7b) over loopback Ollama.'),
                        _buildExcludedItem('No mobile app release', 'Packaged exclusively as a Windows desktop application.'),
                        _buildExcludedItem('No vector database / RAG', 'In-context SQLite prompt injection only; inspectable deterministic workflows.'),
                        _buildExcludedItem('No autonomous background agents', 'Inference is explicitly triggered by user clicks with cancellation support.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Privacy & Data Boundary Banner
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: SoloDeskColors.primaryPale,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SoloDeskColors.borderLine),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline_rounded, color: SoloDeskColors.primary, size: 24),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Local Data & Storage Privacy Boundary',
                          style: TextStyle(color: SoloDeskColors.ink, fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'SoloDesk stores project data, client metadata, and approved scopes in a local SQLite database under your Windows user application support directory. Data at rest is unencrypted and relies on standard OS user profile permissions; it does not protect against physical host compromise. No prompt bodies, client records, or tokens are ever transmitted outside loopback (127.0.0.1).',
                          style: TextStyle(color: SoloDeskColors.muted, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: SoloDeskColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: SoloDeskColors.ink, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(color: SoloDeskColors.muted, fontSize: 12, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExcludedItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•', style: TextStyle(color: SoloDeskColors.red, fontSize: 16, height: 1.1)),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12, height: 1.3),
                children: [
                  TextSpan(
                    text: '$title: ',
                    style: const TextStyle(color: SoloDeskColors.ink, fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: description,
                    style: const TextStyle(color: SoloDeskColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
