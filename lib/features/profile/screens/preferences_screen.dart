import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/paird_widgets.dart';
import '../widgets/preferences_form.dart';

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  final _key = GlobalKey<PreferencesFormState>();
  Map<String, dynamic>? _prefs;
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
      final results = await Future.wait([api.preferences(), api.options()]);
      if (mounted) {
        setState(() {
          _prefs = results[0] as Map<String, dynamic>;
          _options = results[1] as AppOptions;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _save() async {
    final values = _key.currentState?.values();
    if (values == null || _saving) return;
    setState(() => _saving = true);
    try {
      await AppScope.read(context).api.updatePreferences(values);
      if (!mounted) return;
      showSnack(context, 'Preferences saved');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Partner preferences')),
      body: _prefs == null
          ? (_error != null ? ErrorView(message: _error!, onRetry: _load) : const LoadingView())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: PreferencesForm(key: _key, initial: _prefs!, options: _options!),
            ),
      bottomNavigationBar: _prefs == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: GoldButton(label: 'Save preferences', busy: _saving, onPressed: _save),
              ),
            ),
    );
  }
}
