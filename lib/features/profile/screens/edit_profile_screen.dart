import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/paird_widgets.dart';
import '../widgets/photo_manager.dart';
import '../widgets/section_form.dart';

/// Lists profile sections; each opens an editor that saves to the backend.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, this.initialSection});
  final String? initialSection;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  Map<String, dynamic>? _profile;
  AppOptions? _options;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      final initial = widget.initialSection;
      if (initial != null && mounted && _profile != null) _openSection(initial);
    });
  }

  Future<void> _load() async {
    final api = AppScope.read(context).api;
    try {
      final results = await Future.wait([api.myProfile(), api.options()]);
      if (mounted) {
        setState(() {
          _profile = results[0] as Map<String, dynamic>;
          _options = results[1] as AppOptions;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _openSection(String key) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _SectionEditor(section: key, profile: _profile!, options: _options!),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: _profile == null
          ? (_error != null ? ErrorView(message: _error!, onRetry: _load) : const LoadingView())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.badge_outlined, color: AppColors.gold),
                    title: const Text('Name'),
                    subtitle: Text(_profile!['full_name'] as String? ?? ''),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _NameEditor()));
                      _load();
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Column(
                    children: [
                      for (final section in [...profileSections.values])
                        ListTile(
                          title: Text(section.title, style: AppTheme.sans(weight: FontWeight.w600)),
                          subtitle: Text(section.subtitle, style: AppTheme.sans(size: 12, color: AppColors.textSecondary)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openSection(section.key),
                        ),
                      ListTile(
                        title: Text('Photos', style: AppTheme.sans(weight: FontWeight.w600)),
                        subtitle: Text('${(_profile!['photos'] as List).length} photo(s)',
                            style: AppTheme.sans(size: 12, color: AppColors.textSecondary)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openSection('photos'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionEditor extends StatefulWidget {
  const _SectionEditor({required this.section, required this.profile, required this.options});
  final String section;
  final Map<String, dynamic> profile;
  final AppOptions options;

  @override
  State<_SectionEditor> createState() => _SectionEditorState();
}

class _SectionEditorState extends State<_SectionEditor> {
  final _key = GlobalKey<SectionFormState>();
  List<String> _lookingFor = const [];
  bool _ready = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.section == 'basics') {
      AppScope.read(context).api.preferences().then((p) {
        if (mounted) {
          setState(() {
            _lookingFor = ((p['genders'] as List?) ?? const []).map((e) => e.toString()).toList();
            _ready = true;
          });
        }
      }, onError: (Object e) {
        if (mounted) setState(() => _error = e is ApiException ? e.message : 'Could not load preferences.');
      });
    } else {
      _ready = true;
    }
  }

  Future<void> _save() async {
    final values = _key.currentState?.values();
    if (values == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = AppScope.read(context).api;
    try {
      if (values.lookingFor != null) await api.updatePreferences({'genders': values.lookingFor});
      await api.updateProfile(values.profile);
      if (!mounted) return;
      showSnack(context, 'Saved');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPhotos = widget.section == 'photos';
    final title = isPhotos ? 'Photos' : profileSections[widget.section]!.title;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: !_ready
          ? (_error != null ? ErrorView(message: _error!) : const LoadingView())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
                  if (isPhotos)
                    PhotoManager(
                      photos: (widget.profile['photos'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
                      maxPhotos: widget.options.photoMaxCount,
                    )
                  else
                    SectionForm(
                      key: _key,
                      section: widget.section,
                      profile: widget.profile,
                      options: widget.options,
                      lookingFor: _lookingFor,
                    ),
                ],
              ),
            ),
      bottomNavigationBar: isPhotos || !_ready
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: GoldButton(label: 'Save', busy: _saving, onPressed: _save),
              ),
            ),
    );
  }
}

class _NameEditor extends StatefulWidget {
  const _NameEditor();

  @override
  State<_NameEditor> createState() => _NameEditorState();
}

class _NameEditorState extends State<_NameEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: AppScope.read(context).auth.account?.fullName ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final scope = AppScope.read(context);
    try {
      final account = await scope.api.updateName(_name.text.trim());
      scope.auth.updateAccount(account);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Name')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
            PairdTextField(
              label: 'Full name',
              controller: _name,
              validator: (v) => (v ?? '').trim().length < 2 ? 'Please enter your full name' : null,
            ),
            const SizedBox(height: 8),
            Text('Other members see your first name and last initial only.',
                style: AppTheme.sans(size: 12, color: AppColors.textMuted)),
            const SizedBox(height: 20),
            GoldButton(label: 'Save', busy: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
