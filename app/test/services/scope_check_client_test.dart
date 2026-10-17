import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solodesk/models/scope_check_models.dart';
import 'package:solodesk/models/scope_item.dart';
import 'package:solodesk/services/runtime_token_discovery.dart';
import 'package:solodesk/services/scope_check_client.dart';
import 'package:solodesk/services/scope_check_exceptions.dart';

void main() {
  group('ScopeClassification', () {
    test('maps raw strings to semantic classifications', () {
      expect(ScopeClassification.fromString('INCLUDED'), ScopeClassification.included);
      expect(ScopeClassification.fromString('included'), ScopeClassification.included);
      expect(ScopeClassification.fromString('POTENTIALLY_OUTSIDE'), ScopeClassification.potentiallyOutside);
      expect(ScopeClassification.fromString('out_of_scope'), ScopeClassification.potentiallyOutside);
      expect(ScopeClassification.fromString('extra'), ScopeClassification.potentiallyOutside);
      expect(ScopeClassification.fromString('NEEDS_CLARIFICATION'), ScopeClassification.needsClarification);
      expect(ScopeClassification.fromString('ambiguous'), ScopeClassification.needsClarification);
      expect(ScopeClassification.fromString('unknown_value'), ScopeClassification.needsClarification);
    });
  });

  group('ScopeCheckClient with loopback HttpServer', () {
    HttpServer? server;
    const testToken = 'scope-shield-test-token-12345';

    setUp(() {
      RuntimeTokenDiscovery.setToken(testToken);
    });

    tearDown(() async {
      RuntimeTokenDiscovery.clearCache();
      if (server != null) {
        await server!.close(force: true);
        server = null;
      }
    });

    test('parses 200 OK ScopeCheck response with itemized findings and counts', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server!.port;

      server!.listen((HttpRequest request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/scope-check');
        expect(request.headers.value(HttpHeaders.authorizationHeader), 'Bearer $testToken');

        final body = await utf8.decoder.bind(request).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        expect(json['requestText'], contains('5 social media templates'));
        expect(json['scopeVersionId'], 'v-1');

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'requestId': 'req-scope-1',
          'data': {
            'summary': 'Analyzed 2 items: 1 included, 1 out of scope.',
            'findings': [
              {
                'requestExcerpt': '5 social media templates',
                'category': 'out_of_scope',
                'explanation': 'Social media templates are not listed in agreed scope deliverables.',
                'matchedScopeItemId': null,
                'matchedScopeItemDescription': 'No matching scope deliverable found in approved agreement'
              },
              {
                'requestExcerpt': 'minor color adjustment on logo',
                'category': 'included',
                'explanation': 'Covers agreed revision allowance on primary logo.',
                'matchedScopeItemId': 'item-logo-1',
                'matchedScopeItemDescription': 'Primary logo: Vector master files'
              }
            ],
            'replyDraft': 'Thanks for reaching out! The logo adjustment is included. For the social templates, I can provide a separate estimate.'
          }
        }));
        await request.response.close();
      });

      final client = ScopeCheckClient(port: port);
      final result = await client.checkScope(
        requestText: 'Could you do a minor color adjustment on logo and also 5 social media templates?',
        scopeVersionId: 'v-1',
        scopeItems: const [
          ScopeItem(id: 'item-logo-1', scopeVersionId: 'v-1', category: 'included', description: 'Primary logo: Vector master files'),
        ],
      );

      expect(result.requestId, 'req-scope-1');
      expect(result.findings.length, 2);
      expect(result.includedCount, 1);
      expect(result.outsideCount, 1);
      expect(result.clarificationCount, 0);
      expect(result.findings.first.classification, ScopeClassification.potentiallyOutside);
      expect(result.findings.first.matchedScopeItemId, isNull);
      expect(result.findings.first.matchedScopeItemDescription, 'No matching scope deliverable found in approved agreement');
      expect(result.findings[1].matchedScopeItemId, 'item-logo-1');
      expect(result.replyDraft, contains('separate estimate'));
    });

    test('throws ScopeCheckValidationException on 400 Bad Request', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server!.port;

      server!.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': {'code': 'INVALID_INPUT', 'message': 'Request text cannot be empty'},
          'requestId': 'err-1'
        }));
        await request.response.close();
      });

      final client = ScopeCheckClient(port: port);
      await expectLater(
        client.checkScope(requestText: '', scopeVersionId: 'v-1', scopeItems: []),
        throwsA(isA<ScopeCheckValidationException>().having(
          (e) => e.message,
          'message',
          contains('cannot be empty'),
        )),
      );
    });

    test('throws ScopeCheckConcurrencyException on 429 Too Many Requests', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server!.port;

      server!.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.tooManyRequests;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': {'code': 'BUSY', 'message': 'Single concurrency limit active'},
          'requestId': 'err-busy'
        }));
        await request.response.close();
      });

      final client = ScopeCheckClient(port: port);
      await expectLater(
        client.checkScope(requestText: 'test', scopeVersionId: 'v-1', scopeItems: [
          const ScopeItem(id: '1', scopeVersionId: 'v-1', category: 'included', description: 'test')
        ]),
        throwsA(isA<ScopeCheckConcurrencyException>()),
      );
    });

    test('throws ScopeCheckModelOfflineException on 503 Service Unavailable', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server!.port;

      server!.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': {'code': 'MODEL_UNAVAILABLE', 'message': 'Ollama offline'},
          'requestId': 'err-offline'
        }));
        await request.response.close();
      });

      final client = ScopeCheckClient(port: port);
      await expectLater(
        client.checkScope(requestText: 'test', scopeVersionId: 'v-1', scopeItems: [
          const ScopeItem(id: '1', scopeVersionId: 'v-1', category: 'included', description: 'test')
        ]),
        throwsA(isA<ScopeCheckModelOfflineException>()),
      );
    });

    test('throws ScopeCheckTimeoutException on 504 Timeout', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server!.port;

      server!.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.gatewayTimeout;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': {'code': 'TIMEOUT_EXCEEDED', 'message': 'Inference exceeded 75 seconds'},
          'requestId': 'err-timeout'
        }));
        await request.response.close();
      });

      final client = ScopeCheckClient(port: port);
      await expectLater(
        client.checkScope(requestText: 'test', scopeVersionId: 'v-1', scopeItems: [
          const ScopeItem(id: '1', scopeVersionId: 'v-1', category: 'included', description: 'test')
        ]),
        throwsA(isA<ScopeCheckTimeoutException>()),
      );
    });

    test('throws ScopeCheckAuthException on 401 Unauthorized', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server!.port;

      server!.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': {'code': 'UNAUTHORIZED', 'message': 'Invalid token'},
          'requestId': 'err-auth'
        }));
        await request.response.close();
      });

      final client = ScopeCheckClient(port: port);
      await expectLater(
        client.checkScope(requestText: 'test', scopeVersionId: 'v-1', scopeItems: [
          const ScopeItem(id: '1', scopeVersionId: 'v-1', category: 'included', description: 'test')
        ]),
        throwsA(isA<ScopeCheckAuthException>()),
      );
    });

    test('throws ScopeCheckNetworkException when daemon is offline', () async {
      final client = ScopeCheckClient(port: 59998);
      await expectLater(
        client.checkScope(requestText: 'test', scopeVersionId: 'v-1', scopeItems: [
          const ScopeItem(id: '1', scopeVersionId: 'v-1', category: 'included', description: 'test')
        ]),
        throwsA(isA<ScopeCheckNetworkException>()),
      );
    });
  });
}
