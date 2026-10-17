import 'dart:async';
import 'package:flutter/material.dart';
import '../services/service_health.dart';
import '../theme/colors.dart';

class ServiceHealthBadge extends StatefulWidget {
  final ServiceHealthClient healthClient;
  final bool enablePolling;

  const ServiceHealthBadge({
    super.key,
    required this.healthClient,
    this.enablePolling = true,
  });

  @override
  State<ServiceHealthBadge> createState() => _ServiceHealthBadgeState();
}

class _ServiceHealthBadgeState extends State<ServiceHealthBadge> {
  ServiceHealthStatus _status = const ServiceHealthStatus(
    isHealthy: false,
    status: 'checking',
    service: 'solodesk-service',
    version: '0.1.0',
    loopbackOnly: true,
    modelReady: false,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkHealth();
    if (widget.enablePolling) {
      _timer = Timer.periodic(const Duration(seconds: 10), (_) => _checkHealth());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkHealth() async {
    try {
      final res = await widget.healthClient.checkHealth();
      if (mounted) {
        setState(() => _status = res);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = ServiceHealthStatus.unreachable(e.toString()));
      }
    }
  }

  void _showDiagnosticsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Local Service Health Diagnostics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Service: ${_status.service} (v${_status.version})'),
            const SizedBox(height: 6),
            Text('Loopback Binding: ${_status.loopbackOnly ? "127.0.0.1:3141 (Strict)" : "Warning: Not loopback"}'),
            const SizedBox(height: 6),
            Text('Model Status: ${_status.modelReady ? "Ready (${_status.activeModel ?? "qwen3:1.7b"})" : "Not ready"}'),
            if (_status.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                'Diagnostic Note: ${_status.errorMessage}',
                style: const TextStyle(color: SoloDeskColors.red, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'SoloDesk operates local-first. Mastra agent workflows execute on your machine over loopback.',
              style: TextStyle(fontSize: 12, color: SoloDeskColors.muted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _checkHealth();
            },
            child: const Text('Recheck Now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    Color border;
    String label;

    if (_status.isHealthy) {
      bg = SoloDeskColors.greenBg;
      fg = SoloDeskColors.green;
      border = SoloDeskColors.greenBorder;
      label = '● Local AI Ready: ${_status.activeModel ?? "qwen3:1.7b"}';
    } else if (_status.status == 'ok' && !_status.modelReady) {
      bg = SoloDeskColors.amberBg;
      fg = SoloDeskColors.amber;
      border = SoloDeskColors.amberBorder;
      label = '▲ Model Warming';
    } else {
      bg = SoloDeskColors.redBg;
      fg = SoloDeskColors.red;
      border = SoloDeskColors.redBorder;
      label = '✕ Local AI Offline';
    }

    return InkWell(
      onTap: _showDiagnosticsDialog,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
