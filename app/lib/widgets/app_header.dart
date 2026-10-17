import 'package:flutter/material.dart';
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
      padding: const EdgeInsets.symmetric(horizontal: 28),
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

          // 2. Synthetic Demo Data Toggle Button
          OutlinedButton.icon(
            onPressed: onToggleSyntheticDemo,
            style: OutlinedButton.styleFrom(
              backgroundColor: isSyntheticDemoActive ? SoloDeskColors.primaryPale : Colors.white,
              side: BorderSide(
                color: isSyntheticDemoActive ? SoloDeskColors.primaryLight : SoloDeskColors.borderLine,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            icon: Icon(
              isSyntheticDemoActive ? Icons.check_circle : Icons.dataset_outlined,
              size: 16,
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

          const SizedBox(width: 14),

          // 3. Service Health Indicator Badge
          ServiceHealthBadge(
            healthClient: healthClient,
            enablePolling: enableHealthPolling,
          ),
        ],
      ),
    );
  }
}
