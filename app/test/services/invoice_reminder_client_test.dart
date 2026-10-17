import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solodesk/models/invoice_reminder_models.dart';
import 'package:solodesk/services/invoice_reminder_client.dart';
import 'package:solodesk/services/invoice_reminder_exceptions.dart';
import 'package:solodesk/services/runtime_token_discovery.dart';

void main() {
  group('ReminderTone', () {
    test('maps raw strings to standard enum values', () {
      expect(ReminderTone.fromString('gentle'), ReminderTone.gentle);
      expect(ReminderTone.fromString('GENTLE'), ReminderTone.gentle);
      expect(ReminderTone.fromString('friendly'), ReminderTone.gentle);
      expect(ReminderTone.fromString('soft'), ReminderTone.gentle);
      expect(ReminderTone.fromString('firm'), ReminderTone.firm);
      expect(ReminderTone.fromString('urgent'), ReminderTone.firm);
      expect(ReminderTone.fromString('escalated'), ReminderTone.firm);
      expect(ReminderTone.fromString('polite'), ReminderTone.polite);
      expect(ReminderTone.fromString('standard'), ReminderTone.polite);
      expect(ReminderTone.fromString('anything_else'), ReminderTone.polite);
    });

    test('exposes labels, colors, and backend strings', () {
      expect(ReminderTone.gentle.label, 'Gentle');
      expect(ReminderTone.polite.label, 'Polite');
      expect(ReminderTone.firm.label, 'Firm');

      expect(ReminderTone.gentle.toBackendString(), 'gentle');
      expect(ReminderTone.polite.toBackendString(), 'polite');
      expect(ReminderTone.firm.toBackendString(), 'firm');
    });
  });

  group('InvoiceReminderClient with loopback HttpServer', () {
    HttpServer? server;
    const testToken = 'polite-pay-test-token-67890';

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

    test('parses 200 OK InvoiceReminder response with verified facts and tone', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server!.port;

      server!.listen((HttpRequest request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/invoice-reminder');
        expect(request.headers.value(HttpHeaders.authorizationHeader), 'Bearer $testToken');

        final body = await utf8.decoder.bind(request).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        expect(json['clientName'], 'Acme Corp');
        expect(json['invoiceNumber'], 'INV-2026-001');
        expect(json['amountFormatted'], '\$1,500.00');
        expect(json['currency'], 'USD');
        expect(json['dueDate'], '2026-10-15');
        expect(json['daysOverdue'], 2);
        expect(json['tone'], 'polite');

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'requestId': 'req-reminder-1',
          'data': {
            'reminderDraft': 'Hi Acme Corp team, just checking in regarding invoice INV-2026-001 for \$1,500.00, which was due on 2026-10-15. Please let us know if you need another copy.',
            'summary': 'Standard polite follow-up for 2 days overdue invoice INV-2026-001.',
            'toneUsed': 'polite'
          }
        }));
        await request.response.close();
      });

      final client = InvoiceReminderClient(port: port);
      final result = await client.generateReminder(
        invoiceId: 'inv-1',
        clientName: 'Acme Corp',
        invoiceNumber: 'INV-2026-001',
        amountFormatted: '\$1,500.00',
        currency: 'USD',
        dueDate: '2026-10-15',
        daysOverdue: 2,
        tone: 'polite',
      );

      expect(result.requestId, 'req-reminder-1');
      expect(result.reminderDraft, contains('INV-2026-001'));
      expect(result.reminderDraft, contains('\$1,500.00'));
      expect(result.toneUsed, ReminderTone.polite);
      expect(result.summary, contains('INV-2026-001'));
    });

    test('throws InvoiceReminderValidationException on 400 Bad Request', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server!.port;

      server!.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': {'code': 'INVALID_INPUT', 'message': 'clientName cannot be empty'},
          'requestId': 'err-1'
        }));
        await request.response.close();
      });

      final client = InvoiceReminderClient(port: port);
      await expectLater(
        client.generateReminder(
          invoiceId: 'inv-1',
          clientName: '',
          invoiceNumber: 'INV-1',
          amountFormatted: '\$100.00',
          currency: 'USD',
          dueDate: '2026-10-15',
          daysOverdue: 0,
        ),
        throwsA(isA<InvoiceReminderValidationException>().having(
          (e) => e.message,
          'message',
          contains('cannot be empty'),
        )),
      );
    });

    test('throws InvoiceReminderConcurrencyException on 429 Too Many Requests', () async {
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

      final client = InvoiceReminderClient(port: port);
      await expectLater(
        client.generateReminder(
          invoiceId: 'inv-1',
          clientName: 'Acme',
          invoiceNumber: 'INV-1',
          amountFormatted: '\$100.00',
          currency: 'USD',
          dueDate: '2026-10-15',
          daysOverdue: 0,
        ),
        throwsA(isA<InvoiceReminderConcurrencyException>()),
      );
    });

    test('throws InvoiceReminderModelOfflineException on 503 Service Unavailable', () async {
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

      final client = InvoiceReminderClient(port: port);
      await expectLater(
        client.generateReminder(
          invoiceId: 'inv-1',
          clientName: 'Acme',
          invoiceNumber: 'INV-1',
          amountFormatted: '\$100.00',
          currency: 'USD',
          dueDate: '2026-10-15',
          daysOverdue: 0,
        ),
        throwsA(isA<InvoiceReminderModelOfflineException>()),
      );
    });

    test('throws InvoiceReminderTimeoutException on 504 Timeout', () async {
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

      final client = InvoiceReminderClient(port: port);
      await expectLater(
        client.generateReminder(
          invoiceId: 'inv-1',
          clientName: 'Acme',
          invoiceNumber: 'INV-1',
          amountFormatted: '\$100.00',
          currency: 'USD',
          dueDate: '2026-10-15',
          daysOverdue: 0,
        ),
        throwsA(isA<InvoiceReminderTimeoutException>()),
      );
    });

    test('throws InvoiceReminderAuthException on 401 Unauthorized', () async {
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

      final client = InvoiceReminderClient(port: port);
      await expectLater(
        client.generateReminder(
          invoiceId: 'inv-1',
          clientName: 'Acme',
          invoiceNumber: 'INV-1',
          amountFormatted: '\$100.00',
          currency: 'USD',
          dueDate: '2026-10-15',
          daysOverdue: 0,
        ),
        throwsA(isA<InvoiceReminderAuthException>()),
      );
    });

    test('throws InvoiceReminderNetworkException when daemon is offline', () async {
      final client = InvoiceReminderClient(port: 59997);
      await expectLater(
        client.generateReminder(
          invoiceId: 'inv-1',
          clientName: 'Acme',
          invoiceNumber: 'INV-1',
          amountFormatted: '\$100.00',
          currency: 'USD',
          dueDate: '2026-10-15',
          daysOverdue: 0,
        ),
        throwsA(isA<InvoiceReminderNetworkException>()),
      );
    });
  });
}
