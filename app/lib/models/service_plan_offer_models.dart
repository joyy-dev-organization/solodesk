enum OfferTone {
  collaborative,
  professional,
  valueFocused;

  static OfferTone fromString(String val) {
    final lower = val.toLowerCase().trim();
    if (lower.contains('profess') || lower.contains('formal') || lower.contains('direct')) {
      return OfferTone.professional;
    }
    if (lower.contains('value') || lower.contains('roi') || lower.contains('growth') || lower.contains('impact')) {
      return OfferTone.valueFocused;
    }
    return OfferTone.collaborative;
  }

  String toBackendString() {
    switch (this) {
      case OfferTone.collaborative:
        return 'collaborative';
      case OfferTone.professional:
        return 'professional';
      case OfferTone.valueFocused:
        return 'value_focused';
    }
  }

  String get displayName {
    switch (this) {
      case OfferTone.collaborative:
        return 'Collaborative & warm';
      case OfferTone.professional:
        return 'Direct & professional';
      case OfferTone.valueFocused:
        return 'Value & growth focused';
    }
  }
}

class ServicePlanOfferResult {
  final String requestId;
  final String offerText;
  final String deliverablesSummary;
  final String termsSummary;
  final bool pricePreserved;
  final bool cadencePreserved;
  final bool revisionLimitsPreserved;

  const ServicePlanOfferResult({
    required this.requestId,
    required this.offerText,
    required this.deliverablesSummary,
    required this.termsSummary,
    required this.pricePreserved,
    required this.cadencePreserved,
    required this.revisionLimitsPreserved,
  });

  factory ServicePlanOfferResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    final reqId = (json['requestId'] as String?) ?? (data['requestId'] as String?) ?? '';
    final offer = (data['offerText'] as String?) ?? (data['draft'] as String?) ?? (data['proposalDraft'] as String?) ?? '';
    final deliv = (data['deliverablesSummary'] as String?) ?? '';
    final terms = (data['termsSummary'] as String?) ?? '';
    final fact = data['factPreservation'] as Map<String, dynamic>? ?? {};

    return ServicePlanOfferResult(
      requestId: reqId,
      offerText: offer,
      deliverablesSummary: deliv,
      termsSummary: terms,
      pricePreserved: (fact['pricePreserved'] as bool?) ?? true,
      cadencePreserved: (fact['cadencePreserved'] as bool?) ?? true,
      revisionLimitsPreserved: (fact['revisionLimitsPreserved'] as bool?) ?? true,
    );
  }
}
