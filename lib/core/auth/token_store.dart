import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists only the refresh token. Access tokens live in memory.
abstract class TokenStore {
  Future<String?> readRefreshToken();
  Future<void> saveRefreshToken(String token);
  Future<void> clear();
}

/// Encrypted storage (Android Keystore-backed) for the refresh token.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'paird_refresh_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readRefreshToken() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      // Corrupted keystore entry (e.g. after an OS restore): start fresh.
      await clear();
      return null;
    }
  }

  @override
  Future<void> saveRefreshToken(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}

/// In-memory store used by tests.
class MemoryTokenStore implements TokenStore {
  String? token;

  @override
  Future<void> clear() async => token = null;

  @override
  Future<String?> readRefreshToken() async => token;

  @override
  Future<void> saveRefreshToken(String value) async => token = value;
}
