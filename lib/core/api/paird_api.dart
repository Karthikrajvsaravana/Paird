import '../models/models.dart';
import 'api_client.dart';

/// Typed endpoints of the Paird API (backend/*/urls.py).
class PairdApi {
  PairdApi(this.client);
  final ApiClient client;

  AppOptions? _options;

  Map<String, dynamic> _map(dynamic value) => Map<String, dynamic>.from(value as Map);
  List<Map<String, dynamic>> _list(dynamic value) =>
      (value as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  // Options ------------------------------------------------------------------
  Future<AppOptions> options({bool refresh = false}) async {
    if (_options != null && !refresh) return _options!;
    _options = AppOptions(_map(await client.get('/options/')));
    return _options!;
  }

  // Account ------------------------------------------------------------------
  Future<Account> me() async => Account(_map(await client.get('/auth/me/')));
  Future<Account> updateName(String fullName) async =>
      Account(_map(await client.patch('/auth/me/', {'full_name': fullName})));
  Future<Map<String, dynamic>> changePassword(String current, String next) async =>
      _map(await client.post('/auth/change-password/', {'current_password': current, 'new_password': next}));
  Future<void> requestPasswordReset(String identifier) =>
      client.postPublic('/auth/password-reset/', {'identifier': identifier});
  Future<void> confirmPasswordReset(String identifier, String code, String newPassword) => client.postPublic(
        '/auth/password-reset/confirm/',
        {'identifier': identifier, 'code': code, 'new_password': newPassword},
      );
  Future<Map<String, dynamic>> settings() async => _map(await client.get('/settings/'));
  Future<Map<String, dynamic>> updateSettings(Map<String, dynamic> body) async =>
      _map(await client.patch('/settings/', body));
  Future<Account> deactivate(String password) async =>
      Account(_map(await client.post('/account/deactivate/', {'password': password})));
  Future<Account> reactivate() async => Account(_map(await client.post('/account/reactivate/')));
  Future<void> deleteAccount(String password) => client.post('/account/delete/', {'password': password});

  // Profile ------------------------------------------------------------------
  Future<Map<String, dynamic>> myProfile() async => _map(await client.get('/profile/me/'));
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> changes) async =>
      _map(await client.patch('/profile/me/', changes));
  Future<Map<String, dynamic>> publishProfile() async => _map(await client.post('/profile/me/publish/'));
  Future<Map<String, dynamic>> preferences() async => _map(await client.get('/preferences/'));
  Future<Map<String, dynamic>> updatePreferences(Map<String, dynamic> changes) async =>
      _map(await client.patch('/preferences/', changes));
  Future<Map<String, dynamic>> uploadPhoto(List<int> bytes, String filename) async =>
      _map(await client.upload('/photos/', field: 'image', bytes: bytes, filename: filename));
  Future<void> deletePhoto(int id) => client.delete('/photos/$id/');
  Future<void> makePrimaryPhoto(int id) => client.patch('/photos/$id/', {'is_primary': true});
  Future<Map<String, dynamic>> member(int userId) async => _map(await client.get('/members/$userId/'));

  // Dashboard & discovery ------------------------------------------------------
  Future<Map<String, dynamic>> dashboard() async => _map(await client.get('/dashboard/'));

  Future<Paged<MemberCard>> discover({int page = 1, Map<String, dynamic> filters = const {}}) async {
    final data = _map(await client.get('/discover/', query: {'page': page, 'page_size': 20, ...filters}));
    return Paged(
      items: _list(data['results']).map(MemberCard.new).toList(),
      count: data['count'] as int? ?? 0,
      hasNext: data['has_next'] == true,
    );
  }

  // Interests & matches --------------------------------------------------------
  Future<Paged<Interest>> interests({required String direction, String status = 'pending', int page = 1}) async {
    final data = _map(await client.get('/interests/', query: {'direction': direction, 'status': status, 'page': page}));
    return Paged(
      items: _list(data['results']).map(Interest.new).toList(),
      count: data['count'] as int? ?? 0,
      hasNext: data['has_next'] == true,
    );
  }

  Future<Map<String, dynamic>> sendInterest(int userId, {String note = ''}) async =>
      _map(await client.post('/interests/', {'receiver_id': userId, if (note.isNotEmpty) 'note': note}));
  Future<Map<String, dynamic>> interestAction(int interestId, String action) async =>
      _map(await client.post('/interests/$interestId/$action/'));

  Future<Paged<MatchItem>> matches({int page = 1}) async {
    final data = _map(await client.get('/matches/', query: {'page': page}));
    return Paged(
      items: _list(data['results']).map(MatchItem.new).toList(),
      count: data['count'] as int? ?? 0,
      hasNext: data['has_next'] == true,
    );
  }

  Future<void> endMatch(int matchId) => client.post('/matches/$matchId/end/');

  // Messaging ------------------------------------------------------------------
  Future<List<ConversationSummary>> conversations() async =>
      _list(_map(await client.get('/conversations/'))['results']).map(ConversationSummary.new).toList();

  Future<Map<String, dynamic>> messages(int conversationId, {int? before, int? after}) async => _map(
        await client.get('/conversations/$conversationId/messages/', query: {'before': before, 'after': after}),
      );

  Future<ChatMessage> sendMessage(int conversationId, String body) async =>
      ChatMessage(_map(await client.post('/conversations/$conversationId/messages/', {'body': body})));

  // Safety -------------------------------------------------------------------
  Future<void> block(int userId) => client.post('/blocks/', {'user_id': userId});
  Future<void> unblock(int userId) => client.delete('/blocks/$userId/');
  Future<List<Map<String, dynamic>>> blocks() async => _list(await client.get('/blocks/'));
  Future<List<ChoiceOption>> reportReasons() async => _list(await client.get('/reports/reasons/'))
      .map((e) => ChoiceOption(e['value'] as String, e['label'] as String))
      .toList();
  Future<void> report(int userId, String reason, {String details = '', int? messageId, bool block = false}) =>
      client.post('/reports/', {
        'user_id': userId,
        'reason': reason,
        'details': details,
        'message_id': ?messageId,
        'block': block,
      });

  // Notifications, verification, subscription -----------------------------------
  Future<Map<String, dynamic>> notifications() async => _map(await client.get('/notifications/'));
  Future<void> markNotificationsRead() => client.post('/notifications/read-all/');
  Future<Map<String, dynamic>> verification() async => _map(await client.get('/verification/'));
  Future<Map<String, dynamic>> submitVerification(List<int> bytes, String filename) async =>
      _map(await client.upload('/verification/', field: 'selfie', bytes: bytes, filename: filename));
  Future<Map<String, dynamic>> subscription() async => _map(await client.get('/subscription/'));
}
