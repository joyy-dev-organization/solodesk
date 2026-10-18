import 'dart:convert';
import 'dart:io';

import '../models/invoice_reminder_models.dart';
import 'invoice_reminder_exceptions.dart';
import 'runtime_token_discovery.dart';

class InvoiceReminderClient {
  final String host;
  final int port;
  final HttpClient? _customHttpClient;
  HttpClientRequest? _activeRequest;

  InvoiceReminderClient({
    this.host = '127.0.0.1',
    this.port = 3141,
    HttpClient? httpClient,
  }) : _customHttpClient = httpClient;

  Uri get invoiceReminderUri => Uri.parse('http://$host:$port/api/invoice-reminder');

  /// Aborts any in-flight reminder generation HTTP request to free daemon concurrency locks
  void cancelActiveRequest() {
    try {
      _activeRequest?.abort();
    } catch (_) {}
    _activeRequest = null;
  }

  Future<InvoiceReminderResult> generateReminder({
    required String invoiceId,
    required String clientName,
    required String invoiceNumber,
    required String amountFormatted,
    required String currency,
    required String dueDate,
    required int daysOverdue,
    String tone = 'polite',
    String? optionalNotes,
  }) async {
    return _sendRequestWithRetry(
      invoiceId: invoiceId,
      clientName: clientName,
      invoiceNumber: invoiceNumber,
      amountFormatted: amountFormatted,
      currency: currency,
      dueDate: dueDate,
      daysOverdue: daysOverdue,
      tone: tone,
      optionalNotes: optionalNotes,
      isRetry: false,
    );
  }

  Future<InvoiceReminderResult> _sendRequestWithRetry({
    required String invoiceId,
    required String clientName,
    required String invoiceNumber,
    required String amountFormatted,
    required String currency,
    required String dueDate,
    required int daysOverdue,
    required String tone,
    String? optionalNotes,
    required bool isRetry,
  }) async {
    final token = await RuntimeTokenDiscovery.getToken();

    final payload = <String, dynamic>{
      'invoiceId': invoiceId,
      'clientName': clientName,
      'invoiceNumber': invoiceNumber,
      'amountFormatted': amountFormatted,
      'currency': currency,
      'dueDate': dueDate,
      'daysOverdue': daysOverdue,
      'tone': tone,
    };

    if (optionalNotes != null && optionalNotes.trim().isNotEmpty) {
      payload['optionalNotes'] = optionalNotes.trim();
    }

    final client = _customHttpClient ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.postUrl(invoiceReminderUri)
          .timeout(const Duration(seconds: 15));
      _activeRequest = request;

      request.headers.contentType = ContentType.json;
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }

      final bodyBytes = utf8.encode(jsonEncode(payload));
      request.headers.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      // Server inference can take up to 75s; give client 90s total window
      final response = await request.close().timeout(const Duration(seconds: 90));

      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));

      Map<String, dynamic> jsonResponse;
      try {
        jsonResponse = jsonDecode(responseBody) as Map<String, dynamic>;
      } catch (e) {
        throw InvoiceReminderMalformedOutputException(
          'Failed to parse service JSON response: $responseBody',
        );
      }

      if (response.statusCode == HttpStatus.ok) {
        return InvoiceReminderResult.fromJson(jsonResponse);
      }

      // Handle 401 token refresh retry once
      if (response.statusCode == HttpStatus.unauthorized && !isRetry) {
        RuntimeTokenDiscovery.clearCache();
        final refreshedToken = await RuntimeTokenDiscovery.getToken(forceRefresh: true);
        if (refreshedToken != null && refreshedToken != token) {
          return _sendRequestWithRetry(
            invoiceId: invoiceId,
            clientName: clientName,
            invoiceNumber: invoiceNumber,
            amountFormatted: amountFormatted,
            currency: currency,
            dueDate: dueDate,
            daysOverdue: daysOverdue,
            tone: tone,
            optionalNotes: optionalNotes,
            isRetry: true,
          );
        }
      }

      // Map error envelope
      final errorMap = jsonResponse['error'] as Map<String, dynamic>? ?? {};
      final errorCode = errorMap['code'] as String? ?? 'UNKNOWN_ERROR';
      final errorMessage = errorMap['message'] as String? ?? 'Error: HTTP ${response.statusCode}';
      final requestId = (jsonResponse['requestId'] ?? errorMap['requestId']) as String?;

      switch (response.statusCode) {
        case HttpStatus.unauthorized:
          throw InvoiceReminderAuthException(errorMessage, requestId: requestId);
        case HttpStatus.badRequest:
          throw InvoiceReminderValidationException(errorMessage, requestId: requestId);
        case HttpStatus.tooManyRequests:
          throw InvoiceReminderConcurrencyException(errorMessage, requestId: requestId);
        case HttpStatus.serviceUnavailable:
        case HttpStatus.badGateway:
          throw InvoiceReminderModelOfflineException(errorMessage, requestId: requestId);
        case HttpStatus.gatewayTimeout:
          throw InvoiceReminderTimeoutException(errorMessage, requestId: requestId);
        case HttpStatus.internalServerError:
          throw InvoiceReminderMalformedOutputException(errorMessage, requestId: requestId);
        default:
          throw InvoiceReminderException(
            errorMessage,
            code: errorCode,
            statusCode: response.statusCode,
            requestId: requestId,
          );
      }
    } on HttpException catch (e) {
      if (e.message.contains('aborted') || e.message.contains('Connection closed')) {
        throw InvoiceReminderException('Request aborted by user', code: 'ABORTED');
      }
      throw InvoiceReminderNetworkException('HTTP error: ${e.message}');
    } on SocketException catch (e) {
      throw InvoiceReminderNetworkException('Cannot reach local service on $host:$port: ${e.message}');
    } on HandshakeException catch (e) {
      throw InvoiceReminderNetworkException('Loopback connection failed: ${e.message}');
    } on InvoiceReminderException {
      rethrow;
    } catch (e) {
      if (e is Exception && e.toString().contains('TimeoutException')) {
        throw InvoiceReminderTimeoutException('Local model inference timed out after 90 seconds');
      }
      throw InvoiceReminderException('Unexpected client error: $e');
    } finally {
      _activeRequest = null;
      if (_customHttpClient == null) {
        client.close();
      }
    }
  }
}
