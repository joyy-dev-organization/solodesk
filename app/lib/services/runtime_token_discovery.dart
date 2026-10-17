import 'dart:io';

class RuntimeTokenDiscovery {
  static String? _cachedToken;

  /// Returns the cached token if present, or attempts to discover it from disk/env.
  static Future<String?> getToken({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedToken != null && _cachedToken!.isNotEmpty) {
      return _cachedToken;
    }

    // 1. Environment variable
    final envToken = Platform.environment['SOLODESK_RUNTIME_TOKEN'];
    if (envToken != null && envToken.trim().isNotEmpty) {
      _cachedToken = envToken.trim();
      return _cachedToken;
    }

    // 2. Candidate file locations
    final candidates = <String>[
      // Adjacent service directory (dev mode from app root)
      '${Directory.current.path}/../service/.runtime-token',
      '${Directory.current.path}/service/.runtime-token',
      '${Directory.current.path}/.runtime-token',
    ];

    // Executable directory candidates (packaged Windows desktop release)
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      candidates.add('$exeDir/service/.runtime-token');
      candidates.add('$exeDir/.runtime-token');
      candidates.add('$exeDir/../service/.runtime-token');
    } catch (_) {}

    // Windows AppData paths
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      candidates.add('$appData/com.example.solodesk/.runtime-token');
      candidates.add('$appData/solodesk/.runtime-token');
    }

    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      candidates.add('$localAppData/solodesk/.runtime-token');
    }

    // Check each candidate
    for (final path in candidates) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final content = (await file.readAsString()).trim();
          if (content.isNotEmpty) {
            _cachedToken = content;
            return _cachedToken;
          }
        }
      } catch (_) {
        // Continue searching
      }
    }

    return null;
  }

  /// Clears the cached token so next request re-discovers it (e.g. after 401).
  static void clearCache() {
    _cachedToken = null;
  }

  /// Sets a manual token for testing or explicit configuration.
  static void setToken(String? token) {
    _cachedToken = token?.trim();
  }
}
