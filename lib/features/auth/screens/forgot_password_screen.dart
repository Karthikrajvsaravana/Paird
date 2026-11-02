import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/auth/validators.dart';
import '../../../shared/widgets/paird_widgets.dart';

/// Forgot password, in two steps:
///  1. Request a 6-digit code by email.
///  2. Enter the code and a new password (with "Resend code" after a short wait).
/// Pops with the email address when the password was changed.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialIdentifier = ''});
  final String initialIdentifier;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _identifier = TextEditingController(
    text: widget.initialIdentifier.contains('@') ? widget.initialIdentifier : '',
  );
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  bool _resending = false;
  int _resendIn = 0;
  Timer? _timer;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _timer?.cancel();
    _identifier.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _resendIn = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn -= 1);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  Future<void> _sendCode({bool resend = false}) async {
    final api = AppScope.read(context).api;
    final wait = await api.requestPasswordReset(_identifier.text.trim());
    if (!mounted) return;
    setState(() {
      _codeSent = true;
      _info = resend
          ? 'If an account exists for this email, a new code is on its way. Earlier codes no longer work.'
          : 'If an account exists for this email, we sent a 6-digit code. It expires in 15 minutes. '
              'Check your spam folder if you don\'t see it.';
    });
    _startCountdown(wait);
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_codeSent) {
        await _sendCode();
      } else {
        final email = _identifier.text.trim();
        await AppScope.read(context).api.confirmPasswordReset(email, _code.text.trim(), _password.text);
        if (!mounted) return;
        Navigator.of(context).pop(email);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.fieldError('new_password') ?? e.fieldError('code') ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_resending || _resendIn > 0) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await _sendCode(resend: true);
      _code.clear();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _changeEmail() {
    _timer?.cancel();
    setState(() {
      _codeSent = false;
      _resendIn = 0;
      _info = null;
      _error = null;
      _code.clear();
      _password.clear();
      _confirm.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Reset your password', style: AppTheme.serif(size: 32, weight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  _codeSent
                      ? 'Enter the code from the email and choose a new password.'
                      : 'Enter the email address you signed up with and we\'ll send you a code. '
                          'Accounts created with a phone number can\'t reset by SMS yet — please contact support.',
                  style: AppTheme.sans(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 16)],
                if (_info != null) ...[InfoBanner(_info!, icon: Icons.mark_email_read_outlined), const SizedBox(height: 16)],
                PairdTextField(
                  label: 'Email',
                  controller: _identifier,
                  hint: 'name@example.com',
                  enabled: !_codeSent,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  validator: (value) {
                    final v = (value ?? '').trim();
                    if (v.isEmpty) return 'Please enter your email';
                    if (!v.contains('@')) return 'Password reset works with the email you signed up with';
                    return validateIdentifier(v);
                  },
                ),
                if (_codeSent) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(onPressed: _busy ? null : _changeEmail, child: const Text('Use a different email')),
                  ),
                  const SizedBox(height: 4),
                  PairdTextField(
                    label: '6-digit code',
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    validator: (v) => RegExp(r'^\d{6}$').hasMatch((v ?? '').trim()) ? null : 'Enter the 6-digit code',
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: (_resendIn > 0 || _resending || _busy) ? null : _resend,
                      child: Text(
                        _resending
                            ? 'Sending…'
                            : _resendIn > 0
                                ? 'Resend code in ${_resendIn}s'
                                : 'Didn\'t get it? Resend code',
                      ),
                    ),
                  ),
                  PairdTextField(
                    label: 'New password',
                    controller: _password,
                    obscure: true,
                    autofillHints: const [AutofillHints.newPassword],
                    validator: validateNewPassword,
                  ),
                  const SizedBox(height: 16),
                  PairdTextField(
                    label: 'Confirm new password',
                    controller: _confirm,
                    obscure: true,
                    validator: (v) => v != _password.text ? 'Passwords do not match' : null,
                  ),
                ],
                const SizedBox(height: 24),
                GoldButton(label: _codeSent ? 'Set new password' : 'Send code', busy: _busy, onPressed: _submit),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
