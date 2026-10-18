import 'package:flutter/material.dart';
import 'db/repository_scope.dart';
import 'services/service_health.dart';
import 'widgets/app_sidebar.dart';
import 'widgets/app_header.dart';
import 'screens/overview_screen.dart';
import 'screens/my_services_screen.dart';
import 'screens/brief_check_screen.dart';
import 'screens/scope_shield_screen.dart';
import 'screens/polite_pay_screen.dart';
import 'screens/lead_loop_screen.dart';
import 'screens/repeat_work_screen.dart';

class AppShell extends StatefulWidget {
  final ServiceHealthClient healthClient;
  final bool enableHealthPolling;

  const AppShell({
    super.key,
    required this.healthClient,
    this.enableHealthPolling = true,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  bool _isSyntheticDemoActive = false;
  String _businessName = 'ladydiamond';

  static const List<String> screenTitles = [
    'Overview',
    'LeadLoop',
    'BriefCheck',
    'ScopeShield',
    'PolitePay',
    'Repeat Work',
    'My services',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initPreferencesAndDemoState());
  }

  Future<void> _initPreferencesAndDemoState() async {
    if (!mounted) return;
    final scope = RepositoryScope.of(context);
    final prefs = await scope.preferenceRepo.getPreferences();
    final hasDemo = await scope.demoDataRepo.hasSyntheticData();
    if (mounted) {
      setState(() {
        _businessName = prefs.businessName;
        _isSyntheticDemoActive = hasDemo;
      });
    }
  }

  Future<void> _toggleSyntheticDemo() async {
    final scope = RepositoryScope.of(context);
    try {
      if (_isSyntheticDemoActive) {
        // Purge
        await scope.demoDataRepo.purgeSyntheticData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Synthetic demo records purged. Workspace restored to clean local state.')),
          );
        }
      } else {
        // Seed
        await scope.demoDataRepo.seedSyntheticData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Synthetic demo records loaded for testing and exploration.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update demo data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        final hasDemo = await scope.demoDataRepo.hasSyntheticData();
        setState(() => _isSyntheticDemoActive = hasDemo);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // 1. Fixed Left Desktop Sidebar
          AppSidebar(
            selectedIndex: _selectedIndex,
            onSelect: (index) => setState(() => _selectedIndex = index),
            businessName: _businessName,
          ),

          // 2. Main Content Area
          Expanded(
            child: Column(
              children: [
                // Topbar
                AppHeader(
                  screenName: screenTitles[_selectedIndex],
                  healthClient: widget.healthClient,
                  enableHealthPolling: widget.enableHealthPolling,
                  isSyntheticDemoActive: _isSyntheticDemoActive,
                  onToggleSyntheticDemo: _toggleSyntheticDemo,
                ),

                // Active Screen Viewport (Preserved via IndexedStack)
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      OverviewScreen(
                        onNavigate: (index) => setState(() => _selectedIndex = index),
                        isSyntheticDemoActive: _isSyntheticDemoActive,
                      ),
                      LeadLoopScreen(
                        isSyntheticDemoActive: _isSyntheticDemoActive,
                        onNavigate: (index) => setState(() => _selectedIndex = index),
                      ),
                      BriefCheckScreen(
                        onScopeApproved: () {
                          // Refresh overview or switch
                          setState(() {});
                        },
                      ),
                      ScopeShieldScreen(
                        isSyntheticDemoActive: _isSyntheticDemoActive,
                        onNavigate: (index) => setState(() => _selectedIndex = index),
                      ),
                      PolitePayScreen(
                        isSyntheticDemoActive: _isSyntheticDemoActive,
                      ),
                      RepeatWorkScreen(
                        isSyntheticDemoActive: _isSyntheticDemoActive,
                        onNavigate: (index) => setState(() => _selectedIndex = index),
                      ),
                      MyServicesScreen(
                        onSaved: () => _initPreferencesAndDemoState(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
