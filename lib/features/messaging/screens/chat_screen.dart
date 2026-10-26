import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/paird_widgets.dart';
import '../../safety/safety_actions.dart';

/// A conversation. New messages are fetched by polling every 5 seconds while
/// the screen is open; older history loads when scrolling up.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversationId, required this.title});
  final int conversationId;
  final String title;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _messages = <ChatMessage>[]; // newest first
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Map<String, dynamic>? _conversation;
  int _otherReadUpTo = 0;
  bool _hasMore = false;
  bool _loadingOlder = false;
  bool _sending = false;
  bool _polling = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _loadOlder();
    });
    _initial();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _fetchNew());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _fetchNew();
  }

  void _apply(Map<String, dynamic> data) {
    _conversation = Map<String, dynamic>.from(data['conversation'] as Map);
    _otherReadUpTo = data['other_read_up_to'] as int? ?? _otherReadUpTo;
  }

  Future<void> _initial() async {
    try {
      final data = await AppScope.read(context).api.messages(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _apply(data);
        _messages
          ..clear()
          ..addAll((data['results'] as List).map((e) => ChatMessage(Map<String, dynamic>.from(e as Map))));
        _hasMore = data['has_more'] == true;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNotFound ? 'This conversation is no longer available.' : e.message);
    }
  }

  Future<void> _fetchNew() async {
    if (_polling || _conversation == null) return;
    _polling = true;
    try {
      final newest = _messages.isEmpty ? 0 : _messages.first.id;
      final data = await AppScope.read(context).api.messages(widget.conversationId, after: newest);
      if (!mounted) return;
      final fresh = (data['results'] as List).map((e) => ChatMessage(Map<String, dynamic>.from(e as Map))).toList();
      setState(() {
        _apply(data);
        final known = _messages.map((m) => m.id).toSet();
        _messages.insertAll(0, fresh.where((m) => !known.contains(m.id)));
      });
    } on ApiException catch (e) {
      if (e.isNotFound && mounted) {
        _poll?.cancel();
        setState(() => _error = 'This conversation is no longer available.');
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore || _messages.isEmpty) return;
    setState(() => _loadingOlder = true);
    try {
      final data = await AppScope.read(context).api.messages(widget.conversationId, before: _messages.last.id);
      if (!mounted) return;
      setState(() {
        _messages.addAll((data['results'] as List).map((e) => ChatMessage(Map<String, dynamic>.from(e as Map))));
        _hasMore = data['has_more'] == true;
      });
    } on ApiException catch (_) {
      // Leave _hasMore as-is so scrolling can retry.
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final message = await AppScope.read(context).api.sendMessage(widget.conversationId, text);
      if (!mounted) return;
      _input.clear();
      setState(() {
        if (!_messages.any((m) => m.id == message.id)) _messages.insert(0, message);
      });
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
      _fetchNew();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _messageMenu(ChatMessage message) async {
    final member = _conversation?['member'] as Map?;
    if (message.isMine || member == null) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.flag_outlined, color: AppColors.error),
          title: const Text('Report this message'),
          onTap: () => Navigator.pop(context, 'report'),
        ),
      ),
    );
    if (choice == 'report' && mounted) {
      final blocked = await reportMember(context,
          userId: member['user_id'] as int, name: widget.title, messageId: message.id);
      if (blocked && mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = _conversation?['member'] as Map?;
    final canSend = _conversation?['can_send'] == true;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            if (member != null) ...[
              MemberPhoto(url: member['photo_url'] as String?, name: widget.title, size: 36, radius: 18),
              const SizedBox(width: 10),
            ],
            Flexible(child: Text(widget.title, overflow: TextOverflow.ellipsis, style: AppTheme.serif(size: 22))),
          ],
        ),
        actions: [
          if (member != null)
            PopupMenuButton<String>(
              color: AppColors.surfaceRaised,
              onSelected: (v) async {
                final navigator = Navigator.of(context);
                final id = member['user_id'] as int;
                final done = v == 'block'
                    ? await blockMember(context, userId: id, name: widget.title)
                    : await reportMember(context, userId: id, name: widget.title);
                if (done) navigator.pop();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'report', child: Text('Report')),
                PopupMenuItem(value: 'block', child: Text('Block')),
              ],
            ),
        ],
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _initial)
          : _conversation == null
              ? const LoadingView()
              : Column(
                  children: [
                    Expanded(
                      child: _messages.isEmpty
                          ? EmptyView(
                              icon: Icons.waving_hand_outlined,
                              title: 'Say hello',
                              message: 'You matched with ${widget.title}. Start the conversation!',
                            )
                          : ListView.builder(
                              controller: _scroll,
                              reverse: true,
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                              itemCount: _messages.length + (_loadingOlder ? 1 : 0),
                              itemBuilder: (context, i) {
                                if (i == _messages.length) {
                                  return const Padding(padding: EdgeInsets.all(12), child: LoadingView());
                                }
                                final m = _messages[i];
                                return _Bubble(
                                  message: m,
                                  read: m.isMine && m.id <= _otherReadUpTo,
                                  onLongPress: () => _messageMenu(m),
                                );
                              },
                            ),
                    ),
                    if (!canSend)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: InfoBanner(
                          (_conversation?['cannot_send_reason'] as String?) ?? 'You can’t send messages here.',
                        ),
                      )
                    else
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _input,
                                  minLines: 1,
                                  maxLines: 5,
                                  maxLength: 2000,
                                  textCapitalization: TextCapitalization.sentences,
                                  decoration: const InputDecoration(hintText: 'Write a message…', counterText: ''),
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton.filled(
                                tooltip: 'Send',
                                style: IconButton.styleFrom(
                                  backgroundColor: AppColors.gold,
                                  foregroundColor: AppColors.background,
                                  minimumSize: const Size(48, 48),
                                ),
                                onPressed: _sending ? null : _send,
                                icon: _sending
                                    ? const SizedBox(
                                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.send_rounded),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.read, required this.onLongPress});
  final ChatMessage message;
  final bool read;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: mine ? AppColors.gold.withValues(alpha: 0.16) : AppColors.surface,
            border: Border.all(color: mine ? AppColors.gold.withValues(alpha: 0.4) : AppColors.border),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(mine ? 14 : 4),
              bottomRight: Radius.circular(mine ? 4 : 14),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SelectableText(message.body, style: AppTheme.sans(height: 1.4)),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(clockTime(message.createdAt), style: AppTheme.sans(size: 10, color: AppColors.textMuted)),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    Icon(read ? Icons.done_all : Icons.done,
                        size: 14,
                        color: read ? AppColors.gold : AppColors.textMuted,
                        semanticLabel: read ? 'Seen' : 'Sent'),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
