abstract class ServicePlanOfferException implements Exception {
  final String message;
  final String? code;
  final bool retryable;

  const ServicePlanOfferException(this.message, {this.code, this.retryable = false});

  @override
  String toString() => 'ServicePlanOfferException: $message (code: $code, retryable: $retryable)';
}

class ServicePlanOfferNetworkException extends ServicePlanOfferException {
  const ServicePlanOfferNetworkException(super.message)
      : super(code: 'NETWORK_ERROR', retryable: true);
}

class ServicePlanOfferTimeoutException extends ServicePlanOfferException {
  const ServicePlanOfferTimeoutException(super.message)
      : super(code: 'TIMEOUT', retryable: true);
}

class ServicePlanOfferAuthException extends ServicePlanOfferException {
  const ServicePlanOfferAuthException(super.message)
      : super(code: 'UNAUTHORIZED', retryable: false);
}

class ServicePlanOfferConcurrencyException extends ServicePlanOfferException {
  const ServicePlanOfferConcurrencyException(super.message)
      : super(code: 'BUSY', retryable: true);
}

class ServicePlanOfferModelOfflineException extends ServicePlanOfferException {
  const ServicePlanOfferModelOfflineException(super.message, {String? code})
      : super(code: code ?? 'MODEL_UNAVAILABLE', retryable: true);
}

class ServicePlanOfferValidationException extends ServicePlanOfferException {
  const ServicePlanOfferValidationException(super.message)
      : super(code: 'INVALID_INPUT', retryable: false);
}

class ServicePlanOfferMalformedOutputException extends ServicePlanOfferException {
  const ServicePlanOfferMalformedOutputException(super.message)
      : super(code: 'INVALID_OUTPUT', retryable: true);
}
