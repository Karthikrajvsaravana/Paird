import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/widgets/paird_widgets.dart';
import '../../discover/screens/member_profile_screen.dart';
import '../../premium/screens/premium_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../verification/screens/verification_screen.dart';
import 'edit_profile_screen.dart';
import 'preferences_screen.dart';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  Map<String, dynamic>? _profile;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await AppScope.read(context).api.myProfile();
      if (mounted) {
        setState(() {
          _profile = profile;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
    if (mounted) AppScope.read(context).auth.refreshAccount().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final account = AppScope.of(context).auth.account;
    final p = _profile;
    final photos = (p?['photos'] as List?) ?? const [];
    final primary = photos.isEmpty ? null : (photos.first as Map)['url'] as String?;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: p == null
          ? (_error != null ? ErrorView(message: _error!, onRetry: _load) : const LoadingView())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      MemberPhoto(url: primary, name: account?.fullName ?? '', size: 84, radius: 42),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p['full_name'] as String? ?? '', style: AppTheme.serif(size: 28)),
                            Text(
                              [if (p['age'] != null) '${p['age']}', p['city'], p['country']]
                                  .where((s) => s != null && '$s'.isNotEmpty)
                                  .join(' · '),
                              style: AppTheme.sans(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 6),
                            Text('Profile ${p['completion']}% complete',
                                style: AppTheme.sans(size: 12, color: AppColors.gold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (p['is_paused'] == true) ...[
                    const SizedBox(height: 12),
                    const InfoBanner('Your account is deactivated. Reactivate it in Settings to be visible again.'),
                  ],
                  const SizedBox(height: 20),
                  Card(
                    child: Column(
                      children: [
                        _tile(Icons.edit_outlined, 'Edit profile', 'Details, family, lifestyle, plans',
                            () => _open(const EditProfileScreen())),
                        _tile(Icons.photo_library_outlined, 'Photos', '${photos.length} photo(s)',
                            () => _open(const EditProfileScreen(initialSection: 'photos'))),
                        _tile(Icons.visibility_outlined, 'Preview my profile', 'See what others see',
                            () => _open(MemberProfileScreen(userId: account!.id))),
                        _tile(Icons.tune, 'Partner preferences', 'Who you see and your Vibe Scores',
                            () => _open(const PreferencesScreen())),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Column(
                      children: [
                        _tile(Icons.verified_outlined, 'Verification', switch (account?.verificationStatus) {
                          'verified' => 'Photo verified',
                          'pending' => 'Under review',
                          'rejected' => 'Not approved — try again',
                          _ => 'Not verified',
                        }, () => _open(const VerificationScreen())),
                        _tile(Icons.workspace_premium_outlined, 'Premium',
                            account?.subscription.isPremium == true ? 'Premium active' : 'Free plan',
                            () => _open(const PremiumScreen())),
                        _tile(Icons.settings_outlined, 'Settings & privacy', 'Visibility, notifications, account',
                            () => _open(const SettingsScreen())),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () => AppScope.read(context).auth.signOut(),
                    icon: const Icon(Icons.logout, color: AppColors.gold),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap) => ListTile(
        leading: Icon(icon, color: AppColors.gold),
        title: Text(title, style: AppTheme.sans(weight: FontWeight.w600)),
        subtitle: Text(subtitle, style: AppTheme.sans(size: 12, color: AppColors.textSecondary)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: onTap,
      );
}
