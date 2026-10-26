import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/paird_api.dart';
import '../models/models.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// Owns the signed-in session and the current account summary.
class AuthController extends ChangeNotifier {
  AuthController({required this.api}) {
    api.client.onSessionExpired = _onSessionExpired;
  }

  final PairdApi api;
  ApiClient get _client => api.client;

  AuthStatus _status = AuthStatus.unknown;
  Account? _account;
  String? _notice;
  String? _restoreError;

  AuthStatus get status => _status;
  Account? get account => _account;

  /// One-off message for the sign-in screen (e.g. "session expired").
  String? takeNotice() {
    final value = _notice;
    _notice = null;
    return value;
  }

  /// Set when the session could not be checked because the server was unreachable.
  String? get restoreError => _restoreError;

  /// Called on launch: restore the session from the stored refresh token.
  Future<void> restore() async {
    _restoreError = null;
    try {
      final hasSession = await _client.refreshSession();
      if (!hasSession) {
        _setSignedOut();
        return;
      }
      _account = await api.me();
      _status = AuthStatus.signedIn;
      notifyListeners();
    } on ApiException catch (e) {
      if (e.isNetwork || (e.statusCode ?? 0) >= 500) {
        // Keep the stored session; let the user retry when back online.
        _restoreError = e.message;
        _status = AuthStatus.unknown;
        notifyListeners();
      } else {
        await _client.clearSession();
        _setSignedOut();
      }
    }
  }

  Future<void> signIn(String identifier, String password) async {
    final data = await _client.postPublic('/auth/login/', {'identifier': identifier.trim(), 'password': password});
    await _startSession(data as Map<String, dynamic>);
  }

  Future<void> signUp({required String fullName, required String identifier, required String password}) async {
    final data = await _client.postPublic('/auth/register/', {
      'full_name': fullName.trim(),
      'identifier': identifier.trim(),
      'password': password,
    });
    await _startSession(data as Map<String, dynamic>);
  }

  Future<void> _startSession(Map<String, dynamic> data) async {
    final tokens = Map<String, dynamic>.from(data['tokens'] as Map);
    await _client.setSession(access: tokens['access'] as String, refresh: tokens['refresh'] as String);
    _account = Account(Map<String, dynamic>.from(data['user'] as Map));
    _status = AuthStatus.signedIn;
    notifyListeners();
  }

  /// Re-fetch the account summary (e.g. after onboarding completes).
  Future<void> refreshAccount() async {
    _account = await api.me();
    notifyListeners();
  }

  void updateAccount(Account account) {
    _account = account;
    notifyListeners();
  }

  Future<void> applyNewTokens(Map<String, dynamic> tokens) =>
      _client.setSession(access: tokens['access'] as String, refresh: tokens['refresh'] as String);

  Future<void> signOut({String? notice}) async {
    final refresh = await _client.tokenStore.readRefreshToken();
    if (refresh != null) {
      try {
        await _client.postPublic('/auth/logout/', {'refresh': refresh});
      } catch (_) {
        // Revocation is best-effort; local sign-out always succeeds.
      }
    }
    await _client.clearSession();
    _notice = notice;
    _setSignedOut();
  }

  /// Local sign-out without contacting the server (account already deleted).
  Future<void> forgetSession({String? notice}) async {
    await _client.clearSession();
    _notice = notice;
    _setSignedOut();
  }

  void _onSessionExpired() {
    if (_status != AuthStatus.signedIn) return;
    _client.clearSession();
    _notice = 'Your session has expired. Please sign in again.';
    _setSignedOut();
  }

  void _setSignedOut() {
    _account = null;
    _status = AuthStatus.signedOut;
    notifyListeners();
  }
}
