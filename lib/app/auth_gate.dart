import 'package:flutter/material.dart';

import '../core/auth/auth_controller.dart';
import '../core/config/app_config.dart';
import '../features/auth/screens/sign_in_screen.dart';
import '../features/home/screens/home_shell.dart';
import '../features/onboarding/screens/onboarding_screen.dart';
import '../shared/widgets/paird_widgets.dart';
import 'app_scope.dart';
import 'paird_app.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

/// Chooses the root screen from the session state:
/// restoring → splash, signed out → sign in, incomplete profile → onboarding,
/// otherwise → home. Any pushed routes are cleared when the state changes.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AuthController? _auth;
  AuthStatus? _lastStatus;
  bool? _lastComplete;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = AppScope.of(context).auth;
    if (auth != _auth) {
      _auth?.removeListener(_onAuthChanged);
      _auth = auth..addListener(_onAuthChanged);
      _lastStatus = auth.status;
      _lastComplete = auth.account?.profileComplete;
    }
  }

  void _onAuthChanged() {
    final auth = _auth!;
    final complete = auth.account?.profileComplete;
    if (auth.status != _lastStatus || complete != _lastComplete) {
      // Drop screens pushed under the previous state (e.g. Sign up, Settings).
      PairdApp.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
    _lastStatus = auth.status;
    _lastComplete = complete;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = _auth!;
    if (!AppConfig.isConfigured) {
      return const Scaffold(
        body: ErrorView(message: 'This build has no server configured. Rebuild with --dart-define=API_BASE_URL=…'),
      );
    }
    switch (auth.status) {
      case AuthStatus.unknown:
        return _Splash(error: auth.restoreError, onRetry: auth.restore);
      case AuthStatus.signedOut:
        return const SignInScreen(key: ValueKey('sign-in'));
      case AuthStatus.signedIn:
        if (!(auth.account?.profileComplete ?? false)) return const OnboardingScreen();
        return const HomeShell();
    }
  }
}

class _Splash extends StatelessWidget {
  const _Splash({this.error, required this.onRetry});
  final String? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Paird', style: AppTheme.serif(size: 44, color: AppColors.gold).copyWith(letterSpacing: 1.5)),
            const SizedBox(height: 24),
            if (error == null)
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(error!, textAlign: TextAlign.center, style: AppTheme.sans(color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}
