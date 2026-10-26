import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/widgets/paird_widgets.dart';

/// Photo verification: a selfie reviewed by Paird staff against profile
/// photos. Status only changes when staff record a decision on the server.
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await AppScope.read(context).api.verification();
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _submit() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 1600,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    final scope = AppScope.read(context);
    try {
      final data = await scope.api.submitVerification(await picked.readAsBytes(), picked.name);
      if (!mounted) return;
      setState(() => _data = data);
      scope.auth.refreshAccount().catchError((_) {});
      showSnack(context, 'Submitted for review.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.fieldError('selfie') ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final status = d?['status'] as String? ?? 'unverified';
    final (icon, title, color) = switch (status) {
      'verified' => (Icons.verified, 'You’re photo verified', AppColors.success),
      'pending' => (Icons.hourglass_top, 'Under review', AppColors.gold),
      'rejected' => (Icons.error_outline, 'Not approved', AppColors.error),
      _ => (Icons.verified_outlined, 'Not verified yet', AppColors.textSecondary),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Verification')),
      body: d == null
          ? (_error != null ? ErrorView(message: _error!, onRetry: _load) : const LoadingView())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Icon(icon, color: color, size: 56),
                const SizedBox(height: 12),
                Text(title, textAlign: TextAlign.center, style: AppTheme.serif(size: 30)),
                const SizedBox(height: 12),
                Text(d['description'] as String, textAlign: TextAlign.center, style: AppTheme.sans(color: AppColors.textLabel, height: 1.5)),
                if (status == 'rejected' && (d['rejection_reason'] as String? ?? '').isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ErrorBanner(d['rejection_reason'] as String),
                ],
                if (status == 'pending') ...[
                  const SizedBox(height: 16),
                  const InfoBanner('A member of the Paird team will review your selfie. This page updates when they do.'),
                ],
                const SizedBox(height: 24),
                if (d['can_submit'] == true && status != 'verified')
                  GoldButton(
                    label: status == 'rejected' ? 'Try again with a new selfie' : 'Take a selfie',
                    icon: Icons.camera_alt_outlined,
                    busy: _busy,
                    onPressed: _submit,
                  ),
                const SizedBox(height: 12),
                Text(
                  'Verification confirms that your photos look like you. It is not an identity or background check.',
                  textAlign: TextAlign.center,
                  style: AppTheme.sans(size: 12, color: AppColors.textMuted),
                ),
              ],
            ),
    );
  }
}
