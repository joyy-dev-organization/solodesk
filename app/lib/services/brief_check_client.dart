import 'dart:convert';
import 'dart:io';

import '../models/brief_check_models.dart';
import '../models/service_preference.dart';
import 'brief_check_exceptions.dart';
import 'runtime_token_discovery.dart';

class BriefCheckClient {
  final String host;
  final int port;
  final HttpClient? _customHttpClient;

  BriefCheckClient({
    this.host = '127.0.0.1',
    this.port = 3141,
    HttpClient? httpClient,
  }) : _customHttpClient = httpClient;

  Uri get briefCheckUri => Uri.parse('http://$host:$port/api/brief-check');

  /// Executes brief analysis with local Mastra service
  Future<BriefCheckResult> checkBrief({
    required String briefText,
    required String niche,
    ServicePreference? preferences,
  }) async {
    return _sendRequestWithRetry(
      briefText: briefText,
      niche: niche,
      preferences: preferences,
      isRetry: false,
    );
  }

  Future<BriefCheckResult> _sendRequestWithRetry({
    required String briefText,
    required String niche,
    ServicePreference? preferences,
    required bool isRetry,
  }) async {
    final token = await RuntimeTokenDiscovery.getToken();
    final backendNiche = NicheAdapter.toBackendNiche(niche);

    final payload = <String, dynamic>{
      'briefText': briefText,
      'niche': backendNiche,
    };

    if (preferences != null) {
      payload['servicePreferences'] = {
        'defaultCurrency': preferences.defaultCurrency,
        'businessName': preferences.businessName,
      };
    }

    final client = _customHttpClient ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.postUrl(briefCheckUri)
          .timeout(const Duration(seconds: 15));

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
        throw BriefCheckMalformedOutputException(
          'Failed to parse service JSON response: $responseBody',
        );
      }

      if (response.statusCode == HttpStatus.ok) {
        return BriefCheckResult.fromJson(jsonResponse);
      }

      // Handle 401 token refresh retry once
      if (response.statusCode == HttpStatus.unauthorized && !isRetry) {
        RuntimeTokenDiscovery.clearCache();
        final refreshedToken = await RuntimeTokenDiscovery.getToken(forceRefresh: true);
        if (refreshedToken != null && refreshedToken != token) {
          return _sendRequestWithRetry(
            briefText: briefText,
            niche: niche,
            preferences: preferences,
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
          throw BriefCheckAuthException(errorMessage, requestId: requestId);
        case HttpStatus.badRequest:
          throw BriefCheckValidationException(errorMessage, requestId: requestId);
        case HttpStatus.tooManyRequests:
          throw BriefCheckConcurrencyException(errorMessage, requestId: requestId);
        case HttpStatus.serviceUnavailable:
        case HttpStatus.badGateway:
          throw BriefCheckModelOfflineException(errorMessage, requestId: requestId);
        case HttpStatus.gatewayTimeout:
          throw BriefCheckTimeoutException(errorMessage, requestId: requestId);
        case HttpStatus.internalServerError:
          throw BriefCheckMalformedOutputException(errorMessage, requestId: requestId);
        default:
          throw BriefCheckException(
            errorMessage,
            code: errorCode,
            statusCode: response.statusCode,
            requestId: requestId,
          );
      }
    } on SocketException catch (e) {
      throw BriefCheckNetworkException('Cannot reach local service on $host:$port: ${e.message}');
    } on HandshakeException catch (e) {
      throw BriefCheckNetworkException('Connection failed: ${e.message}');
    } on BriefCheckException {
      rethrow;
    } catch (e) {
      if (e is Exception && e.toString().contains('TimeoutException')) {
        throw BriefCheckTimeoutException('Local model analysis timed out after 90 seconds');
      }
      throw BriefCheckException('Unexpected client error: $e');
    } finally {
      if (_customHttpClient == null) {
        client.close();
      }
    }
  }
}
