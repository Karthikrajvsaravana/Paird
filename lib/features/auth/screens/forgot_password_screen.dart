import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/auth/validators.dart';
import '../../../shared/widgets/paird_widgets.dart';

/// Two steps: request a 6-digit code by email, then set a new password.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialIdentifier = ''});
  final String initialIdentifier;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _identifier = TextEditingController(text: widget.initialIdentifier);
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _identifier.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = AppScope.read(context).api;
    try {
      if (!_codeSent) {
        await api.requestPasswordReset(_identifier.text.trim());
        setState(() {
          _codeSent = true;
          _info = 'If an account exists for this email, we sent a 6-digit code. It expires in 15 minutes.';
        });
      } else {
        await api.confirmPasswordReset(_identifier.text.trim(), _code.text.trim(), _password.text);
        if (!mounted) return;
        showSnack(context, 'Password updated. Please sign in.');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      setState(() => _error = e.fieldError('new_password') ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Reset your password', style: AppTheme.serif(size: 32, weight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  'Enter the email address on your account. Phone-number accounts can’t reset by SMS yet — contact support.',
                  style: AppTheme.sans(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 16)],
                if (_info != null) ...[InfoBanner(_info!), const SizedBox(height: 16)],
                PairdTextField(
                  label: 'Email',
                  controller: _identifier,
                  hint: 'name@example.com',
                  enabled: !_codeSent,
                  keyboardType: TextInputType.emailAddress,
                  validator: validateIdentifier,
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 16),
                  PairdTextField(
                    label: '6-digit code',
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    validator: (v) => RegExp(r'^\d{6}$').hasMatch((v ?? '').trim()) ? null : 'Enter the 6-digit code',
                  ),
                  const SizedBox(height: 8),
                  PairdTextField(
                    label: 'New password',
                    controller: _password,
                    obscure: true,
                    autofillHints: const [AutofillHints.newPassword],
                    validator: validateNewPassword,
                  ),
                ],
                const SizedBox(height: 24),
                GoldButton(label: _codeSent ? 'Set new password' : 'Send code', busy: _busy, onPressed: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
