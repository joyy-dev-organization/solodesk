/// Typed exceptions for BriefCheck client operations.
class BriefCheckException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;
  final String? requestId;

  BriefCheckException(
    this.message, {
    this.code,
    this.statusCode,
    this.requestId,
  });

  @override
  String toString() => 'BriefCheckException($code): $message';
}

class BriefCheckAuthException extends BriefCheckException {
  BriefCheckAuthException(super.message, {super.requestId})
      : super(code: 'UNAUTHORIZED', statusCode: 401);
}

class BriefCheckValidationException extends BriefCheckException {
  BriefCheckValidationException(super.message, {super.requestId})
      : super(code: 'VALIDATION_ERROR', statusCode: 400);
}

class BriefCheckConcurrencyException extends BriefCheckException {
  BriefCheckConcurrencyException(super.message, {super.requestId})
      : super(code: 'CONCURRENCY_LOCK', statusCode: 429);
}

class BriefCheckModelOfflineException extends BriefCheckException {
  BriefCheckModelOfflineException(super.message, {super.requestId})
      : super(code: 'MODEL_OFFLINE', statusCode: 503);
}

class BriefCheckTimeoutException extends BriefCheckException {
  BriefCheckTimeoutException(super.message, {super.requestId})
      : super(code: 'TIMEOUT_EXCEEDED', statusCode: 504);
}

class BriefCheckMalformedOutputException extends BriefCheckException {
  BriefCheckMalformedOutputException(super.message, {super.requestId})
      : super(code: 'MALFORMED_OUTPUT', statusCode: 500);
}

class BriefCheckNetworkException extends BriefCheckException {
  BriefCheckNetworkException(super.message)
      : super(code: 'NETWORK_ERROR');
}
