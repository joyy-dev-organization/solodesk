/// Typed exceptions for ScopeCheck client operations.
class ScopeCheckException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;
  final String? requestId;

  ScopeCheckException(
    this.message, {
    this.code,
    this.statusCode,
    this.requestId,
  });

  @override
  String toString() => 'ScopeCheckException($code): $message';
}

class ScopeCheckAuthException extends ScopeCheckException {
  ScopeCheckAuthException(super.message, {super.requestId})
      : super(code: 'UNAUTHORIZED', statusCode: 401);
}

class ScopeCheckValidationException extends ScopeCheckException {
  ScopeCheckValidationException(super.message, {super.requestId})
      : super(code: 'VALIDATION_ERROR', statusCode: 400);
}

class ScopeCheckConcurrencyException extends ScopeCheckException {
  ScopeCheckConcurrencyException(super.message, {super.requestId})
      : super(code: 'CONCURRENCY_LOCK', statusCode: 429);
}

class ScopeCheckModelOfflineException extends ScopeCheckException {
  ScopeCheckModelOfflineException(super.message, {super.requestId})
      : super(code: 'MODEL_OFFLINE', statusCode: 503);
}

class ScopeCheckTimeoutException extends ScopeCheckException {
  ScopeCheckTimeoutException(super.message, {super.requestId})
      : super(code: 'TIMEOUT_EXCEEDED', statusCode: 504);
}

class ScopeCheckMalformedOutputException extends ScopeCheckException {
  ScopeCheckMalformedOutputException(super.message, {super.requestId})
      : super(code: 'MALFORMED_OUTPUT', statusCode: 500);
}

class ScopeCheckNetworkException extends ScopeCheckException {
  ScopeCheckNetworkException(super.message)
      : super(code: 'NETWORK_ERROR');
}
