import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solodesk/models/brief_check_models.dart';
import 'package:solodesk/services/brief_check_client.dart';
import 'package:solodesk/services/brief_check_exceptions.dart';
import 'package:solodesk/services/runtime_token_discovery.dart';

void main() {
  group('NicheAdapter', () {
    test('maps UI niches to backend Zod enums', () {
      expect(NicheAdapter.toBackendNiche('Design & branding'), 'design');
      expect(NicheAdapter.toBackendNiche('Brand identity design'), 'design');
      expect(NicheAdapter.toBackendNiche('Writing & content'), 'writing');
      expect(NicheAdapter.toBackendNiche('Copywriting'), 'writing');
      expect(NicheAdapter.toBackendNiche('Software Engineering'), 'general');
      expect(NicheAdapter.toBackendNiche('Consulting'), 'general');
    });
  });

  group('BriefCheckClient with loopback HttpServer', () {
    HttpServer? server;
    const testToken = 'test-token-abcdef123456';

    setUp(() async {
      RuntimeTokenDiscovery.setToken(testToken);
    });

    tearDown(() async {
      RuntimeTokenDiscovery.clearCache();
      if (server != null) {
        await server!.close(force: true);
        server = null;
      }
    });

    test('successfully parses 200 OK analysis response', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = server!.port;

      server!.listen((HttpRequest request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/brief-check');
        expect(request.headers.value(HttpHeaders.authorizationHeader), 'Bearer $testToken');

        final body = await utf8.decoder.bind(request).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        expect(json['briefText'], 'I need a new logo for my bakery');
        expect(json['niche'], 'design');

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'success': true,
          'requestId': 'req-test-1',
          'data': {
            'statedRequirements': ['Logo for bakery'],
            'assumptions': ['Client needs vector files'],
            'omissions': ['Color palette preference', 'Timeline'],
            'suggestedQuestions': ['What is your preferred color palette?'],
            'starterScopeItems': [
              {
                'title': 'Primary Logo Concept',
                'description': 'Vector logo design in 3 initial directions'
              }
            ]
          }
        }));
        await request.response.close();
      });

      final client = BriefCheckClient(port: serverPort);
      final result = await client.checkBrief(
        briefText: 'I need a new logo for my bakery',
        niche: 'Design & branding',
      );

      expect(result.requestId, 'req-test-1');
      expect(result.statedRequirements, ['Logo for bakery']);
      expect(result.starterScopeItems.length, 1);
      expect(result.starterScopeItems.first.title, 'Primary Logo Concept');
      expect(result.goalSummary, 'Logo for bakery');
    });

    test('throws BriefCheckValidationException on 400 Bad Request', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = server!.port;

      server!.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': {
            'code': 'VALIDATION_ERROR',
            'message': 'Brief cannot exceed 8,000 characters.'
          },
          'requestId': 'req-bad-1'
        }));
        await request.response.close();
      });

      final client = BriefCheckClient(port: serverPort);
      await expectLater(
        client.checkBrief(briefText: 'too long', niche: 'design'),
        throwsA(isA<BriefCheckValidationException>().having(
          (e) => e.message,
          'message',
          contains('8,000 characters'),
        )),
      );
    });

    test('throws BriefCheckConcurrencyException on 429 Busy', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = server!.port;

      server!.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.tooManyRequests;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': {
            'code': 'BUSY',
            'message': 'Local inference engine is currently processing another request.'
          }
        }));
        await request.response.close();
      });

      final client = BriefCheckClient(port: serverPort);
      await expectLater(
        client.checkBrief(briefText: 'test', niche: 'design'),
        throwsA(isA<BriefCheckConcurrencyException>()),
      );
    });

    test('throws BriefCheckModelOfflineException on 503 Unavailable', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = server!.port;

      server!.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': {
            'code': 'MODEL_UNAVAILABLE',
            'message': 'Local Ollama service is not reachable.'
          }
        }));
        await request.response.close();
      });

      final client = BriefCheckClient(port: serverPort);
      await expectLater(
        client.checkBrief(briefText: 'test', niche: 'design'),
        throwsA(isA<BriefCheckModelOfflineException>()),
      );
    });

    test('throws BriefCheckTimeoutException on 504 Timeout', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = server!.port;

      server!.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.gatewayTimeout;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': {
            'code': 'TIMEOUT_EXCEEDED',
            'message': 'Local inference exceeded maximum allowed duration of 75 seconds.'
          }
        }));
        await request.response.close();
      });

      final client = BriefCheckClient(port: serverPort);
      await expectLater(
        client.checkBrief(briefText: 'test', niche: 'design'),
        throwsA(isA<BriefCheckTimeoutException>()),
      );
    });

    test('throws BriefCheckAuthException on 401 Unauthorized', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = server!.port;

      server!.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': {
            'code': 'UNAUTHORIZED',
            'message': 'Invalid authentication token.'
          }
        }));
        await request.response.close();
      });

      final client = BriefCheckClient(port: serverPort);
      await expectLater(
        client.checkBrief(briefText: 'test', niche: 'design'),
        throwsA(isA<BriefCheckAuthException>()),
      );
    });

    test('throws BriefCheckNetworkException when daemon is offline', () async {
      // Port 59999 is unbound
      final client = BriefCheckClient(port: 59999);
      await expectLater(
        client.checkBrief(briefText: 'test', niche: 'design'),
        throwsA(isA<BriefCheckNetworkException>()),
      );
    });
  });
}
