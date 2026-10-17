import 'package:solodesk/db/invoice_repository.dart';
import 'package:solodesk/models/client.dart';
import 'package:solodesk/models/invoice.dart';

class FakeInvoiceRepository implements IInvoiceRepository {
  final List<Invoice> invoices = [];
  final Map<String, Client> clients = {};

  @override
  Future<List<Invoice>> getInvoices({
    String? clientId,
    InvoiceStatus? status,
    bool includeSynthetic = true,
  }) async {
    return invoices.where((inv) {
      if (!includeSynthetic && inv.isSynthetic) return false;
      if (clientId != null && inv.clientId != clientId) return false;
      if (status != null && inv.status != status) return false;
      return true;
    }).toList();
  }

  @override
  Future<List<InvoiceWithClient>> getInvoicesWithClient({
    String? clientId,
    String? statusFilter,
    bool includeSynthetic = true,
    DateTime? referenceDate,
  }) async {
    final ref = referenceDate ?? DateTime.now();
    final list = await getInvoices(
      clientId: clientId,
      includeSynthetic: includeSynthetic,
    );

    final filtered = list.where((inv) {
      if (statusFilter == 'paid') return inv.status == InvoiceStatus.paid;
      if (statusFilter == 'unpaid') return inv.status == InvoiceStatus.unpaid;
      if (statusFilter == 'overdue') return inv.isOverdueAt(ref);
      return true;
    }).toList();

    return filtered.map((inv) {
      final client = clients[inv.clientId];
      return InvoiceWithClient(
        invoice: inv,
        clientName: client?.name ?? 'Test Client',
        clientInitials: client?.initials ?? 'TC',
        projectName: inv.projectId != null ? 'Test Project' : null,
      );
    }).toList();
  }

  @override
  Future<Invoice?> getInvoiceById(String id) async {
    try {
      return invoices.firstWhere((inv) => inv.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> createInvoice(Invoice invoice) async {
    invoices.removeWhere((i) => i.id == invoice.id);
    invoices.add(invoice);
  }

  @override
  Future<void> updateInvoice(Invoice invoice) async {
    final idx = invoices.indexWhere((i) => i.id == invoice.id);
    if (idx != -1) {
      invoices[idx] = invoice;
    }
  }

  @override
  Future<void> deleteInvoice(String id) async {
    invoices.removeWhere((i) => i.id == id);
  }

  @override
  Future<void> markInvoicePaid(String id, {DateTime? paidAt}) async {
    final idx = invoices.indexWhere((i) => i.id == id);
    if (idx != -1) {
      invoices[idx] = invoices[idx].copyWith(
        status: InvoiceStatus.paid,
        paidAt: paidAt ?? DateTime.now(),
      );
    }
  }

  @override
  Future<void> markInvoiceUnpaid(String id) async {
    final idx = invoices.indexWhere((i) => i.id == id);
    if (idx != -1) {
      invoices[idx] = invoices[idx].copyWith(
        status: InvoiceStatus.unpaid,
        paidAt: null,
      );
    }
  }
}
