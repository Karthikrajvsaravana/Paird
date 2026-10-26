import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Minimal in-memory stand-in for the Paird auth API, used only by tests.
class FakeBackend {
  final requests = <http.Request>[];
  final users = <String, ({String password, String name})>{};
  final validRefresh = <String>{};
  String? validAccess;
  int refreshCalls = 0;
  int _counter = 0;
  bool offline = false;
  bool profileComplete = false;

  /// Extra JSON responses for signed-in endpoints, keyed by "METHOD /path/".
  final routes = <String, Object? Function(Map<String, dynamic> body)>{};

  MockClient get client => MockClient(_handle);

  Map<String, dynamic> _tokens() {
    _counter++;
    validAccess = 'access-$_counter';
    final refresh = 'refresh-$_counter';
    validRefresh.add(refresh);
    return {'access': validAccess, 'refresh': refresh};
  }

  Map<String, dynamic> _user(String identifier) => {
        'id': 1,
        'full_name': users[identifier]?.name ?? 'Member',
        'email': identifier,
        'phone': null,
        'profile_complete': profileComplete,
        'onboarding_step': 0,
        'profile_completion': 0,
        'is_paused': false,
        'verification_status': 'unverified',
        'subscription': {'plan': 'free', 'is_premium': false},
      };

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  http.Response _error(int status, String message, [Map<String, dynamic>? fields]) => _json({
        'error': {'code': 'error', 'message': message, 'fields': ?fields},
      }, status);

  Future<http.Response> _handle(http.Request request) async {
    if (offline) throw http.ClientException('offline');
    requests.add(request);
    final path = request.url.path.replaceFirst('/api/v1', '');
    final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;
    switch (path) {
      case '/auth/register/':
        final id = (body['identifier'] as String).toLowerCase();
        if (users.containsKey(id)) {
          return _error(400, 'An account with this email address already exists.', {
            'identifier': ['An account with this email address already exists. Try signing in.'],
          });
        }
        users[id] = (password: body['password'] as String, name: body['full_name'] as String);
        return _json({'tokens': _tokens(), 'user': _user(id)}, 201);
      case '/auth/login/':
        final id = (body['identifier'] as String).toLowerCase();
        if (users[id]?.password != body['password']) {
          return _error(400, 'Incorrect email/phone number or password.');
        }
        return _json({'tokens': _tokens(), 'user': _user(id)});
      case '/auth/refresh/':
        refreshCalls++;
        if (!validRefresh.remove(body['refresh'])) return _error(401, 'Token is invalid or expired');
        return _json(_tokens());
      case '/auth/logout/':
        validRefresh.remove(body['refresh']);
        return http.Response('', 204);
      case '/auth/me/':
        if (request.headers['Authorization'] != 'Bearer $validAccess') return _error(401, 'Not authenticated');
        return _json(_user(users.keys.isEmpty ? 'a@b.co' : users.keys.first));
    }
    final route = routes['${request.method} $path'];
    if (route != null) {
      if (request.headers['Authorization'] != 'Bearer $validAccess') return _error(401, 'Not authenticated');
      final result = route(body);
      return result == null ? http.Response('', 204) : _json(result);
    }
    return _error(404, 'Not found.');
  }
}

/// Signed-in, empty-account responses for the main screens.
void addHomeRoutes(FakeBackend backend, {List<Map<String, dynamic>> discover = const []}) {
  backend.profileComplete = true;
  backend.routes.addAll({
    'GET /dashboard/': (_) => {
          'profile': {'is_complete': true, 'completion': 80, 'missing_required': [], 'onboarding_step': 10},
          'counts': {
            'interests_received': 2,
            'interests_sent': 1,
            'matches': 0,
            'unread_messages': 0,
            'unread_notifications': 0,
          },
          'verification_status': 'unverified',
          'subscription': {'plan': 'free', 'is_premium': false},
          'notices': [],
          'recommendations': [],
        },
    'GET /discover/': (_) => {'count': discover.length, 'has_next': false, 'results': discover},
    'GET /options/': (_) => {
          'choices': {},
          'min_age': 18,
          'photo_max_count': 6,
          'photo_max_bytes': 5242880,
          'interest_expiry_days': 7,
          'message_max_length': 2000,
        },
    'GET /matches/': (_) => {'count': 0, 'has_next': false, 'results': []},
    'GET /interests/': (_) => {'count': 0, 'has_next': false, 'results': []},
    'GET /conversations/': (_) => {'count': 0, 'results': []},
    'GET /profile/me/': (_) => {
          'full_name': 'Asha Raman',
          'age': 30,
          'city': 'Chennai',
          'country': 'India',
          'completion': 80,
          'photos': [],
          'is_paused': false,
        },
  });
}
