import 'dart:convert';
import 'dart:io';

import '../models/service_plan_offer_models.dart';
import 'service_plan_offer_exceptions.dart';
import 'runtime_token_discovery.dart';

class ServicePlanOfferClient {
  final String host;
  final int port;
  final HttpClient? _customHttpClient;
  HttpClientRequest? _activeRequest;

  ServicePlanOfferClient({
    this.host = '127.0.0.1',
    this.port = 3141,
    HttpClient? httpClient,
  }) : _customHttpClient = httpClient;

  Uri get offerDraftUri => Uri.parse('http://$host:$port/v1/offer-draft');

  /// Aborts any in-flight offer draft HTTP request
  void cancelActiveRequest() {
    try {
      _activeRequest?.abort();
    } catch (_) {}
    _activeRequest = null;
  }

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
    return _sendRequestWithRetry(
      clientName: clientName,
      serviceNiche: serviceNiche,
      planTitle: planTitle,
      deliverables: deliverables,
      exclusions: exclusions,
      revisionLimits: revisionLimits,
      priceFormatted: priceFormatted,
      currency: currency,
      cadence: cadence,
      tone: tone,
      isRenewal: isRenewal,
      optionalNotes: optionalNotes,
      isRetry: false,
    );
  }

  Future<ServicePlanOfferResult> _sendRequestWithRetry({
    required String clientName,
    required String serviceNiche,
    required String planTitle,
    required List<String> deliverables,
    required List<String> exclusions,
    required String revisionLimits,
    required String priceFormatted,
    String? currency,
    required String cadence,
    required String tone,
    required bool isRenewal,
    String? optionalNotes,
    required bool isRetry,
  }) async {
    final token = await RuntimeTokenDiscovery.getToken();

    final payload = <String, dynamic>{
      'clientName': clientName,
      'serviceNiche': serviceNiche,
      'planTitle': planTitle,
      'deliverables': deliverables,
      'exclusions': exclusions,
      'revisionLimits': revisionLimits,
      'priceFormatted': priceFormatted,
      'cadence': cadence,
      'tone': tone,
      'isRenewal': isRenewal,
    };

    if (currency != null && currency.length == 3) {
      payload['currency'] = currency;
    }
    if (optionalNotes != null && optionalNotes.trim().isNotEmpty) {
      payload['optionalNotes'] = optionalNotes.trim();
    }

    final client = _customHttpClient ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.postUrl(offerDraftUri)
          .timeout(const Duration(seconds: 15));
      _activeRequest = request;

      request.headers.contentType = ContentType.json;
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }

      final bodyBytes = utf8.encode(jsonEncode(payload));
      request.headers.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      // In-flight inference response timeout bounded to 95 seconds
      final response = await request.close().timeout(const Duration(seconds: 95));
      _activeRequest = null;

      final responseBody = await response.transform(utf8.decoder).join();
      Map<String, dynamic> jsonResponse = {};
      try {
        jsonResponse = jsonDecode(responseBody) as Map<String, dynamic>;
      } catch (_) {
        throw const ServicePlanOfferMalformedOutputException(
          'SoloDesk inference service returned non-JSON response.',
        );
      }

      if (response.statusCode == 200) {
        return ServicePlanOfferResult.fromJson(jsonResponse);
      }

      // Handle 401 Unauthorized with single token refresh retry
      if (response.statusCode == 401) {
        if (!isRetry) {
          RuntimeTokenDiscovery.clearCache();
          return _sendRequestWithRetry(
            clientName: clientName,
            serviceNiche: serviceNiche,
            planTitle: planTitle,
            deliverables: deliverables,
            exclusions: exclusions,
            revisionLimits: revisionLimits,
            priceFormatted: priceFormatted,
            currency: currency,
            cadence: cadence,
            tone: tone,
            isRenewal: isRenewal,
            optionalNotes: optionalNotes,
            isRetry: true,
          );
        }
        throw const ServicePlanOfferAuthException(
          'Authentication failed. Local bearer token is missing or invalid.',
        );
      }

      // Parse error envelope
      final errorMap = jsonResponse['error'] as Map<String, dynamic>? ?? {};
      final errorCode = errorMap['code'] as String? ?? 'UNKNOWN';
      final errorMessage = errorMap['message'] as String? ?? 'An error occurred during proposal generation.';

      if (response.statusCode == 429 || errorCode == 'BUSY') {
        throw ServicePlanOfferConcurrencyException(errorMessage);
      }
      if (response.statusCode == 503 || errorCode == 'MODEL_UNAVAILABLE' || errorCode == 'MODEL_NOT_FOUND') {
        throw ServicePlanOfferModelOfflineException(errorMessage, code: errorCode);
      }
      if (response.statusCode == 504 || errorCode == 'TIMEOUT') {
        throw ServicePlanOfferTimeoutException(errorMessage);
      }
      if (response.statusCode == 400 || errorCode == 'INVALID_INPUT') {
        throw ServicePlanOfferValidationException(errorMessage);
      }
      if (response.statusCode == 502 || errorCode == 'INVALID_OUTPUT') {
        throw ServicePlanOfferMalformedOutputException(errorMessage);
      }

      throw ServicePlanOfferMalformedOutputException(
        'Inference failed (${response.statusCode}): $errorMessage',
      );
    } on SocketException catch (e) {
      _activeRequest = null;
      throw ServicePlanOfferNetworkException(
        'Cannot connect to local inference service at ${offerDraftUri.authority}. '
        'Verify that the SoloDesk service is running. ($e)',
      );
    } on HttpException catch (e) {
      _activeRequest = null;
      throw ServicePlanOfferNetworkException('HTTP error communicating with local service: $e');
    }
  }
}
