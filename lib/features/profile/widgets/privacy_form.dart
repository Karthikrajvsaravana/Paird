import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/models/models.dart';

/// Privacy controls. Every option is enforced by the backend, not just hidden here.
class PrivacyForm extends StatelessWidget {
  const PrivacyForm({super.key, required this.values, required this.options, required this.onChanged});
  final Map<String, dynamic> values;
  final AppOptions options;
  final void Function(String field, dynamic value) onChanged;

  Widget _select(String field, String title, String subtitle) {
    final current = values[field]?.toString();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: AppTheme.sans(color: AppColors.textPrimary, weight: FontWeight.w500)),
      subtitle: Text(subtitle, style: AppTheme.sans(size: 12, color: AppColors.textSecondary)),
      trailing: DropdownButton<String>(
        value: current,
        dropdownColor: AppColors.surfaceRaised,
        underline: const SizedBox.shrink(),
        style: AppTheme.sans(color: AppColors.gold, weight: FontWeight.w600),
        items: [for (final o in options.choices(field)) DropdownMenuItem(value: o.value, child: Text(o.label))],
        onChanged: (v) => onChanged(field, v),
      ),
    );
  }

  Widget _toggle(String field, String title, String subtitle) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: values[field] == true,
        title: Text(title, style: AppTheme.sans(color: AppColors.textPrimary, weight: FontWeight.w500)),
        subtitle: Text(subtitle, style: AppTheme.sans(size: 12, color: AppColors.textSecondary)),
        onChanged: (v) => onChanged(field, v),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _toggle('discoverable', 'Show me in Discover', 'Turn off to hide your profile from new people.'),
        _select('photo_visibility', 'Photos', 'Who can see your photos.'),
        _select('interests_from', 'Interests from', 'Who can send you interests.'),
        _select('messages_from', 'Messages from', 'Only matches can ever message you.'),
        _select('income_visibility', 'Income', 'Who can see your income.'),
        _select('lifestyle_visibility', 'Lifestyle', 'Who can see diet, smoking and drinking.'),
        _toggle('show_last_seen', 'Show last active', 'If off, you also won’t see others’ last active time.'),
      ],
    );
  }
}
