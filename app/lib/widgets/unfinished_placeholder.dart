import 'package:flutter/material.dart';
import '../theme/colors.dart';

class UnfinishedPlaceholder extends StatelessWidget {
  final String title;
  final String milestone;
  final String description;
  final String plannedDetails;
  final IconData icon;

  const UnfinishedPlaceholder({
    super.key,
    required this.title,
    required this.milestone,
    required this.description,
    required this.plannedDetails,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: SoloDeskColors.amberBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: SoloDeskColors.amberBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.schedule,
                  color: SoloDeskColors.amber,
                  size: 28,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: SoloDeskColors.amber,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: SoloDeskColors.amberBorder),
                            ),
                            child: Text(
                              milestone,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: SoloDeskColors.amber,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Not included in this release',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: SoloDeskColors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 13,
                          color: SoloDeskColors.ink,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // Technical Roadmap Note Card
          Container(
            width: double.infinity,
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
                    Icon(icon, color: SoloDeskColors.primary, size: 24),
                    const SizedBox(width: 12),
                    const Text(
                      'Roadmap Specification',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: SoloDeskColors.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  plannedDetails,
                  style: const TextStyle(
                    fontSize: 13,
                    color: SoloDeskColors.muted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.lock_clock, size: 16, color: SoloDeskColors.muted),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Per SoloDesk Build Handbook, foundational BriefCheck and ScopeShield are delivered first.',
                        style: TextStyle(
                          fontSize: 12,
                          color: SoloDeskColors.muted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
