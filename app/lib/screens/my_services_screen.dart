import 'package:flutter/material.dart';
import '../db/repository_scope.dart';
import '../models/service_preference.dart';
import '../theme/colors.dart';

class MyServicesScreen extends StatefulWidget {
  final VoidCallback? onSaved;

  const MyServicesScreen({super.key, this.onSaved});

  @override
  State<MyServicesScreen> createState() => _MyServicesScreenState();
}

class _MyServicesScreenState extends State<MyServicesScreen> {
  static const List<String> allNiches = [
    'Design & branding',
    'Writing & content',
    'Software & development',
    'Marketing & social media',
    'Photography & video',
    'Consulting & coaching',
    'Virtual assistance',
    'Education & tutoring',
    'Finance & operations',
    'Trades & local services',
    'Other',
  ];

  static const List<Map<String, String>> currencies = [
    {'code': 'NGN', 'label': 'NGN — Nigerian naira (₦)'},
    {'code': 'USD', 'label': 'USD — US dollar (\$)'},
    {'code': 'EUR', 'label': 'EUR — Euro (€)'},
    {'code': 'GBP', 'label': 'GBP — British pound (£)'},
    {'code': 'GHS', 'label': 'GHS — Ghanaian cedi (GH₵)'},
  ];

  late TextEditingController _businessNameController;
  final Set<String> _selectedNiches = {};
  String _defaultCurrency = 'NGN';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _businessNameController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreferences());
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    if (!mounted) return;
    final repo = RepositoryScope.of(context).preferenceRepo;
    final prefs = await repo.getPreferences();
    if (mounted) {
      setState(() {
        _selectedNiches.clear();
        _selectedNiches.addAll(prefs.niches);
        _defaultCurrency = prefs.defaultCurrency;
        _businessNameController.text = prefs.businessName;
        _isLoading = false;
      });
    }
  }

  Future<void> _savePreferences() async {
    if (_selectedNiches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one service category.')),
      );
      return;
    }

    final repo = RepositoryScope.of(context).preferenceRepo;
    final updated = ServicePreference(
      id: 'default',
      niches: _selectedNiches.toList(),
      defaultCurrency: _defaultCurrency,
      businessName: _businessNameController.text.trim().isEmpty
          ? 'Joyce Ava · Independent freelancer'
          : _businessNameController.text.trim(),
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );

    await repo.savePreferences(updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved ${_selectedNiches.length} service categories and $_defaultCurrency currency to local database.'),
          backgroundColor: SoloDeskColors.green,
        ),
      );
      widget.onSaved?.call();
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PERSONALIZATION',
                      style: TextStyle(
                        color: SoloDeskColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Make SoloDesk fit the work you do.',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                        color: SoloDeskColors.ink,
                        letterSpacing: -0.9,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Freelancers do not all work the same way. Select the service categories that apply to you.',
                      style: TextStyle(fontSize: 13, color: SoloDeskColors.muted),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _savePreferences,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('Save preferences'),
              ),
            ],
          ),

          const SizedBox(height: 28),

          // 2-Column Layout
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Card: Settings Form
              Expanded(
                flex: 6,
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
                      const Text(
                        'My services',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: SoloDeskColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Select one or several. The local AI prompts and scope checklists adapt to your choices.',
                        style: TextStyle(fontSize: 12, color: SoloDeskColors.muted),
                      ),
                      const SizedBox(height: 18),

                      // Niche Chips
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: allNiches.map((niche) {
                          final isSelected = _selectedNiches.contains(niche);
                          return FilterChip(
                            label: Text(niche),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedNiches.add(niche);
                                } else {
                                  _selectedNiches.remove(niche);
                                }
                              });
                            },
                            selectedColor: SoloDeskColors.primaryPale,
                            checkmarkColor: SoloDeskColors.primary,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? SoloDeskColors.primary : SoloDeskColors.ink,
                            ),
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: isSelected ? SoloDeskColors.primaryLight : SoloDeskColors.borderLine,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 20),

                      // Default Currency
                      const Text(
                        'Default currency',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: SoloDeskColors.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: SoloDeskColors.borderLine),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _defaultCurrency,
                            isExpanded: true,
                            items: currencies.map((c) {
                              return DropdownMenuItem<String>(
                                value: c['code'],
                                child: Text(c['label']!),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _defaultCurrency = val);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Amounts are tracked as integer minor units with ISO currency codes. Currency conversion is not included.',
                        style: TextStyle(fontSize: 11, color: SoloDeskColors.muted),
                      ),

                      const SizedBox(height: 20),

                      // Business Name Field
                      const Text(
                        'Business / display name',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: SoloDeskColors.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _businessNameController,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Joyce Ava · Independent freelancer',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 24),

              // Right Card: Architectural Explanations
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: SoloDeskColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: SoloDeskColors.borderLine),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How SoloDesk adapts',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: SoloDeskColors.ink,
                        ),
                      ),
                      SizedBox(height: 16),
                      _AdaptItem(
                        icon: Icons.checklist_outlined,
                        title: 'Brief checklists',
                        body: 'Writing briefs check word count and rights. Design briefs check vector deliverables and revision allowances.',
                      ),
                      SizedBox(height: 14),
                      _AdaptItem(
                        icon: Icons.security_outlined,
                        title: 'Scope definitions',
                        body: 'Deliverables, exclusions, and revision rounds are scoped to your active domain.',
                      ),
                      SizedBox(height: 14),
                      _AdaptItem(
                        icon: Icons.lock_outline,
                        title: 'Local-only persistence',
                        body: 'Preferences are saved to SQLite on your Windows device and never transmitted to cloud servers.',
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

class _AdaptItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _AdaptItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: SoloDeskColors.primaryPale,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: SoloDeskColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: SoloDeskColors.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 11,
                  color: SoloDeskColors.muted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
