import 'package:flutter/material.dart';
import '../theme/colors.dart';

class AppSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final String businessName;

  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    this.businessName = 'ladydiamond',
  });

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return 'LD';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: SoloDeskColors.sidebarNav,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Brand Header
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 24, bottom: 20),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B7FFF), Color(0xFF6151D3)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x445E51CA),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'S',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'SoloDesk',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'YOUR FREELANCE HQ',
                        style: TextStyle(
                          color: Color(0xFFA9A7C4),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. Navigation Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                const _NavSectionHeader(title: 'WORKSPACE'),
                _NavItem(
                  icon: Icons.dashboard_outlined,
                  title: 'Overview',
                  isSelected: selectedIndex == 0,
                  onTap: () => onSelect(0),
                ),
                _NavItem(
                  icon: Icons.people_outline,
                  title: 'LeadLoop',
                  badge: 'P2',
                  isSelected: selectedIndex == 1,
                  onTap: () => onSelect(1),
                ),
                _NavItem(
                  icon: Icons.assignment_outlined,
                  title: 'BriefCheck',
                  badge: 'AI',
                  badgeColor: SoloDeskColors.primary,
                  isSelected: selectedIndex == 2,
                  onTap: () => onSelect(2),
                ),
                _NavItem(
                  icon: Icons.shield_outlined,
                  title: 'ScopeShield',
                  isSelected: selectedIndex == 3,
                  onTap: () => onSelect(3),
                ),
                _NavItem(
                  icon: Icons.attach_money_outlined,
                  title: 'PolitePay',
                  badge: 'P1',
                  isSelected: selectedIndex == 4,
                  onTap: () => onSelect(4),
                ),
                _NavItem(
                  icon: Icons.autorenew_outlined,
                  title: 'Repeat Work',
                  badge: 'P2',
                  isSelected: selectedIndex == 5,
                  onTap: () => onSelect(5),
                ),
                const SizedBox(height: 16),
                const _NavSectionHeader(title: 'MANAGE'),
                _NavItem(
                  icon: Icons.settings_outlined,
                  title: 'My services',
                  isSelected: selectedIndex == 6,
                  onTap: () => onSelect(6),
                ),
              ],
            ),
          ),

          // 3. Bottom Local Privacy Card & User Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              children: [
                // Local Privacy Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x0DFFFFFF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x1AFFFFFF)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PRIVACY MODE',
                        style: TextStyle(
                          color: Color(0xFFA09FBE),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '◉ Local-first AI',
                        style: TextStyle(
                          color: Color(0xFFF5F4FF),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Client information stays on your device when paired with a local model.',
                        style: TextStyle(
                          color: Color(0xFFAEADC6),
                          fontSize: 10,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(color: Color(0x1AFFFFFF)),
                const SizedBox(height: 8),

                // User profile avatar
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFDE1CA),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          _getInitials(businessName),
                          style: const TextStyle(
                            color: Color(0xFF7D4324),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            businessName.split('·')[0].trim(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Text(
                            'Independent freelancer',
                            style: TextStyle(
                              color: Color(0xFFA8A6C3),
                              fontSize: 10,
                            ),
                          ),
                        ],
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

class _NavSectionHeader extends StatelessWidget {
  final String title;

  const _NavSectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 10, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          color: SoloDeskColors.navMuted,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? badge;
  final Color? badgeColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.title,
    this.badge,
    this.badgeColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected ? SoloDeskColors.navActive : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: SoloDeskColors.sidebarHover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? Colors.white : SoloDeskColors.navText,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : SoloDeskColors.navText,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor ?? const Color(0x26FFFFFF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
