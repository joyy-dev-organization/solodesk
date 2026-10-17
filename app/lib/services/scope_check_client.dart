import 'dart:convert';
import 'dart:io';

import '../models/scope_check_models.dart';
import '../models/scope_item.dart';
import 'runtime_token_discovery.dart';
import 'scope_check_exceptions.dart';

class ScopeCheckClient {
  final String host;
  final int port;
  final HttpClient? _customHttpClient;

  ScopeCheckClient({
    this.host = '127.0.0.1',
    this.port = 3141,
    HttpClient? httpClient,
  }) : _customHttpClient = httpClient;

  Uri get scopeCheckUri => Uri.parse('http://$host:$port/api/scope-check');

  Future<ScopeCheckResult> checkScope({
    required String requestText,
    required String scopeVersionId,
    required List<ScopeItem> scopeItems,
    String niche = 'general',
  }) async {
    return _sendRequestWithRetry(
      requestText: requestText,
      scopeVersionId: scopeVersionId,
      scopeItems: scopeItems,
      niche: niche,
      isRetry: false,
    );
  }

  Future<ScopeCheckResult> _sendRequestWithRetry({
    required String requestText,
    required String scopeVersionId,
    required List<ScopeItem> scopeItems,
    required String niche,
    required bool isRetry,
  }) async {
    final token = await RuntimeTokenDiscovery.getToken();

    final backendItems = scopeItems.map(ScopeItemAdapter.toBackendItem).toList();

    final payload = <String, dynamic>{
      'requestText': requestText,
      'scopeVersionId': scopeVersionId,
      'scopeItems': backendItems,
      'niche': niche,
    };

    final client = _customHttpClient ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.postUrl(scopeCheckUri)
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
        throw ScopeCheckMalformedOutputException(
          'Failed to parse service JSON response: $responseBody',
        );
      }

      if (response.statusCode == HttpStatus.ok) {
        return ScopeCheckResult.fromJson(jsonResponse);
      }

      // Handle 401 token refresh retry once
      if (response.statusCode == HttpStatus.unauthorized && !isRetry) {
        RuntimeTokenDiscovery.clearCache();
        final refreshedToken = await RuntimeTokenDiscovery.getToken(forceRefresh: true);
        if (refreshedToken != null && refreshedToken != token) {
          return _sendRequestWithRetry(
            requestText: requestText,
            scopeVersionId: scopeVersionId,
            scopeItems: scopeItems,
            niche: niche,
            isRetry: true,
          );
        }
      }

      // Map error envelope
      final errorMap = jsonResponse['error'] as Map<String, dynamic>? ?? {};
      final errorCode = errorMap['code'] as String? ?? 'UNKNOWN_ERROR';
      final errorMessage = errorMap['message'] as String? ?? 'Error: HTTP ${response.statusCode}';
      final requestId = jsonResponse['requestId'] as String?;

      switch (response.statusCode) {
        case HttpStatus.unauthorized:
          throw ScopeCheckAuthException(errorMessage, requestId: requestId);
        case HttpStatus.badRequest:
          throw ScopeCheckValidationException(errorMessage, requestId: requestId);
        case HttpStatus.tooManyRequests:
          throw ScopeCheckConcurrencyException(errorMessage, requestId: requestId);
        case HttpStatus.serviceUnavailable:
        case HttpStatus.badGateway:
          throw ScopeCheckModelOfflineException(errorMessage, requestId: requestId);
        case HttpStatus.gatewayTimeout:
          throw ScopeCheckTimeoutException(errorMessage, requestId: requestId);
        case HttpStatus.internalServerError:
          throw ScopeCheckMalformedOutputException(errorMessage, requestId: requestId);
        default:
          throw ScopeCheckException(
            errorMessage,
            code: errorCode,
            statusCode: response.statusCode,
            requestId: requestId,
          );
      }
    } on SocketException catch (e) {
      throw ScopeCheckNetworkException('Cannot reach local service on $host:$port: ${e.message}');
    } on HandshakeException catch (e) {
      throw ScopeCheckNetworkException('Loopback connection failed: ${e.message}');
    } on ScopeCheckException {
      rethrow;
    } catch (e) {
      if (e is Exception && e.toString().contains('TimeoutException')) {
        throw ScopeCheckTimeoutException('Local model inference timed out after 90 seconds');
      }
      throw ScopeCheckException('Unexpected client error: $e');
    } finally {
      if (_customHttpClient == null) {
        client.close();
      }
    }
  }
}
