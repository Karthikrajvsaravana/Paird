// Typed views over Paird API payloads. Only fields the app uses are mapped.

DateTime? _date(dynamic value) => value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
int _int(dynamic value) => value is int ? value : int.tryParse('${value ?? 0}') ?? 0;

class Subscription {
  Subscription(this.json);
  final Map<String, dynamic> json;
  String get plan => json['plan'] as String? ?? 'free';
  bool get isPremium => json['is_premium'] == true;
  DateTime? get expiresAt => _date(json['expires_at']);
  int? get dailyInterestLimit => json['daily_interest_limit'] as int?;
}

class Account {
  Account(this.json);
  final Map<String, dynamic> json;

  int get id => _int(json['id']);
  String get fullName => json['full_name'] as String? ?? '';
  String? get email => json['email'] as String?;
  String? get phone => json['phone'] as String?;
  String get identifier => email ?? phone ?? '';
  bool get profileComplete => json['profile_complete'] == true;
  int get onboardingStep => _int(json['onboarding_step']);
  int get profileCompletion => _int(json['profile_completion']);
  bool get isPaused => json['is_paused'] == true;
  String get verificationStatus => json['verification_status'] as String? ?? 'unverified';
  Subscription get subscription => Subscription(Map<String, dynamic>.from(json['subscription'] as Map? ?? {}));
  String get firstName => fullName.trim().isEmpty ? 'there' : fullName.trim().split(RegExp(r'\s+')).first;
}

class Vibe {
  Vibe(this.json);
  final Map<String, dynamic> json;
  int? get score => json['score'] as int?;
  List<VibeCriterion> get breakdown =>
      (json['breakdown'] as List? ?? []).map((e) => VibeCriterion(Map<String, dynamic>.from(e as Map))).toList();
}

class VibeCriterion {
  VibeCriterion(this.json);
  final Map<String, dynamic> json;
  String get label => json['label'] as String? ?? '';
  bool get met => json['met'] == true;
}

class Connection {
  Connection(this.json);
  final Map<String, dynamic> json;
  /// none | interest_sent | interest_received | declined | matched
  String get status => json['status'] as String? ?? 'none';
  int? get interestId => json['interest_id'] as int?;
  int? get matchId => json['match_id'] as int?;
  int? get conversationId => json['conversation_id'] as int?;
  bool get canSendInterest => json['can_send_interest'] == true;
  DateTime? get expiresAt => _date(json['expires_at']);
}

class MemberCard {
  MemberCard(this.json);
  final Map<String, dynamic> json;

  int get userId => _int(json['user_id']);
  String get displayName => json['display_name'] as String? ?? 'Paird member';
  int? get age => json['age'] as int?;
  String get city => json['city'] as String? ?? '';
  String get country => json['country'] as String? ?? '';
  String get occupation => json['occupation'] as String? ?? '';
  String? get photoUrl => json['photo_url'] as String?;
  bool get photosHidden => json['photos_hidden'] == true;
  bool get isVerified => json['is_verified'] == true;
  Vibe? get vibe => json['vibe'] is Map ? Vibe(Map<String, dynamic>.from(json['vibe'] as Map)) : null;
  Connection? get connection =>
      json['connection'] is Map ? Connection(Map<String, dynamic>.from(json['connection'] as Map)) : null;

  String get location => [city, country].where((s) => s.isNotEmpty).join(', ');
  String get headline => [if (age != null) '$age', if (location.isNotEmpty) location].join(' · ');
}

class Interest {
  Interest(this.json);
  final Map<String, dynamic> json;
  int get id => _int(json['id']);
  String get direction => json['direction'] as String? ?? 'received';
  String get status => json['status'] as String? ?? 'pending';
  String get note => json['note'] as String? ?? '';
  DateTime? get createdAt => _date(json['created_at']);
  DateTime? get expiresAt => _date(json['expires_at']);
  MemberCard get member => MemberCard(Map<String, dynamic>.from(json['member'] as Map));
}

class MatchItem {
  MatchItem(this.json);
  final Map<String, dynamic> json;
  int get id => _int(json['id']);
  int? get conversationId => json['conversation_id'] as int?;
  int get unreadCount => _int(json['unread_count']);
  DateTime? get createdAt => _date(json['created_at']);
  MemberCard get member => MemberCard(Map<String, dynamic>.from(json['member'] as Map));
}

class ConversationSummary {
  ConversationSummary(this.json);
  final Map<String, dynamic> json;
  int get id => _int(json['id']);
  int get matchId => _int(json['match_id']);
  bool get isActive => json['is_active'] == true;
  int get unreadCount => _int(json['unread_count']);
  DateTime? get updatedAt => _date(json['updated_at']);
  Map<String, dynamic>? get lastMessage => json['last_message'] as Map<String, dynamic>?;
  MemberCard get member => MemberCard(Map<String, dynamic>.from(json['member'] as Map));
}

class ChatMessage {
  ChatMessage(this.json);
  final Map<String, dynamic> json;
  int get id => _int(json['id']);
  String get body => json['body'] as String? ?? '';
  bool get isMine => json['is_mine'] == true;
  bool? get isRead => json['is_read'] as bool?;
  DateTime? get createdAt => _date(json['created_at']);
}

class Paged<T> {
  Paged({required this.items, required this.count, required this.hasNext});
  final List<T> items;
  final int count;
  final bool hasNext;
}

/// Choice sets served by /options/ so the app and backend never disagree.
class ChoiceOption {
  const ChoiceOption(this.value, this.label);
  final String value;
  final String label;
}

class AppOptions {
  AppOptions(this.json);
  final Map<String, dynamic> json;

  List<ChoiceOption> choices(String name) => (json['choices']?[name] as List? ?? [])
      .map((e) => ChoiceOption(e['value'] as String, e['label'] as String))
      .toList();

  String label(String name, String? value) {
    if (value == null || value.isEmpty) return '';
    for (final option in choices(name)) {
      if (option.value == value) return option.label;
    }
    return value;
  }

  int get minAge => _int(json['min_age']);
  int get photoMaxCount => _int(json['photo_max_count']);
  int get photoMaxBytes => _int(json['photo_max_bytes']);
  int get interestExpiryDays => _int(json['interest_expiry_days']);
  int get messageMaxLength => _int(json['message_max_length']);
}

String timeAgo(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${time.day}/${time.month}/${time.year}';
}

String clockTime(DateTime? time) {
  if (time == null) return '';
  final h = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m ${time.hour < 12 ? 'AM' : 'PM'}';
}

String timeLeft(DateTime? until) {
  if (until == null) return '';
  final diff = until.difference(DateTime.now());
  if (diff.isNegative) return 'expired';
  if (diff.inDays >= 1) return '${diff.inDays}d left';
  if (diff.inHours >= 1) return '${diff.inHours}h left';
  return '${diff.inMinutes}m left';
}
