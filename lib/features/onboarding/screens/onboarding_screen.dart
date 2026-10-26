import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/paird_widgets.dart';
import '../../profile/widgets/photo_manager.dart';
import '../../profile/widgets/preferences_form.dart';
import '../../profile/widgets/privacy_form.dart';
import '../../profile/widgets/section_form.dart';

/// First-time profile setup. Progress is saved to the server after every
/// step (profile.onboarding_step), so members can leave and resume later.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _steps = [
    'basics',
    'location',
    'career',
    'family',
    'lifestyle',
    'plans',
    'about',
    'photos',
    'preferences',
    'privacy',
  ];

  late Future<void> _loading;
  AppOptions? _options;
  Map<String, dynamic> _profile = {};
  Map<String, dynamic> _preferences = {};
  Map<String, dynamic> _privacy = {};
  int _index = 0;
  bool _saving = false;
  bool _consent = false;
  String? _error;

  // One key per step: a shared GlobalKey would carry state between sections.
  final _sectionKeys = <String, GlobalKey<SectionFormState>>{};
  GlobalKey<SectionFormState> get _sectionKey => _sectionKeys.putIfAbsent(_step, GlobalKey<SectionFormState>.new);
  final _prefKey = GlobalKey<PreferencesFormState>();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loading = _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = AppScope.read(context).api;
    final results = await Future.wait([api.options(), api.myProfile(), api.preferences()]);
    _options = results[0] as AppOptions;
    _profile = results[1] as Map<String, dynamic>;
    _preferences = results[2] as Map<String, dynamic>;
    _privacy = {
      for (final k in [
        'discoverable',
        'photo_visibility',
        'interests_from',
        'messages_from',
        'income_visibility',
        'lifestyle_visibility',
        'show_last_seen',
      ])
        k: _profile[k],
    };
    _consent = _profile['consent_accepted_at'] != null;
    _index = ((_profile['onboarding_step'] as int?) ?? 0).clamp(0, _steps.length - 1);
  }

  String get _step => _steps[_index];

  Future<void> _next() async {
    if (_saving) return;
    final api = AppScope.read(context).api;
    final auth = AppScope.read(context).auth;
    setState(() => _error = null);

    Map<String, dynamic>? profileChanges;
    Map<String, dynamic>? prefChanges;
    if (profileSections.containsKey(_step)) {
      final values = _sectionKey.currentState?.values();
      if (values == null) return;
      profileChanges = values.profile;
      if (values.lookingFor != null) prefChanges = {'genders': values.lookingFor};
    } else if (_step == 'photos') {
      profileChanges = {};
    } else if (_step == 'preferences') {
      prefChanges = _prefKey.currentState?.values();
      if (prefChanges == null) return;
      profileChanges = {};
    } else if (_step == 'privacy') {
      if (!_consent) {
        setState(() => _error = 'Please confirm the statements below to publish your profile.');
        return;
      }
      profileChanges = {..._privacy, 'accept_consent': true};
    }

    setState(() => _saving = true);
    try {
      if (prefChanges != null) _preferences = await api.updatePreferences(prefChanges);
      final isLast = _index == _steps.length - 1;
      _profile = await api.updateProfile({
        ...?profileChanges,
        if (!isLast) 'onboarding_step': _index + 1,
      });
      if (isLast) {
        await api.publishProfile();
        await auth.refreshAccount(); // AuthGate now shows the home screen.
        return;
      }
      if (!mounted) return;
      setState(() => _index += 1);
      _scroll.jumpTo(0);
    } on ApiException catch (e) {
      if (!mounted) return;
      final missing = e.fields['missing_required'];
      setState(() => _error = missing is List && missing.isNotEmpty
          ? 'Some required details are missing: ${missing.join(', ').replaceAll('_', ' ')}. Go back to complete them.'
          : e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _body() {
    final options = _options!;
    if (profileSections.containsKey(_step)) {
      return SectionForm(
        key: _sectionKey,
        section: _step,
        profile: _profile,
        options: options,
        lookingFor: ((_preferences['genders'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );
    }
    switch (_step) {
      case 'photos':
        return PhotoManager(
          photos: ((_profile['photos'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          maxPhotos: options.photoMaxCount,
          onChanged: (photos) => _profile['photos'] = photos,
        );
      case 'preferences':
        return PreferencesForm(key: _prefKey, initial: _preferences, options: options);
      case 'privacy':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PrivacyForm(
              values: _privacy,
              options: options,
              onChanged: (field, value) => setState(() => _privacy[field] = value),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _consent,
              activeColor: AppColors.gold,
              checkColor: AppColors.background,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'I am at least ${options.minAge} years old, I am looking for marriage, the information in my profile '
                'is true, and I agree that Paird shows my profile to other members according to my privacy settings.',
                style: AppTheme.sans(size: 13, color: AppColors.textLabel),
              ),
              onChanged: (v) => setState(() => _consent = v ?? false),
            ),
          ],
        );
    }
    return const SizedBox.shrink();
  }

  String get _title {
    if (profileSections.containsKey(_step)) return profileSections[_step]!.title;
    return {'photos': 'Your photos', 'preferences': 'Who you’re looking for', 'privacy': 'Privacy & consent'}[_step]!;
  }

  String get _subtitle {
    if (profileSections.containsKey(_step)) return profileSections[_step]!.subtitle;
    return {
      'photos': 'Optional, but profiles with a clear photo receive far more interest.',
      'preferences': 'You can change these at any time.',
      'privacy': 'Choose what others can see. You can change this later in Settings.',
    }[_step]!;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: LoadingView());
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: ErrorView(
              message: snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'Could not load your profile.',
              onRetry: () => setState(() => _loading = _load()),
            ),
          );
        }
        final isLast = _index == _steps.length - 1;
        return Scaffold(
          appBar: AppBar(
            leading: _index > 0
                ? IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
                    onPressed: _saving ? null : () => setState(() => _index -= 1),
                  )
                : null,
            title: Text('Paird', style: AppTheme.serif(size: 28, color: AppColors.gold)),
            actions: [
              TextButton(
                onPressed: () => AppScope.read(context).auth.signOut(),
                child: const Text('Sign out'),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Semantics(
                    label: 'Step ${_index + 1} of ${_steps.length}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (_index + 1) / _steps.length,
                        minHeight: 4,
                        backgroundColor: AppColors.border,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Step ${_index + 1} of ${_steps.length}',
                            style: AppTheme.sans(size: 12, color: AppColors.gold, weight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(_title, style: AppTheme.serif(size: 32, weight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(_subtitle, style: AppTheme.sans(color: AppColors.textSecondary)),
                        const SizedBox(height: 24),
                        if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 16)],
                        KeyedSubtree(key: ValueKey(_step), child: _body()),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: GoldButton(
                    label: isLast ? 'Publish my profile' : 'Save & continue',
                    busy: _saving,
                    onPressed: _next,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
