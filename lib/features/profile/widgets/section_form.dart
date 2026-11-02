import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/models/models.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/widgets/paird_widgets.dart';
import '../../../shared/widgets/pickers.dart';

/// Profile sections shared by onboarding and "Edit profile".
/// Keys match backend/profiles/services.py ONBOARDING_STEPS.
class ProfileSection {
  const ProfileSection(this.key, this.title, this.subtitle);
  final String key;
  final String title;
  final String subtitle;
}

const profileSections = {
  'basics': ProfileSection('basics', 'About you', 'The essentials members see first.'),
  'location': ProfileSection('location', 'Where you live', 'Your city is shown; your address never is.'),
  'career': ProfileSection('career', 'Education & career', 'Income is optional and private by default.'),
  'family': ProfileSection('family', 'Family', 'Share as much or as little as you like.'),
  'lifestyle': ProfileSection('lifestyle', 'Lifestyle', 'You can hide these in Settings.'),
  'plans': ProfileSection('plans', 'Marriage plans', 'Help matches understand your timeline.'),
  'about': ProfileSection('about', 'In your words', 'A short introduction goes a long way.'),
};

/// Form for one profile section. Read values with [SectionFormState.values].
class SectionForm extends StatefulWidget {
  const SectionForm({
    super.key,
    required this.section,
    required this.profile,
    required this.options,
    this.lookingFor = const [],
  });

  final String section;
  final Map<String, dynamic> profile;
  final AppOptions options;
  final List<String> lookingFor;

  @override
  State<SectionForm> createState() => SectionFormState();
}

class SectionFormState extends State<SectionForm> {
  final formKey = GlobalKey<FormState>();
  late final Map<String, dynamic> _draft = Map<String, dynamic>.from(widget.profile);
  late Set<String> _lookingFor = widget.lookingFor.toSet();
  final Map<String, TextEditingController> _text = {};
  String? _chipError;
  Country? _country; // resolved from the profile's country name
  bool _loadingLocation = false;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    if (widget.section == 'location' && (widget.profile['country'] ?? '').toString().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final country = await AppScope.read(context).api.countryNamed(widget.profile['country'] as String);
          if (mounted) setState(() => _country = country);
        } on ApiException {
          // Picker will retry when opened.
        }
      });
    }
  }

  static const _textFields = [
    'community',
    'mother_tongue',
    'city',
    'state',
    'country',
    'education_field',
    'occupation',
    'about_family',
    'about_me',
    'height_cm',
    'annual_income',
  ];

  static const _sectionFields = {
    'basics': [
      'gender',
      'date_of_birth',
      'height_cm',
      'marital_status',
      'has_children',
      'religion',
      'community',
      'mother_tongue',
    ],
    'location': ['city', 'state', 'country', 'open_to_relocate'],
    'career': ['education_level', 'education_field', 'occupation', 'employment_type', 'annual_income', 'income_currency'],
    'family': ['family_type', 'family_values', 'about_family'],
    'lifestyle': ['diet', 'smoking', 'drinking'],
    'plans': ['marriage_timeline', 'wants_children', 'living_arrangement'],
    'about': ['about_me'],
  };

  TextEditingController _controller(String field) => _text.putIfAbsent(
        field,
        () => TextEditingController(text: widget.profile[field]?.toString() ?? ''),
      );

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Validates and returns the changed values, or null if invalid.
  ({Map<String, dynamic> profile, List<String>? lookingFor})? values() {
    setState(() => _chipError = null);
    final valid = formKey.currentState?.validate() ?? false;
    final requiredChips = <String, String>{
      if (widget.section == 'basics') ...{'gender': 'your gender', 'marital_status': 'your marital status'},
      if (widget.section == 'career') 'education_level': 'your education',
      if (widget.section == 'plans') 'marriage_timeline': 'your marriage timeline',
    };
    for (final entry in requiredChips.entries) {
      if ((_draft[entry.key] ?? '').toString().isEmpty) {
        setState(() => _chipError = 'Please select ${entry.value}.');
        return null;
      }
    }
    if (widget.section == 'location' && _controller('country').text.trim().isEmpty) {
      setState(() => _chipError = 'Please choose your country.');
      return null;
    }
    if (widget.section == 'basics') {
      if (_lookingFor.isEmpty) {
        setState(() => _chipError = 'Please choose who you are looking for.');
        return null;
      }
      if (_draft['date_of_birth'] == null) {
        setState(() => _chipError = 'Please enter your date of birth.');
        return null;
      }
    }
    if (!valid) return null;

    final out = <String, dynamic>{};
    for (final field in _sectionFields[widget.section]!) {
      if (_textFields.contains(field)) {
        final raw = _controller(field).text.trim();
        if (field == 'height_cm' || field == 'annual_income') {
          out[field] = raw.isEmpty ? null : int.tryParse(raw.replaceAll(',', ''));
        } else {
          out[field] = raw;
        }
      } else {
        out[field] = _draft[field] ?? (field == 'has_children' ? null : '');
      }
    }
    if (widget.section == 'career' && out['annual_income'] == null) out['income_currency'] = '';
    return (profile: out, lookingFor: widget.section == 'basics' ? _lookingFor.toList() : null);
  }

  List<({String value, String label})> _opts(String name) =>
      [for (final c in widget.options.choices(name)) (value: c.value, label: c.label)];

  Widget _chips(String field, String label, {bool optional = false, String? choices}) {
    final current = _draft[field]?.toString() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(label, optional: optional),
        ChoiceChips(
          options: _opts(choices ?? field),
          selected: current.isEmpty ? {} : {current},
          onChanged: (s) => setState(() => _draft[field] = s.isEmpty ? '' : s.first),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _dropdown(String field, String label, {bool optional = false}) {
    final current = _draft[field]?.toString() ?? '';
    final options = widget.options.choices(field);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel(label, optional: optional),
          DropdownButtonFormField<String>(
            initialValue: current.isEmpty ? null : current,
            isExpanded: true,
            dropdownColor: AppColors.surfaceRaised,
            hint: Text('Select', style: AppTheme.sans(color: Colors.grey.shade600)),
            items: [
              if (optional) const DropdownMenuItem(value: '', child: Text('—')),
              for (final o in options) DropdownMenuItem(value: o.value, child: Text(o.label)),
            ],
            validator: optional ? null : (v) => (v == null || v.isEmpty) ? 'Please select $label'.toLowerCase() : null,
            onChanged: (v) => setState(() => _draft[field] = v ?? ''),
          ),
        ],
      ),
    );
  }

  Widget _textField(
    String field,
    String label, {
    bool optional = false,
    String? hint,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboard,
    FormFieldValidator<String>? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel(label, optional: optional),
          TextFormField(
            controller: _controller(field),
            maxLines: maxLines,
            maxLength: maxLength,
            keyboardType: keyboard,
            textCapitalization: maxLines > 1 ? TextCapitalization.sentences : TextCapitalization.words,
            style: AppTheme.sans(color: Colors.white),
            decoration: InputDecoration(hintText: hint),
            validator: validator ??
                (optional ? null : (v) => (v == null || v.trim().isEmpty) ? 'This field is required' : null),
          ),
        ],
      ),
    );
  }

  Widget _dateOfBirth() {
    final raw = _draft['date_of_birth'] as String?;
    final value = raw == null ? null : DateTime.tryParse(raw);
    final minAge = widget.options.minAge == 0 ? 18 : widget.options.minAge;
    final now = DateTime.now();
    final latest = DateTime(now.year - minAge, now.month, now.day);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('Date of birth'),
          PickerField(
            value: value == null ? null : formatBirthDate(value),
            placeholder: 'Select date',
            icon: Icons.cake_outlined,
            onTap: () async {
              final picked = await showBirthDatePicker(
                context,
                initial: value ?? DateTime(latest.year - 5, 1, 1),
                earliest: DateTime(now.year - 100, 1, 1),
                latest: latest,
                helpText: 'You must be $minAge or older to use PairD.',
              );
              if (picked != null) {
                setState(() => _draft['date_of_birth'] =
                    '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Only your age is shown to other members.',
                style: AppTheme.sans(size: 12, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCountry() async {
    final api = AppScope.read(context).api;
    setState(() {
      _loadingLocation = true;
      _locationError = null;
    });
    try {
      final countries = await api.countries();
      if (!mounted) return;
      final picked = await showSearchablePicker(
        context,
        title: 'Country',
        items: [for (final c in countries) c.name],
        selected: _controller('country').text,
        searchHint: 'Search countries',
      );
      if (picked == null || !mounted) return;
      final country = countries.firstWhere((c) => c.name == picked);
      setState(() {
        if (_controller('country').text != picked) _controller('state').clear();
        _controller('country').text = picked;
        _country = country;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _locationError = e.message);
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  Future<void> _pickState() async {
    final country = _country;
    if (country == null) return;
    setState(() {
      _loadingLocation = true;
      _locationError = null;
    });
    try {
      final states = await AppScope.read(context).api.states(country.code);
      if (!mounted) return;
      final picked = await showSearchablePicker(
        context,
        title: 'State / region',
        items: states,
        selected: _controller('state').text,
        searchHint: 'Search ${country.name}',
      );
      if (picked != null && mounted) setState(() => _controller('state').text = picked);
    } on ApiException catch (e) {
      if (mounted) setState(() => _locationError = e.message);
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  List<Widget> _locationFields() {
    final country = _controller('country').text;
    final state = _controller('state').text;
    final hasStates = _country?.hasStates ?? true;
    return [
      if (_locationError != null) ...[ErrorBanner(_locationError!), const SizedBox(height: 12)],
      const FieldLabel('Country'),
      PickerField(value: country, placeholder: 'Select your country', onTap: _loadingLocation ? () {} : _pickCountry),
      const SizedBox(height: 16),
      if (country.isNotEmpty && hasStates) ...[
        const FieldLabel('State / region', optional: true),
        PickerField(
          value: state,
          placeholder: _country == null ? 'Loading…' : 'Select your state',
          enabled: _country != null && !_loadingLocation,
          onTap: _pickState,
        ),
        const SizedBox(height: 16),
      ],
      if (_loadingLocation) const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator()),
      _textField('city', 'City', hint: 'e.g. Chennai', maxLength: 80),
      _chips('open_to_relocate', 'Open to relocating after marriage?', optional: true),
    ];
  }

  List<Widget> _fields() {
    switch (widget.section) {
      case 'basics':
        return [
          _chips('gender', 'I am a'),
          const FieldLabel("I'm looking for"),
          ChoiceChips(
            multi: true,
            options: _opts('gender'),
            selected: _lookingFor,
            onChanged: (s) => setState(() => _lookingFor = s),
          ),
          const SizedBox(height: 16),
          _dateOfBirth(),
          _chips('marital_status', 'Marital status'),
          const FieldLabel('Do you have children?', optional: true),
          ChoiceChips(
            options: const [(value: 'yes', label: 'Yes'), (value: 'no', label: 'No')],
            selected: _draft['has_children'] == null ? {} : {_draft['has_children'] == true ? 'yes' : 'no'},
            onChanged: (s) => setState(() => _draft['has_children'] = s.isEmpty ? null : s.first == 'yes'),
          ),
          const SizedBox(height: 16),
          _textField('height_cm', 'Height (cm)',
              optional: true,
              keyboard: TextInputType.number,
              hint: 'e.g. 168',
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = int.tryParse(v.trim());
                return (n == null || n < 120 || n > 230) ? 'Enter a height between 120 and 230 cm' : null;
              }),
          _dropdown('religion', 'Religion', optional: true),
          _textField('community', 'Community', optional: true, maxLength: 60),
          _textField('mother_tongue', 'Mother tongue', optional: true, maxLength: 40),
        ];
      case 'location':
        return _locationFields();
      case 'career':
        return [
          _dropdown('education_level', 'Highest education'),
          _textField('education_field', 'Field of study', optional: true, maxLength: 80),
          _textField('occupation', 'Occupation', hint: 'e.g. Software engineer', maxLength: 80),
          _chips('employment_type', 'Work', optional: true),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _textField('annual_income', 'Annual income',
                    optional: true,
                    keyboard: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      return int.tryParse(v.trim().replaceAll(',', '')) == null ? 'Numbers only' : null;
                    }),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: _dropdown('income_currency', 'Currency', optional: true)),
            ],
          ),
          Text('Income is visible to your matches only, unless you change it in Settings.',
              style: AppTheme.sans(size: 12, color: AppColors.textMuted)),
        ];
      case 'family':
        return [
          _chips('family_type', 'Family type', optional: true),
          _chips('family_values', 'Family values', optional: true),
          _textField('about_family', 'About your family', optional: true, maxLines: 4, maxLength: 500),
        ];
      case 'lifestyle':
        return [
          _chips('diet', 'Diet', optional: true),
          _chips('smoking', 'Smoking', optional: true),
          _chips('drinking', 'Drinking', optional: true),
        ];
      case 'plans':
        return [
          _chips('marriage_timeline', 'When are you hoping to marry?'),
          _chips('wants_children', 'Children in the future', optional: true),
          _chips('living_arrangement', 'After marriage, living', optional: true),
        ];
      case 'about':
        return [
          _textField('about_me', 'About me',
              optional: true,
              maxLines: 6,
              maxLength: 1000,
              hint: 'What matters to you, what a good weekend looks like, what you are looking for…'),
          Text("Please don't include phone numbers, emails or social handles.",
              style: AppTheme.sans(size: 12, color: AppColors.textMuted)),
        ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_chipError != null) ...[ErrorBanner(_chipError!), const SizedBox(height: 16)],
          ..._fields(),
        ],
      ),
    );
  }
}
