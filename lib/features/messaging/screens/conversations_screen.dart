import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/paird_widgets.dart';
import 'chat_screen.dart';

/// Conversations with matches. Refreshed by polling every 30 seconds while
/// this screen exists (there is no push / websocket delivery yet).
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key, this.onChanged});
  final VoidCallback? onChanged;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<ConversationSummary>? _items;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await AppScope.read(context).api.conversations();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: items == null
          ? (_error != null ? ErrorView(message: _error!, onRetry: _load) : const LoadingView())
          : RefreshIndicator(
              onRefresh: _load,
              child: items.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 80),
                      EmptyView(
                        icon: Icons.chat_bubble_outline,
                        title: 'No conversations yet',
                        message: 'Once you match with someone, you can message them here.',
                      ),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, indent: 84),
                      itemBuilder: (context, i) {
                        final c = items[i];
                        final last = c.lastMessage;
                        final preview = last == null
                            ? 'Say hello 👋'
                            : '${last['is_mine'] == true ? 'You: ' : ''}${last['body']}';
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: MemberPhoto(url: c.member.photoUrl, name: c.member.displayName, hidden: c.member.photosHidden),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(c.member.displayName,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.sans(weight: c.unreadCount > 0 ? FontWeight.w700 : FontWeight.w500)),
                              ),
                              Text(timeAgo(c.updatedAt), style: AppTheme.sans(size: 11, color: AppColors.textMuted)),
                            ],
                          ),
                          subtitle: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.isActive ? preview : 'Match ended',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.sans(
                                    size: 13,
                                    color: c.unreadCount > 0 ? AppColors.textPrimary : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              if (c.unreadCount > 0)
                                Badge(
                                  label: Text('${c.unreadCount}'),
                                  backgroundColor: AppColors.gold,
                                  textColor: AppColors.background,
                                ),
                            ],
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ChatScreen(conversationId: c.id, title: c.member.displayName),
                            ));
                            _load();
                            widget.onChanged?.call();
                          },
                        );
                      },
                    ),
            ),
    );
  }
}
