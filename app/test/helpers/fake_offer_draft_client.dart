import 'dart:async';
import 'package:solodesk/models/service_plan_offer_models.dart';
import 'package:solodesk/services/service_plan_offer_client.dart';

class FakeOfferDraftClient extends ServicePlanOfferClient {
  ServicePlanOfferResult? stubResult;
  Exception? errorToThrow;
  bool cancelCalled = false;
  Completer<ServicePlanOfferResult>? delayedCompleter;

  @override
  void cancelActiveRequest() {
    cancelCalled = true;
    super.cancelActiveRequest();
  }

  @override
  Future<ServicePlanOfferResult> generateOfferDraft({
    required String clientName,
    required String serviceNiche,
    required String planTitle,
    required List<String> deliverables,
    List<String> exclusions = const [],
    required String revisionLimits,
    required String priceFormatted,
    String? currency,
    String cadence = 'monthly',
    String tone = 'collaborative',
    bool isRenewal = false,
    String? optionalNotes,
  }) async {
    if (delayedCompleter != null) {
      return delayedCompleter!.future;
    }
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return stubResult ??
        ServicePlanOfferResult(
          requestId: 'fake-offer-req-1',
          offerText: 'Hi $clientName,\n\nI would love to propose our ongoing $planTitle ($priceFormatted / $cadence).\n\nAgreed deliverables:\n${deliverables.map((d) => '• $d').join('\n')}\n\nRevision limits: $revisionLimits\n\nLooking forward to hearing your thoughts!\n\nBest regards,',
          deliverablesSummary: deliverables.join('; '),
          termsSummary: '$priceFormatted ($cadence); $revisionLimits',
          pricePreserved: true,
          cadencePreserved: true,
          revisionLimitsPreserved: true,
        );
  }
}
