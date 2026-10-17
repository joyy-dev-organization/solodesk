/// Typed exceptions for InvoiceReminder client operations.
class InvoiceReminderException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;
  final String? requestId;

  InvoiceReminderException(
    this.message, {
    this.code,
    this.statusCode,
    this.requestId,
  });

  @override
  String toString() => 'InvoiceReminderException($code): $message';
}

class InvoiceReminderAuthException extends InvoiceReminderException {
  InvoiceReminderAuthException(super.message, {super.requestId})
      : super(code: 'UNAUTHORIZED', statusCode: 401);
}

class InvoiceReminderValidationException extends InvoiceReminderException {
  InvoiceReminderValidationException(super.message, {super.requestId})
      : super(code: 'VALIDATION_ERROR', statusCode: 400);
}

class InvoiceReminderConcurrencyException extends InvoiceReminderException {
  InvoiceReminderConcurrencyException(super.message, {super.requestId})
      : super(code: 'CONCURRENCY_LOCK', statusCode: 429);
}

class InvoiceReminderModelOfflineException extends InvoiceReminderException {
  InvoiceReminderModelOfflineException(super.message, {super.requestId})
      : super(code: 'MODEL_OFFLINE', statusCode: 503);
}

class InvoiceReminderTimeoutException extends InvoiceReminderException {
  InvoiceReminderTimeoutException(super.message, {super.requestId})
      : super(code: 'TIMEOUT_EXCEEDED', statusCode: 504);
}

class InvoiceReminderMalformedOutputException extends InvoiceReminderException {
  InvoiceReminderMalformedOutputException(super.message, {super.requestId})
      : super(code: 'MALFORMED_OUTPUT', statusCode: 500);
}

class InvoiceReminderNetworkException extends InvoiceReminderException {
  InvoiceReminderNetworkException(super.message)
      : super(code: 'NETWORK_ERROR');
}
