import 'package:flutter/foundation.dart';

/// Backend location, chosen at build time (never contains secrets).
///
/// * Physical phone (local dev): pass your PC's LAN address, e.g.
///     flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8001/api/v1
/// * Android emulator: the default http://10.0.2.2:8001/api/v1 reaches the PC.
/// * Release builds MUST pass an HTTPS production URL.
class AppConfig {
  AppConfig._();

  static const String _defined = String.fromEnvironment('API_BASE_URL');

  /// Local development default: the Android emulator reaches the host
  /// machine's Django server (port 8001) through 10.0.2.2.
  static String get apiBaseUrl {
    if (_defined.isNotEmpty) return _defined.endsWith('/') ? _defined.substring(0, _defined.length - 1) : _defined;
    if (kReleaseMode) return '';
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8001/api/v1';
    return 'http://127.0.0.1:8001/api/v1';
  }

  static bool get isConfigured => apiBaseUrl.isNotEmpty;

  /// True when no API_BASE_URL was given and the emulator default is in use.
  static bool get usingEmulatorDefault => _defined.isEmpty;

  static const Duration requestTimeout = Duration(seconds: 20);
}
