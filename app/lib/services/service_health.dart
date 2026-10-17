import 'dart:convert';
import 'dart:io';

class ServiceHealthStatus {
  final bool isHealthy;
  final String status;
  final String service;
  final String version;
  final bool loopbackOnly;
  final bool modelReady;
  final String? activeModel;
  final String? errorMessage;

  const ServiceHealthStatus({
    required this.isHealthy,
    required this.status,
    required this.service,
    required this.version,
    required this.loopbackOnly,
    required this.modelReady,
    this.activeModel,
    this.errorMessage,
  });

  factory ServiceHealthStatus.unreachable(String error) {
    return ServiceHealthStatus(
      isHealthy: false,
      status: 'unreachable',
      service: 'solodesk-service',
      version: 'unknown',
      loopbackOnly: true,
      modelReady: false,
      errorMessage: error,
    );
  }

  factory ServiceHealthStatus.fromJson(Map<String, dynamic> json) {
    final ollama = json['ollama'] as Map<String, dynamic>?;
    final isModelReady = ollama?['modelReady'] == true;
    final statusStr = json['status'] as String? ?? 'unknown';

    return ServiceHealthStatus(
      isHealthy: statusStr == 'ok' && isModelReady,
      status: statusStr,
      service: json['service'] as String? ?? 'solodesk-service',
      version: json['version'] as String? ?? '0.1.0',
      loopbackOnly: json['loopbackOnly'] == true,
      modelReady: isModelReady,
      activeModel: json['activeModel'] as String?,
    );
  }
}

class ServiceHealthClient {
  final String host;
  final int port;

  ServiceHealthClient({this.host = '127.0.0.1', this.port = 3141});

  Uri get healthUri => Uri.parse('http://$host:$port/health');

  Future<ServiceHealthStatus> checkHealth() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);

    try {
      final request = await client.getUrl(healthUri);
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        return ServiceHealthStatus.unreachable('HTTP ${response.statusCode}');
      }

      final responseBody = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      return ServiceHealthStatus.fromJson(decoded);
    } catch (e) {
      return ServiceHealthStatus.unreachable(e.toString());
    } finally {
      client.close();
    }
  }
}
