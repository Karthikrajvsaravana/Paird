import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/auth/validators.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/paird_widgets.dart';
import '../../profile/widgets/privacy_form.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _privacy;
  Map<String, dynamic>? _notifications;
  AppOptions? _options;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = AppScope.read(context).api;
    try {
      final results = await Future.wait([api.settings(), api.options()]);
      final settings = results[0] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _privacy = Map<String, dynamic>.from(settings['privacy'] as Map);
          _notifications = Map<String, dynamic>.from(settings['notifications'] as Map);
          _options = results[1] as AppOptions;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _update(String group, String field, dynamic value) async {
    if (_saving) return;
    final target = group == 'privacy' ? _privacy! : _notifications!;
    final previous = target[field];
    setState(() {
      target[field] = value;
      _saving = true;
    });
    try {
      final result = await AppScope.read(context).api.updateSettings({
        group: {field: value},
      });
      if (mounted) {
        setState(() {
          _privacy = Map<String, dynamic>.from(result['privacy'] as Map);
          _notifications = Map<String, dynamic>.from(result['notifications'] as Map);
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => target[field] = previous);
        showSnack(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deactivateOrReactivate(bool paused) async {
    final scope = AppScope.read(context);
    try {
      if (paused) {
        scope.auth.updateAccount(await scope.api.reactivate());
        if (mounted) showSnack(context, 'Welcome back! Your profile is visible again.');
      } else {
        final password = await passwordDialog(
          context,
          title: 'Deactivate account?',
          message: 'Your profile will be hidden from everyone and you won’t receive new interests or messages. '
              'You can reactivate any time by signing in.',
          confirmLabel: 'Deactivate',
        );
        if (password == null || password.isEmpty) return;
        scope.auth.updateAccount(await scope.api.deactivate(password));
        if (mounted) showSnack(context, 'Your account is deactivated.');
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.fieldError('password') ?? e.message);
    }
  }

  Future<void> _delete() async {
    final scope = AppScope.read(context);
    final password = await passwordDialog(
      context,
      title: 'Delete account permanently?',
      message: 'This deletes your profile, photos, interests, matches and messages. This cannot be undone.',
      confirmLabel: 'Delete forever',
    );
    if (password == null || password.isEmpty) return;
    try {
      await scope.api.deleteAccount(password);
      await scope.auth.forgetSession(notice: 'Your account has been deleted.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.fieldError('password') ?? e.message);
    }
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(text, style: AppTheme.serif(size: 22, color: AppColors.gold)),
      );

  @override
  Widget build(BuildContext context) {
    final account = AppScope.of(context).auth.account;
    final paused = account?.isPaused ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _privacy == null
          ? (_error != null ? ErrorView(message: _error!, onRetry: _load) : const LoadingView())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                _header('Privacy'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: PrivacyForm(
                      values: _privacy!,
                      options: _options!,
                      onChanged: (field, value) => _update('privacy', field, value),
                    ),
                  ),
                ),
                _header('Notifications'),
                Card(
                  child: Column(
                    children: [
                      for (final entry in const {
                        'interests': 'New interests',
                        'matches': 'Matches and accepted interests',
                        'account': 'Account and verification updates',
                      }.entries)
                        SwitchListTile(
                          title: Text(entry.value, style: AppTheme.sans()),
                          value: _notifications![entry.key] == true,
                          onChanged: (v) => _update('notifications', entry.key, v),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          'These control in-app notifications. Unread messages always show as badges. Push notifications are not available yet.',
                          style: AppTheme.sans(size: 12, color: AppColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
                _header('Safety'),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.block, color: AppColors.gold),
                    title: const Text('Blocked members'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _BlockedScreen())),
                  ),
                ),
                _header('Account'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.alternate_email, color: AppColors.gold),
                        title: const Text('Signed in as'),
                        subtitle: Text(account?.identifier ?? ''),
                      ),
                      ListTile(
                        leading: const Icon(Icons.lock_outline, color: AppColors.gold),
                        title: const Text('Change password'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _ChangePasswordScreen())),
                      ),
                      ListTile(
                        leading: Icon(paused ? Icons.play_circle_outline : Icons.pause_circle_outline, color: AppColors.gold),
                        title: Text(paused ? 'Reactivate account' : 'Deactivate account'),
                        subtitle: Text(paused ? 'Make your profile visible again' : 'Hide your profile temporarily'),
                        onTap: () => _deactivateOrReactivate(paused),
                      ),
                      ListTile(
                        leading: const Icon(Icons.logout, color: AppColors.gold),
                        title: const Text('Sign out'),
                        onTap: () => AppScope.read(context).auth.signOut(),
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete_forever_outlined, color: AppColors.error),
                        title: Text('Delete account', style: AppTheme.sans(color: AppColors.error)),
                        onTap: _delete,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _BlockedScreen extends StatefulWidget {
  const _BlockedScreen();

  @override
  State<_BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<_BlockedScreen> {
  late Future<List<Map<String, dynamic>>> _future = AppScope.read(context).api.blocks();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked members')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
          if (snapshot.hasError) return const ErrorView(message: 'Could not load blocked members.');
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const EmptyView(icon: Icons.block, title: 'Nobody blocked', message: 'Members you block appear here.');
          }
          return ListView(
            children: [
              for (final b in items)
                ListTile(
                  title: Text(b['display_name'] as String),
                  trailing: TextButton(
                    onPressed: () async {
                      await AppScope.read(context).api.unblock(b['user_id'] as int);
                      setState(() => _future = AppScope.read(context).api.blocks());
                    },
                    child: const Text('Unblock'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ChangePasswordScreen extends StatefulWidget {
  const _ChangePasswordScreen();

  @override
  State<_ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<_ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final scope = AppScope.read(context);
    try {
      final result = await scope.api.changePassword(_current.text, _next.text);
      await scope.auth.applyNewTokens(Map<String, dynamic>.from(result['tokens'] as Map));
      if (!mounted) return;
      showSnack(context, 'Password changed. Other devices have been signed out.');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.fieldError('current_password') ?? e.fieldError('new_password') ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
            PairdTextField(
              label: 'Current password',
              controller: _current,
              obscure: true,
              autofillHints: const [AutofillHints.password],
              validator: (v) => (v ?? '').isEmpty ? 'Enter your current password' : null,
            ),
            const SizedBox(height: 16),
            PairdTextField(
              label: 'New password',
              controller: _next,
              obscure: true,
              autofillHints: const [AutofillHints.newPassword],
              validator: validateNewPassword,
            ),
            const SizedBox(height: 24),
            GoldButton(label: 'Change password', busy: _busy, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
