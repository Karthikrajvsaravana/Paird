import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/paird_widgets.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = AppScope.read(context).api;
    try {
      final data = await api.notifications();
      if (!mounted) return;
      setState(() {
        _items = (data['results'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _error = null;
      });
      if ((data['unread_count'] as int? ?? 0) > 0) await api.markNotificationsRead();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  IconData _icon(String kind) => switch (kind) {
        'interest_received' => Icons.favorite_border,
        'interest_accepted' || 'new_match' => Icons.favorite,
        'verification_updated' => Icons.verified_outlined,
        _ => Icons.notifications_none,
      };

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: items == null
          ? (_error != null ? ErrorView(message: _error!, onRetry: _load) : const LoadingView())
          : RefreshIndicator(
              onRefresh: _load,
              child: items.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 80),
                      EmptyView(icon: Icons.notifications_none, title: 'All caught up', message: 'New activity will appear here.'),
                    ])
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final n = items[i];
                        final unread = n['read_at'] == null;
                        return ListTile(
                          leading: Icon(_icon(n['kind'] as String), color: AppColors.gold),
                          title: Text(n['title'] as String,
                              style: AppTheme.sans(weight: unread ? FontWeight.w700 : FontWeight.w400)),
                          subtitle: Text(
                            [if ((n['body'] as String? ?? '').isNotEmpty) n['body'], timeAgo(DateTime.tryParse(n['created_at'] as String)?.toLocal())]
                                .join('\n'),
                            style: AppTheme.sans(size: 12, color: AppColors.textSecondary),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
