import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/paird_widgets.dart';
import '../../discover/member_tile.dart';
import '../../notifications/screens/notifications_screen.dart';
import '../../premium/screens/premium_screen.dart';
import '../../profile/screens/edit_profile_screen.dart';
import '../../verification/screens/verification_screen.dart';

/// Home: real counts, notices and recommendations from GET /dashboard/.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final data = await AppScope.read(context).api.dashboard();
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  Widget _stat(String label, int value, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              children: [
                Icon(icon, color: AppColors.gold, size: 20),
                const SizedBox(height: 6),
                Text('$value', style: AppTheme.serif(size: 26)),
                Text(label,
                    textAlign: TextAlign.center,
                    style: AppTheme.sans(size: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = AppScope.of(context).auth.account;
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: Text('Paird', style: AppTheme.serif(size: 30, color: AppColors.gold).copyWith(letterSpacing: 1.5)),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => _open(const NotificationsScreen()),
            icon: Badge(
              isLabelVisible: ((data?['counts']?['unread_notifications'] as int?) ?? 0) > 0,
              label: Text('${data?['counts']?['unread_notifications'] ?? ''}'),
              child: const Icon(Icons.notifications_none),
            ),
          ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _error != null && data == null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: _content(account, data!),
                  ),
                ),
    );
  }

  List<Widget> _content(Account? account, Map<String, dynamic> data) {
    final profile = data['profile'] as Map;
    final counts = data['counts'] as Map;
    final notices = (data['notices'] as List).cast<Map>();
    final recs = (data['recommendations'] as List).map((e) => MemberCard(Map<String, dynamic>.from(e as Map))).toList();
    final completion = profile['completion'] as int? ?? 0;
    final verification = data['verification_status'] as String? ?? 'unverified';
    final premium = (data['subscription'] as Map?)?['is_premium'] == true;

    return [
      Text('Hello, ${account?.firstName ?? 'there'}', style: AppTheme.serif(size: 32, weight: FontWeight.w600)),
      Text('Your next meaningful connection starts here.', style: AppTheme.sans(color: AppColors.textSecondary)),
      const SizedBox(height: 16),
      if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
      if (completion < 100)
        SectionCard(
          title: 'Profile $completion% complete',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: completion / 100, minHeight: 6, backgroundColor: AppColors.border),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _open(const EditProfileScreen()),
                  child: const Text('Complete your profile'),
                ),
              ),
            ],
          ),
        ),
      for (final notice in notices.where((n) => n['kind'] != 'complete_profile'))
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: InkWell(
            onTap: switch (notice['kind']) {
              'verify' || 'verification_rejected' => () => _open(const VerificationScreen()),
              'add_photo' => () => _open(const EditProfileScreen(initialSection: 'photos')),
              'interests_expiring' => () => widget.onNavigate(2),
              _ => null,
            },
            child: InfoBanner(notice['message'] as String),
          ),
        ),
      const SizedBox(height: 14),
      Row(
        children: [
          _stat('Interests\nreceived', counts['interests_received'] as int, Icons.favorite_border, () => widget.onNavigate(2)),
          const SizedBox(width: 8),
          _stat('Interests\nsent', counts['interests_sent'] as int, Icons.send_outlined, () => widget.onNavigate(2)),
          const SizedBox(width: 8),
          _stat('Matches\n', counts['matches'] as int, Icons.people_outline, () => widget.onNavigate(2)),
          const SizedBox(width: 8),
          _stat('Unread\nmessages', counts['unread_messages'] as int, Icons.chat_bubble_outline, () => widget.onNavigate(3)),
        ],
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: Card(
              child: ListTile(
                onTap: () => _open(const VerificationScreen()),
                leading: Icon(verification == 'verified' ? Icons.verified : Icons.verified_outlined,
                    color: verification == 'verified' ? AppColors.success : AppColors.gold),
                title: Text('Verification', style: AppTheme.sans(size: 13, weight: FontWeight.w600)),
                subtitle: Text(
                  switch (verification) {
                    'verified' => 'Photo verified',
                    'pending' => 'Under review',
                    'rejected' => 'Try again',
                    _ => 'Not verified',
                  },
                  style: AppTheme.sans(size: 12, color: AppColors.textSecondary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Card(
              child: ListTile(
                onTap: () => _open(const PremiumScreen()),
                leading: const Icon(Icons.workspace_premium_outlined, color: AppColors.gold),
                title: Text('Plan', style: AppTheme.sans(size: 13, weight: FontWeight.w600)),
                subtitle: Text(premium ? 'Premium' : 'Free',
                    style: AppTheme.sans(size: 12, color: AppColors.textSecondary)),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(child: Text('Recommended for you', style: AppTheme.serif(size: 24))),
          TextButton(onPressed: () => widget.onNavigate(1), child: const Text('See all')),
        ],
      ),
      const SizedBox(height: 6),
      if (recs.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'No recommendations yet. As more members join who match your preferences, they’ll appear here.',
              style: AppTheme.sans(color: AppColors.textSecondary),
            ),
          ),
        )
      else
        for (final member in recs)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: MemberTile(member: member, onChanged: _load)),
    ];
  }
}
