import 'package:flutter/material.dart';
import '../screens/roadmap_boundaries_screen.dart';
import '../services/service_health.dart';
import '../theme/colors.dart';
import 'service_health_badge.dart';

class AppHeader extends StatelessWidget {
  final String screenName;
  final ServiceHealthClient healthClient;
  final bool isSyntheticDemoActive;
  final VoidCallback onToggleSyntheticDemo;
  final bool enableHealthPolling;

  const AppHeader({
    super.key,
    required this.screenName,
    required this.healthClient,
    required this.isSyntheticDemoActive,
    required this.onToggleSyntheticDemo,
    this.enableHealthPolling = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: SoloDeskColors.borderLine),
        ),
      ),
      child: Row(
        children: [
          // 1. Breadcrumbs
          Row(
            children: [
              const Text(
                'Workspace',
                style: TextStyle(
                  color: SoloDeskColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '/',
                  style: TextStyle(color: Color(0xFFC3C5D3)),
                ),
              ),
              Text(
                screenName,
                style: const TextStyle(
                  color: SoloDeskColors.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),

          const Spacer(),

          // 2. Feature Freeze Status Pill
          Tooltip(
            message: 'SoloDesk v0.1.0-challenge · Feature Freeze Active. Click to view scope boundaries.',
            child: InkWell(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => Dialog(
                    backgroundColor: SoloDeskColors.background,
                    insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: const SizedBox(
                        width: 1000,
                        height: 700,
                        child: RoadmapBoundariesScreen(),
                      ),
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.ac_unit, size: 12, color: Color(0xFFD97706)),
                    SizedBox(width: 4),
                    Text(
                      'Freeze Active',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // 3. Synthetic Demo Data Toggle Button
          OutlinedButton.icon(
            onPressed: onToggleSyntheticDemo,
            style: OutlinedButton.styleFrom(
              backgroundColor: isSyntheticDemoActive ? SoloDeskColors.primaryPale : Colors.white,
              side: BorderSide(
                color: isSyntheticDemoActive ? SoloDeskColors.primaryLight : SoloDeskColors.borderLine,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            icon: Icon(
              isSyntheticDemoActive ? Icons.check_circle : Icons.dataset_outlined,
              size: 15,
              color: isSyntheticDemoActive ? SoloDeskColors.primary : SoloDeskColors.muted,
            ),
            label: Text(
              isSyntheticDemoActive ? 'Demo Data: ON' : 'Load Demo Data',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isSyntheticDemoActive ? SoloDeskColors.primary : SoloDeskColors.ink,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // 4. Service Health Indicator Badge
          ServiceHealthBadge(
            healthClient: healthClient,
            enablePolling: enableHealthPolling,
          ),
        ],
      ),
    );
  }
}
