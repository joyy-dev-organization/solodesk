import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../db/repository_scope.dart';
import '../domain/invoice_totals_calculator.dart';
import '../models/client.dart';
import '../models/invoice.dart';
import '../models/invoice_reminder_models.dart';
import '../models/money.dart';
import '../models/project.dart';
import '../services/invoice_reminder_client.dart';
import '../services/invoice_reminder_exceptions.dart';
import '../theme/colors.dart';
import '../widgets/stat_card.dart';

class PolitePayScreen extends StatefulWidget {
  final bool isSyntheticDemoActive;
  final InvoiceReminderClient? client;

  const PolitePayScreen({
    super.key,
    this.isSyntheticDemoActive = false,
    this.client,
  });

  @override
  State<PolitePayScreen> createState() => _PolitePayScreenState();
}

class _PolitePayScreenState extends State<PolitePayScreen> {
  late final InvoiceReminderClient _client;

  bool _isLoading = true;
  List<InvoiceWithClient> _invoices = [];
  InvoiceTotalsResult? _totalsResult;
  String _statusFilter = 'all'; // 'all', 'unpaid', 'overdue', 'paid'

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? InvoiceReminderClient();
    WidgetsBinding.instance.addPostFrameCallback((_) => loadData());
  }

  @override
  void didUpdateWidget(covariant PolitePayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSyntheticDemoActive != widget.isSyntheticDemoActive) {
      loadData();
    }
  }

  Future<void> loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final scope = RepositoryScope.of(context);
      final allInvoices = await scope.invoiceRepo.getInvoices(
        includeSynthetic: widget.isSyntheticDemoActive,
      );
      final filteredInvoices = await scope.invoiceRepo.getInvoicesWithClient(
        statusFilter: _statusFilter,
        referenceDate: DateTime.now(),
        includeSynthetic: widget.isSyntheticDemoActive,
      );

      final totals = InvoiceTotalsCalculator.calculate(allInvoices);

      if (mounted) {
        setState(() {
          _invoices = filteredInvoices;
          _totalsResult = totals;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load invoice data: $e')),
        );
      }
    }
  }

  Future<void> _togglePaidStatus(Invoice invoice) async {
    final scope = RepositoryScope.of(context);
    if (invoice.status == InvoiceStatus.paid) {
      await scope.invoiceRepo.markInvoiceUnpaid(invoice.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invoice ${invoice.invoiceNumber} marked as Unpaid.')),
        );
      }
    } else {
      await scope.invoiceRepo.markInvoicePaid(invoice.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invoice ${invoice.invoiceNumber} marked as Paid.')),
        );
      }
    }
    await loadData();
  }

  Future<void> _deleteInvoice(Invoice invoice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Invoice'),
        content: Text('Are you sure you want to delete invoice ${invoice.invoiceNumber}? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: SoloDeskColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final scope = RepositoryScope.of(context);
      await scope.invoiceRepo.deleteInvoice(invoice.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invoice ${invoice.invoiceNumber} deleted.')),
        );
      }
      await loadData();
    }
  }

  Future<void> _showCreateInvoiceDialog() async {
    final scope = RepositoryScope.of(context);
    final clients = await scope.clientRepo.getClients(
      includeSynthetic: widget.isSyntheticDemoActive,
    );
    final projects = await scope.projectRepo.getProjects(
      includeSynthetic: widget.isSyntheticDemoActive,
    );
    final prefs = await scope.preferenceRepo.getPreferences();

    if (!mounted) return;

    if (clients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one client in Overview before creating an invoice.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => _CreateInvoiceDialog(
        clients: clients,
        projects: projects,
        defaultCurrency: prefs.defaultCurrency,
        isSynthetic: widget.isSyntheticDemoActive,
        onCreated: () => loadData(),
      ),
    );
  }

  void _showReminderModal(InvoiceWithClient item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReminderDraftModal(
        item: item,
        client: _client,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SoloDeskColors.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Header Section
                  _buildHeader(),
                  const SizedBox(height: 20),

                  // 2. SoloDesk Boundary Policy Banner
                  _buildBoundaryBanner(),
                  const SizedBox(height: 24),

                  // 3. Multi-Currency Accounting Totals
                  _buildMultiCurrencyTotals(),
                  const SizedBox(height: 28),

                  // 4. Filter Bar & Controls
                  _buildFilterBar(),
                  const SizedBox(height: 16),

                  // 5. Invoices List
                  _buildInvoicesList(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'PolitePay: Invoices & Multi-Currency Accounting',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: SoloDeskColors.ink,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Track client payments with exact minor-unit arithmetic and draft polite, tone-calibrated payment reminders.',
                style: TextStyle(
                  fontSize: 13,
                  color: SoloDeskColors.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: _isLoading ? null : loadData,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                foregroundColor: SoloDeskColors.ink,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _showCreateInvoiceDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create Invoice'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SoloDeskColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBoundaryBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: SoloDeskColors.primaryPale,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SoloDeskColors.primaryLight.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: const [
          Icon(Icons.shield_outlined, color: SoloDeskColors.primary, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'SoloDesk Boundary Policy: SoloDesk never processes payments, connects to payment gateways, or sends messages automatically. All invoice records and reminder drafts are strictly for your local tracking and review.',
              style: TextStyle(
                fontSize: 12,
                color: SoloDeskColors.ink,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiCurrencyTotals() {
    final totals = _totalsResult?.totalsByCurrency ?? {};

    if (totals.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: SoloDeskColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SoloDeskColors.borderLine),
        ),
        child: const Center(
          child: Text(
            'No invoices recorded yet. Create an invoice or enable synthetic demo data in the top bar.',
            style: TextStyle(fontSize: 13, color: SoloDeskColors.muted),
          ),
        ),
      );
    }

    final currencyEntries = totals.entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (currencyEntries.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: const [
                Icon(Icons.pie_chart_outline_rounded, size: 16, color: SoloDeskColors.muted),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Strictly multi-currency: Balances are calculated independently per currency with zero cross-currency summing.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: SoloDeskColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        for (final entry in currencyEntries) ...[
          if (currencyEntries.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Text(
                '${entry.key} Currency Totals',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: SoloDeskColors.ink,
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'TOTAL OUTSTANDING (${entry.key})',
                  value: entry.value.totalOutstanding.formatted,
                  note: '${entry.value.unpaidCount} unpaid ${entry.value.unpaidCount == 1 ? "invoice" : "invoices"}',
                  icon: Icons.pending_actions_rounded,
                  iconColor: SoloDeskColors.amber,
                  iconBgColor: SoloDeskColors.amberBg,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StatCard(
                  label: 'OVERDUE (${entry.key})',
                  value: entry.value.totalOverdue.formatted,
                  note: '${entry.value.overdueCount} overdue ${entry.value.overdueCount == 1 ? "invoice" : "invoices"}',
                  icon: Icons.warning_amber_rounded,
                  iconColor: entry.value.overdueCount > 0 ? SoloDeskColors.red : SoloDeskColors.muted,
                  iconBgColor: entry.value.overdueCount > 0 ? SoloDeskColors.redBg : SoloDeskColors.background,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StatCard(
                  label: 'COLLECTED (${entry.key})',
                  value: entry.value.totalPaid.formatted,
                  note: '${entry.value.paidCount} paid ${entry.value.paidCount == 1 ? "invoice" : "invoices"}',
                  icon: Icons.check_circle_outline_rounded,
                  iconColor: SoloDeskColors.green,
                  iconBgColor: SoloDeskColors.greenBg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildFilterBar() {
    final totals = _totalsResult;
    final totalCount = totals?.totalInvoicesCount ?? 0;
    final unpaidCount = totals?.totalUnpaidCount ?? 0;
    final overdueCount = totals?.totalOverdueCount ?? 0;
    final paidCount = totals?.totalPaidCount ?? 0;

    return Row(
      children: [
        _buildFilterChip('all', 'All ($totalCount)'),
        const SizedBox(width: 8),
        _buildFilterChip('unpaid', 'Unpaid ($unpaidCount)'),
        const SizedBox(width: 8),
        _buildFilterChip('overdue', 'Overdue ($overdueCount)'),
        const SizedBox(width: 8),
        _buildFilterChip('paid', 'Paid ($paidCount)'),
      ],
    );
  }

  Widget _buildFilterChip(String filterKey, String label) {
    final isSelected = _statusFilter == filterKey;
    return InkWell(
      onTap: () {
        if (_statusFilter != filterKey) {
          setState(() => _statusFilter = filterKey);
          loadData();
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? SoloDeskColors.primary : SoloDeskColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? SoloDeskColors.primary : SoloDeskColors.borderLine,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : SoloDeskColors.ink,
          ),
        ),
      ),
    );
  }

  Widget _buildInvoicesList() {
    if (_invoices.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: SoloDeskColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SoloDeskColors.borderLine),
        ),
        child: Column(
          children: const [
            Icon(Icons.receipt_long_outlined, size: 48, color: SoloDeskColors.muted),
            SizedBox(height: 12),
            Text(
              'No invoices found for this filter.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SoloDeskColors.ink),
            ),
            SizedBox(height: 4),
            Text(
              'Create a new invoice or adjust your filter selection.',
              style: TextStyle(fontSize: 13, color: SoloDeskColors.muted),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();

    return Column(
      children: [
        for (final item in _invoices) ...[
          _buildInvoiceCard(item, now),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildInvoiceCard(InvoiceWithClient item, DateTime now) {
    final inv = item.invoice;
    final displayStatus = inv.displayStatusAt(now);
    final isOverdue = inv.isOverdueAt(now);
    final daysOverdue = inv.daysOverdueAt(now);

    Color badgeBg;
    Color badgeText;
    String badgeLabel;

    switch (displayStatus) {
      case InvoiceDisplayStatus.paid:
        badgeBg = SoloDeskColors.greenBg;
        badgeText = SoloDeskColors.green;
        badgeLabel = 'PAID';
        break;
      case InvoiceDisplayStatus.overdue:
        badgeBg = SoloDeskColors.redBg;
        badgeText = SoloDeskColors.red;
        badgeLabel = 'OVERDUE ($daysOverdue ${daysOverdue == 1 ? "day" : "days"})';
        break;
      case InvoiceDisplayStatus.dueToday:
        badgeBg = SoloDeskColors.amberBg;
        badgeText = SoloDeskColors.amber;
        badgeLabel = 'DUE TODAY';
        break;
      case InvoiceDisplayStatus.upcoming:
        badgeBg = SoloDeskColors.blueBg;
        badgeText = SoloDeskColors.blue;
        badgeLabel = 'UPCOMING';
        break;
      default:
        badgeBg = SoloDeskColors.background;
        badgeText = SoloDeskColors.muted;
        badgeLabel = inv.status.name.toUpperCase();
        break;
    }

    final dueDateStr =
        '${inv.dueDate.year}-${inv.dueDate.month.toString().padLeft(2, '0')}-${inv.dueDate.day.toString().padLeft(2, '0')}';
    final issueDateStr =
        '${inv.issueDate.year}-${inv.issueDate.month.toString().padLeft(2, '0')}-${inv.issueDate.day.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(20),
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
              CircleAvatar(
                radius: 18,
                backgroundColor: SoloDeskColors.primaryPale,
                child: Text(
                  item.clientInitials,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: SoloDeskColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          item.clientName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: SoloDeskColors.ink,
                          ),
                        ),
                        if (item.projectName != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '· ${item.projectName}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: SoloDeskColors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      inv.invoiceNumber,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: SoloDeskColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: badgeText,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: SoloDeskColors.borderLine),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AMOUNT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: SoloDeskColors.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    inv.amount.formatted,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: SoloDeskColors.ink,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ISSUE DATE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: SoloDeskColors.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    issueDateStr,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SoloDeskColors.ink,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DUE DATE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: SoloDeskColors.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dueDateStr,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isOverdue ? SoloDeskColors.red : SoloDeskColors.ink,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (inv.status != InvoiceStatus.paid)
                    OutlinedButton.icon(
                      onPressed: () => _showReminderModal(item),
                      icon: const Icon(Icons.mode_comment_outlined, size: 16),
                      label: const Text('Draft Reminder'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SoloDeskColors.primary,
                        side: const BorderSide(color: SoloDeskColors.primary),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (inv.status == InvoiceStatus.paid)
                    OutlinedButton.icon(
                      onPressed: () => _togglePaidStatus(inv),
                      icon: const Icon(Icons.undo_rounded, size: 16),
                      label: const Text('Mark Unpaid'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SoloDeskColors.muted,
                        side: const BorderSide(color: SoloDeskColors.borderLine),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: () => _togglePaidStatus(inv),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Mark Paid'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SoloDeskColors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _deleteInvoice(inv),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: SoloDeskColors.muted,
                    tooltip: 'Delete Invoice',
                  ),
                ],
              ),
            ],
          ),
          if (inv.notes != null && inv.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Note: ${inv.notes}',
              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: SoloDeskColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// CREATE INVOICE DIALOG
// ============================================================================

class _CreateInvoiceDialog extends StatefulWidget {
  final List<Client> clients;
  final List<Project> projects;
  final String defaultCurrency;
  final bool isSynthetic;
  final VoidCallback onCreated;

  const _CreateInvoiceDialog({
    required this.clients,
    required this.projects,
    this.defaultCurrency = 'USD',
    required this.isSynthetic,
    required this.onCreated,
  });

  @override
  State<_CreateInvoiceDialog> createState() => _CreateInvoiceDialogState();
}

class _CreateInvoiceDialogState extends State<_CreateInvoiceDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _selectedClientId;
  String? _selectedProjectId;
  late final TextEditingController _invoiceNumberController;
  final TextEditingController _amountController = TextEditingController(text: '1500.00');
  final TextEditingController _notesController = TextEditingController();
  late String _selectedCurrency;
  final DateTime _issueDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 14));

  static const List<String> supportedCurrencies = [
    'USD', 'EUR', 'GBP', 'NGN', 'KES', 'GHS', 'ZAR', 'CAD', 'AUD',
  ];

  @override
  void initState() {
    super.initState();
    _selectedClientId = widget.clients.first.id;
    final prefCurr = widget.defaultCurrency.trim().toUpperCase();
    _selectedCurrency = prefCurr.isNotEmpty ? prefCurr : 'USD';
    final randomSuffix = (100 + (DateTime.now().millisecondsSinceEpoch % 900)).toString();
    _invoiceNumberController = TextEditingController(text: 'INV-${DateTime.now().year}-$randomSuffix');
  }

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  List<Project> get _clientProjects {
    return widget.projects.where((p) => p.clientId == _selectedClientId).toList();
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _saveInvoice() async {
    if (!_formKey.currentState!.validate()) return;

    final minorUnits = Money.decimalStringToMinorUnits(_amountController.text.trim());
    if (minorUnits <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice amount must be greater than zero.')),
      );
      return;
    }

    final invoice = Invoice(
      id: const Uuid().v4(),
      clientId: _selectedClientId,
      projectId: _selectedProjectId,
      invoiceNumber: _invoiceNumberController.text.trim(),
      amount: Money(minorUnits: minorUnits, currency: _selectedCurrency),
      issueDate: Invoice.toCalendarDate(_issueDate),
      dueDate: Invoice.toCalendarDate(_dueDate),
      status: InvoiceStatus.unpaid,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      isSynthetic: widget.isSynthetic,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final scope = RepositoryScope.of(context);
    await scope.invoiceRepo.createInvoice(invoice);

    if (mounted) {
      Navigator.pop(context);
      widget.onCreated();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invoice ${invoice.invoiceNumber} created successfully!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientProjects = _clientProjects;

    return AlertDialog(
      title: const Text('Create New Invoice'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedClientId,
                  decoration: const InputDecoration(labelText: 'Client *'),
                  items: widget.clients
                      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.displayName)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedClientId = val;
                        _selectedProjectId = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                if (clientProjects.isNotEmpty) ...[
                  DropdownButtonFormField<String?>(
                    key: ValueKey(_selectedClientId),
                    initialValue: _selectedProjectId,
                    decoration: const InputDecoration(labelText: 'Associated Project (Optional)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None / General')),
                      ...clientProjects.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))),
                    ],
                    onChanged: (val) => setState(() => _selectedProjectId = val),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _invoiceNumberController,
                  decoration: const InputDecoration(labelText: 'Invoice Number *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _amountController,
                        decoration: const InputDecoration(
                          labelText: 'Amount (Major units) *',
                          hintText: '1500.00',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final text = v.trim();
                          final d = double.tryParse(text);
                          if (d == null || d <= 0) return 'Must be > 0';
                          if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) {
                            return 'Max 2 decimal places';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedCurrency,
                        decoration: const InputDecoration(labelText: 'Currency *'),
                        items: {...supportedCurrencies, _selectedCurrency}
                            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedCurrency = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickDueDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Due Date *',
                            suffixIcon: Icon(Icons.calendar_today, size: 18),
                          ),
                          child: Text(
                            '${_dueDate.year}-${_dueDate.month.toString().padLeft(2, '0')}-${_dueDate.day.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (Optional)',
                    hintText: 'e.g. Net-14 payment terms',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: SoloDeskColors.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: _saveInvoice,
          child: const Text('Create Invoice'),
        ),
      ],
    );
  }
}

// ============================================================================
// REMINDER DRAFT MODAL / DRAWER
// ============================================================================

class _ReminderDraftModal extends StatefulWidget {
  final InvoiceWithClient item;
  final InvoiceReminderClient client;

  const _ReminderDraftModal({
    required this.item,
    required this.client,
  });

  @override
  State<_ReminderDraftModal> createState() => _ReminderDraftModalState();
}

class _ReminderDraftModalState extends State<_ReminderDraftModal> {
  ReminderTone _selectedTone = ReminderTone.polite;
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _draftController = TextEditingController();

  bool _isGenerating = false;
  String? _errorMessage;
  Timer? _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final days = widget.item.invoice.daysOverdueAt(now);
    if (days == 0) {
      _selectedTone = ReminderTone.gentle;
    } else if (days > 14) {
      _selectedTone = ReminderTone.firm;
    } else {
      _selectedTone = ReminderTone.polite;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_isGenerating) {
      widget.client.cancelActiveRequest();
    }
    _notesController.dispose();
    _draftController.dispose();
    super.dispose();
  }

  void _cancelGeneration() {
    widget.client.cancelActiveRequest();
    _timer?.cancel();
    if (mounted) {
      setState(() {
        _isGenerating = false;
        _errorMessage = 'Generation cancelled by user.';
      });
    }
  }

  Future<void> _generateDraft() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _elapsedSeconds = 0;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });

    final inv = widget.item.invoice;
    final now = DateTime.now();
    final dueDateStr =
        '${inv.dueDate.year}-${inv.dueDate.month.toString().padLeft(2, '0')}-${inv.dueDate.day.toString().padLeft(2, '0')}';
    final days = inv.daysOverdueAt(now);

    try {
      final result = await widget.client.generateReminder(
        invoiceId: inv.id,
        clientName: widget.item.clientName,
        invoiceNumber: inv.invoiceNumber,
        amountFormatted: inv.amount.formatted,
        currency: inv.amount.currency,
        dueDate: dueDateStr,
        daysOverdue: days,
        tone: _selectedTone.toBackendString(),
        optionalNotes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _draftController.text = result.reminderDraft;
        });
        _timer?.cancel();
      }
    } on InvoiceReminderException catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _errorMessage = e.code == 'ABORTED' ? 'Generation cancelled by user.' : e.message;
        });
        _timer?.cancel();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _errorMessage = 'Unexpected client error: $e';
        });
        _timer?.cancel();
      }
    }
  }

  void _copyToClipboard() {
    if (_draftController.text.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: _draftController.text.trim()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payment reminder copied to clipboard! Paste into your email or messaging client.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.item.invoice;
    final now = DateTime.now();
    final isOverdue = inv.isOverdueAt(now);
    final days = inv.daysOverdueAt(now);
    final dueDateStr =
        '${inv.dueDate.year}-${inv.dueDate.month.toString().padLeft(2, '0')}-${inv.dueDate.day.toString().padLeft(2, '0')}';

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(
        color: SoloDeskColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: const [
                    Icon(Icons.mark_email_read_outlined, color: SoloDeskColors.primary, size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Draft Polite Payment Reminder',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: SoloDeskColors.ink,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Verified Facts Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SoloDeskColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SoloDeskColors.borderLine),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('CLIENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: SoloDeskColors.muted)),
                      const SizedBox(height: 2),
                      Text(widget.item.clientName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: SoloDeskColors.ink), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('INVOICE #', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: SoloDeskColors.muted)),
                      const SizedBox(height: 2),
                      Text(inv.invoiceNumber, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: SoloDeskColors.ink), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('EXACT AMOUNT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: SoloDeskColors.muted)),
                      const SizedBox(height: 2),
                      Text(inv.amount.formatted, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: SoloDeskColors.ink), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('DUE DATE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: SoloDeskColors.muted)),
                      const SizedBox(height: 2),
                      Text(
                        '$dueDateStr (${isOverdue ? "$days days overdue" : "Due today / upcoming"})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isOverdue ? SoloDeskColors.red : SoloDeskColors.green,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Tone Selector
          const Text(
            'SELECT REMINDER TONE',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SoloDeskColors.muted, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _buildToneChip(ReminderTone.gentle),
              _buildToneChip(ReminderTone.polite),
              _buildToneChip(ReminderTone.firm),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _selectedTone.description,
            style: const TextStyle(fontSize: 12, color: SoloDeskColors.muted, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),

          // Optional Freelancer Notes
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Optional Context or Note (e.g. "We spoke on Slack yesterday")',
              hintText: 'Add custom notes to guide the draft...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),

          // Generate CTA or Loading
          if (_isGenerating)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SoloDeskColors.primaryPale,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: SoloDeskColors.primary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Drafting payment reminder with local model (${_elapsedSeconds}s)...',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SoloDeskColors.primary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _cancelGeneration,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SoloDeskColors.red,
                      side: const BorderSide(color: SoloDeskColors.redBorder),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _generateDraft,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(_draftController.text.isEmpty ? 'Generate Polite Reminder' : 'Regenerate Reminder Draft'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SoloDeskColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SoloDeskColors.redBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SoloDeskColors.redBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: SoloDeskColors.red, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(fontSize: 12, color: SoloDeskColors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Drafted Text Area
          Expanded(
            child: TextField(
              controller: _draftController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: 'Click "Generate Polite Reminder" to draft a polite, verified payment message...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                fillColor: SoloDeskColors.background,
                filled: true,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Footer Actions & Boundary Disclaimer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'SoloDesk does not send messages. Review and edit before sending to your client.',
                  style: TextStyle(fontSize: 11, color: SoloDeskColors.muted),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _draftController.text.trim().isEmpty ? null : _copyToClipboard,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy to Clipboard'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SoloDeskColors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToneChip(ReminderTone tone) {
    final isSelected = _selectedTone == tone;
    return InkWell(
      onTap: _isGenerating ? null : () => setState(() => _selectedTone = tone),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? tone.color : SoloDeskColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? tone.color : SoloDeskColors.borderLine,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tone.icon,
              size: 16,
              color: isSelected ? Colors.white : SoloDeskColors.muted,
            ),
            const SizedBox(width: 6),
            Text(
              tone.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : SoloDeskColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
