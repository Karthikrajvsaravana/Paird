import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/paird_widgets.dart';

/// Partner preferences. Gender and age range filter discovery; everything
/// else is optional and shapes the Vibe Score (see README "Vibe Score").
class PreferencesForm extends StatefulWidget {
  const PreferencesForm({super.key, required this.initial, required this.options});
  final Map<String, dynamic> initial;
  final AppOptions options;

  @override
  State<PreferencesForm> createState() => PreferencesFormState();
}

class PreferencesFormState extends State<PreferencesForm> {
  late final Map<String, dynamic> _draft = Map<String, dynamic>.from(widget.initial);
  late RangeValues _age = RangeValues(
    ((widget.initial['age_min'] as int?) ?? _minAge).toDouble(),
    ((widget.initial['age_max'] as int?) ?? 45).toDouble(),
  );
  late bool _ageSet = widget.initial['age_min'] != null || widget.initial['age_max'] != null;
  late final _income = TextEditingController(text: widget.initial['income_min']?.toString() ?? '');
  final _countryInput = TextEditingController();
  String? _error;

  int get _minAge => widget.options.minAge == 0 ? 18 : widget.options.minAge;

  static const _multiFields = {
    'genders': 'gender',
    'marital_statuses': 'marital_status',
    'religions': 'religion',
    'education_levels': 'education_level',
    'employment_types': 'employment_type',
    'wants_children': 'wants_children',
    'marriage_timelines': 'marriage_timeline',
    'living_arrangements': 'living_arrangement',
    'diets': 'diet',
    'smoking': 'smoking',
    'drinking': 'drinking',
  };

  @override
  void dispose() {
    _income.dispose();
    _countryInput.dispose();
    super.dispose();
  }

  Set<String> _set(String field) => {...((_draft[field] as List?) ?? const []).map((e) => e.toString())};

  Map<String, dynamic>? values() {
    setState(() => _error = null);
    if (_set('genders').isEmpty) {
      setState(() => _error = 'Choose at least one gender you are looking for.');
      return null;
    }
    final incomeRaw = _income.text.trim().replaceAll(',', '');
    final income = incomeRaw.isEmpty ? null : int.tryParse(incomeRaw);
    if (incomeRaw.isNotEmpty && income == null) {
      setState(() => _error = 'Minimum income must be a number.');
      return null;
    }
    if (income != null && (_draft['income_currency'] ?? '').toString().isEmpty) {
      setState(() => _error = 'Select a currency for the minimum income.');
      return null;
    }
    return {
      for (final field in _multiFields.keys) field: _set(field).toList(),
      'countries': ((_draft['countries'] as List?) ?? const []).map((e) => e.toString()).toList(),
      'age_min': _ageSet ? _age.start.round() : null,
      'age_max': _ageSet ? _age.end.round() : null,
      'income_min': income,
      'income_currency': income == null ? '' : _draft['income_currency'],
      'requires_relocation_openness': _draft['requires_relocation_openness'] == true,
    };
  }

  Widget _multi(String field, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(label, optional: field != 'genders'),
        ChoiceChips(
          multi: true,
          options: [for (final c in widget.options.choices(_multiFields[field]!)) (value: c.value, label: c.label)],
          selected: _set(field),
          onChanged: (s) => setState(() => _draft[field] = s.toList()),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  void _addCountry() {
    final value = _countryInput.text.trim();
    if (value.isEmpty) return;
    final list = ((_draft['countries'] as List?) ?? const []).map((e) => e.toString()).toList();
    if (!list.any((c) => c.toLowerCase() == value.toLowerCase()) && list.length < 20) list.add(value);
    setState(() {
      _draft['countries'] = list;
      _countryInput.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final countries = ((_draft['countries'] as List?) ?? const []).map((e) => e.toString()).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 16)],
        const InfoBanner(
          'Gender and age decide who you see in Discover. Everything else is optional and only shapes your Vibe Score.',
        ),
        const SizedBox(height: 18),
        _multi('genders', 'Looking for'),
        Row(
          children: [
            const Expanded(child: FieldLabel('Age range', optional: true)),
            Switch(
              value: _ageSet,
              onChanged: (v) => setState(() => _ageSet = v),
            ),
          ],
        ),
        if (_ageSet) ...[
          Text('${_age.start.round()} – ${_age.end.round()} years', style: AppTheme.sans(color: AppColors.gold)),
          RangeSlider(
            values: _age,
            min: _minAge.toDouble(),
            max: 80,
            divisions: 80 - _minAge,
            activeColor: AppColors.gold,
            labels: RangeLabels('${_age.start.round()}', '${_age.end.round()}'),
            onChanged: (v) => setState(() => _age = v),
          ),
        ] else
          Text('Any age', style: AppTheme.sans(color: AppColors.textSecondary)),
        const SizedBox(height: 18),
        _multi('marital_statuses', 'Marital status'),
        _multi('religions', 'Religion'),
        const FieldLabel('Countries', optional: true),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _countryInput,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'Add a country'),
                onSubmitted: (_) => _addCountry(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(onPressed: _addCountry, icon: const Icon(Icons.add), tooltip: 'Add country'),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in countries)
              InputChip(
                label: Text(c),
                onDeleted: () => setState(() => _draft['countries'] = countries.where((x) => x != c).toList()),
              ),
          ],
        ),
        const SizedBox(height: 18),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _draft['requires_relocation_openness'] == true,
          title: Text('Partner should be open to relocating', style: AppTheme.sans(color: AppColors.textLabel)),
          onChanged: (v) => setState(() => _draft['requires_relocation_openness'] = v),
        ),
        const SizedBox(height: 8),
        _multi('education_levels', 'Education'),
        _multi('employment_types', 'Career'),
        const FieldLabel('Minimum annual income', optional: true),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _income,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Any'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                initialValue: (_draft['income_currency'] ?? '').toString().isEmpty ? null : _draft['income_currency'] as String,
                dropdownColor: AppColors.surfaceRaised,
                hint: const Text('Currency'),
                items: [
                  for (final c in widget.options.choices('income_currency'))
                    DropdownMenuItem(value: c.value, child: Text(c.label)),
                ],
                onChanged: (v) => setState(() => _draft['income_currency'] = v ?? ''),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 18),
          child: Text('Only compared with members who chose to show income and use the same currency.',
              style: AppTheme.sans(size: 12, color: AppColors.textMuted)),
        ),
        _multi('wants_children', 'Children'),
        _multi('marriage_timelines', 'Marriage timeline'),
        _multi('living_arrangements', 'Living arrangement'),
        _multi('diets', 'Diet'),
        _multi('smoking', 'Smoking'),
        _multi('drinking', 'Drinking'),
      ],
    );
  }
}
