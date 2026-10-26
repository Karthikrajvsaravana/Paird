import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/paird_widgets.dart';
import '../../messaging/screens/chat_screen.dart';
import '../../safety/safety_actions.dart';

/// Another member's profile (`GET /members/<id>/`), already filtered by the
/// server according to their privacy settings. Pops with `true` if the
/// connection changed so lists can refresh.
class MemberProfileScreen extends StatefulWidget {
  const MemberProfileScreen({super.key, required this.userId, this.preview});
  final int userId;
  final MemberCard? preview;

  @override
  State<MemberProfileScreen> createState() => _MemberProfileScreenState();
}

class _MemberProfileScreenState extends State<MemberProfileScreen> {
  Map<String, dynamic>? _data;
  AppOptions? _options;
  String? _error;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = AppScope.read(context).api;
    try {
      final results = await Future.wait([api.member(widget.userId), api.options()]);
      if (!mounted) return;
      setState(() {
        _data = results[0] as Map<String, dynamic>;
        _options = results[1] as AppOptions;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNotFound ? 'This profile is no longer available.' : e.message);
    }
  }

  /// Viewing your own profile ("Preview my profile"): no connection actions.
  bool get _isSelf => _data != null && _data!['connection'] == null;

  Connection get _connection => Connection(Map<String, dynamic>.from(_data!['connection'] as Map));
  String get _name => _data?['display_name'] as String? ?? widget.preview?.displayName ?? 'Member';

  Future<void> _act(Future<Map<String, dynamic>?> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await action();
      _changed = true;
      if (!mounted) return;
      showSnack(context, success);
      final match = result?['match'];
      await _load();
      if (match is Map && match['conversation_id'] != null && mounted) {
        showSnack(context, "It's a match! You can now message $_name.");
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendInterest() async {
    final note = await showDialog<String>(
      context: context,
      builder: (context) => _NoteDialog(name: _name),
    );
    if (note == null || !mounted) return;
    final api = AppScope.read(context).api;
    await _act(() => api.sendInterest(widget.userId, note: note), 'Interest sent.');
  }

  List<Widget> _actions() {
    if (_isSelf) {
      return [
        Text('This is how other members see your profile.',
            textAlign: TextAlign.center, style: AppTheme.sans(color: AppColors.textSecondary)),
      ];
    }
    final api = AppScope.read(context).api;
    final c = _connection;
    switch (c.status) {
      case 'matched':
        return [
          GoldButton(
            label: 'Message',
            icon: Icons.chat_bubble_outline,
            onPressed: c.conversationId == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ChatScreen(conversationId: c.conversationId!, title: _name)),
                    ),
          ),
        ];
      case 'interest_received':
        return [
          Text('$_name sent you an interest${c.expiresAt != null ? ' · ${timeLeft(c.expiresAt)} to respond' : ''}',
              textAlign: TextAlign.center, style: AppTheme.sans(color: AppColors.gold)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _act(() => api.interestAction(c.interestId!, 'decline'), 'Interest declined.'),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GoldButton(
                  label: 'Accept',
                  busy: _busy,
                  onPressed: () => _act(() => api.interestAction(c.interestId!, 'accept'), "It's a match!"),
                ),
              ),
            ],
          ),
        ];
      case 'interest_sent':
        return [
          Text('Interest sent${c.expiresAt != null ? ' · expires in ${timeLeft(c.expiresAt).replaceAll(' left', '')}' : ''}',
              textAlign: TextAlign.center, style: AppTheme.sans(color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _busy ? null : () => _act(() => api.interestAction(c.interestId!, 'withdraw'), 'Interest withdrawn.'),
            child: const Text('Withdraw interest'),
          ),
        ];
      case 'declined':
        return [
          Text('$_name declined your interest.', textAlign: TextAlign.center, style: AppTheme.sans(color: AppColors.textSecondary)),
        ];
      default:
        return [GoldButton(label: 'Send interest', icon: Icons.favorite_border, busy: _busy, onPressed: _sendInterest)];
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_name),
          actions: [
            if (_data != null && !_isSelf)
              PopupMenuButton<String>(
                tooltip: 'More',
                color: AppColors.surfaceRaised,
                onSelected: (value) async {
                  final navigator = Navigator.of(context);
                  final api = AppScope.read(context).api;
                  if (value == 'report') {
                    final blocked = await reportMember(context, userId: widget.userId, name: _name);
                    if (blocked) navigator.pop(true);
                  } else if (value == 'block') {
                    if (await blockMember(context, userId: widget.userId, name: _name)) navigator.pop(true);
                  } else if (value == 'end' && _connection.matchId != null) {
                    if (!context.mounted) return;
                    final ok = await confirmDialog(context,
                        title: 'End match with $_name?',
                        message: 'You will no longer be able to message each other.',
                        confirmLabel: 'End match',
                        destructive: true);
                    if (ok) {
                      await _act(() async {
                        await api.endMatch(_connection.matchId!);
                        return null;
                      }, 'Match ended.');
                    }
                  }
                },
                itemBuilder: (_) => [
                  if (_connection.status == 'matched') const PopupMenuItem(value: 'end', child: Text('End match')),
                  const PopupMenuItem(value: 'report', child: Text('Report')),
                  const PopupMenuItem(value: 'block', child: Text('Block')),
                ],
              ),
          ],
        ),
        body: _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : _data == null
                ? const LoadingView()
                : _profile(),
        bottomNavigationBar: _data == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: _actions()),
                ),
              ),
      ),
    );
  }

  Widget _profile() {
    final d = _data!;
    final o = _options!;
    final photos = (d['photos'] as List).cast<Map>();
    final vibe = d['vibe'] is Map ? Vibe(Map<String, dynamic>.from(d['vibe'] as Map)) : null;
    String label(String field, [String? choices]) => o.label(choices ?? field, d[field] as String?);
    final location = [d['city'], d['state'], d['country']].where((s) => s != null && s.toString().isNotEmpty).join(', ');
    final lifestyle = d['lifestyle'] as Map?;
    final income = d['income'] as Map?;

    Widget row(String title, String? value) {
      if (value == null || value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 130, child: Text(title, style: AppTheme.sans(size: 13, color: AppColors.textSecondary))),
            Expanded(child: Text(value, style: AppTheme.sans(size: 14))),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: photos.isEmpty
              ? MemberPhoto(url: null, name: _name, size: 400, radius: 20, hidden: d['photos_hidden'] == true)
              : PageView(
                  children: [
                    for (final p in photos) MemberPhoto(url: p['url'] as String, name: _name, size: 400, radius: 20),
                  ],
                ),
        ),
        if (d['photos_hidden'] == true)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${_name.split(' ').first} shares photos with matches only.',
                textAlign: TextAlign.center, style: AppTheme.sans(size: 12, color: AppColors.textSecondary)),
          )
        else if (photos.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Swipe for ${photos.length - 1} more',
                textAlign: TextAlign.center, style: AppTheme.sans(size: 12, color: AppColors.textMuted)),
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            Flexible(child: Text('$_name${d['age'] != null ? ', ${d['age']}' : ''}', style: AppTheme.serif(size: 32))),
            if (d['is_verified'] == true) ...[const SizedBox(width: 8), const VerifiedBadge(size: 22)],
          ],
        ),
        if (location.isNotEmpty) Text(location, style: AppTheme.sans(color: AppColors.textSecondary)),
        if (d['last_active_at'] != null)
          Text('Active ${timeAgo(DateTime.tryParse(d['last_active_at'] as String)?.toLocal())}',
              style: AppTheme.sans(size: 12, color: AppColors.textMuted)),
        const SizedBox(height: 14),
        if (vibe?.score != null)
          SectionCard(
            title: 'Vibe Score ${vibe!.score}%',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How many of your partner preferences this profile meets. It is not a prediction of compatibility.',
                  style: AppTheme.sans(size: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in vibe.breakdown)
                      Chip(
                        avatar: Icon(c.met ? Icons.check : Icons.close,
                            size: 16, color: c.met ? AppColors.success : AppColors.textMuted),
                        label: Text(c.label),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if ((d['about_me'] as String? ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(title: 'About', child: Text(d['about_me'] as String, style: AppTheme.sans(height: 1.5))),
        ],
        const SizedBox(height: 12),
        SectionCard(
          title: 'Details',
          child: Column(
            children: [
              row('Height', d['height_cm'] != null ? '${d['height_cm']} cm' : null),
              row('Marital status', label('marital_status')),
              row('Children', d['has_children'] == null ? null : (d['has_children'] == true ? 'Has children' : 'No children')),
              row('Religion', label('religion')),
              row('Community', d['community'] as String?),
              row('Mother tongue', d['mother_tongue'] as String?),
              row('Relocation', label('open_to_relocate')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Education & career',
          child: Column(
            children: [
              row('Education', label('education_level')),
              row('Field', d['education_field'] as String?),
              row('Occupation', d['occupation'] as String?),
              row('Work', label('employment_type')),
              if (income != null) row('Income', '${income['currency']} ${income['amount']} / year'),
              if (d['income_hidden'] == true && income == null)
                row('Income', 'Visible to ${d['is_match'] == true ? 'nobody' : 'matches only'}'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Family & plans',
          child: Column(
            children: [
              row('Family type', label('family_type')),
              row('Family values', label('family_values')),
              row('About family', d['about_family'] as String?),
              row('Marriage timeline', label('marriage_timeline')),
              row('Children', label('wants_children')),
              row('Living', label('living_arrangement')),
            ],
          ),
        ),
        if (lifestyle != null) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'Lifestyle',
            child: Column(
              children: [
                row('Diet', o.label('diet', lifestyle['diet'] as String?)),
                row('Smoking', o.label('smoking', lifestyle['smoking'] as String?)),
                row('Drinking', o.label('drinking', lifestyle['drinking'] as String?)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.name});
  final String name;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Send interest to ${widget.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Add a short note (optional). They have a limited time to respond before it expires.', style: AppTheme.sans(size: 13)),
          const SizedBox(height: 12),
          TextField(controller: _note, maxLength: 300, maxLines: 3, decoration: const InputDecoration(hintText: 'Hi! …')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, _note.text.trim()), child: const Text('Send')),
      ],
    );
  }
}
