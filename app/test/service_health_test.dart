import 'package:flutter_test/flutter_test.dart';
import 'package:solodesk/services/service_health.dart';

void main() {
  group('ServiceHealthStatus', () {
    test('parses ok response correctly', () {
      final json = {
        'status': 'ok',
        'service': 'solodesk-service',
        'version': '0.1.0',
        'loopbackOnly': true,
        'ollama': {
          'available': true,
          'modelReady': true,
        },
        'activeModel': 'qwen3:4b',
      };

      final status = ServiceHealthStatus.fromJson(json);
      expect(status.isHealthy, isTrue);
      expect(status.modelReady, isTrue);
      expect(status.loopbackOnly, isTrue);
      expect(status.activeModel, equals('qwen3:4b'));
    });

    test('creates unreachable status when service is stopped', () {
      final status = ServiceHealthStatus.unreachable('Connection refused');
      expect(status.isHealthy, isFalse);
      expect(status.status, equals('unreachable'));
      expect(status.errorMessage, equals('Connection refused'));
    });
  });
}
