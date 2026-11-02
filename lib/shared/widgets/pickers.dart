import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';

/// Bottom sheet with a search box and a scrollable list. Returns the chosen item.
Future<String?> showSearchablePicker(
  BuildContext context, {
  required String title,
  required List<String> items,
  String? selected,
  String searchHint = 'Search',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SearchablePickerSheet(title: title, items: items, selected: selected, searchHint: searchHint),
  );
}

class _SearchablePickerSheet extends StatefulWidget {
  const _SearchablePickerSheet({required this.title, required this.items, this.selected, required this.searchHint});
  final String title;
  final List<String> items;
  final String? selected;
  final String searchHint;

  @override
  State<_SearchablePickerSheet> createState() => _SearchablePickerSheetState();
}

class _SearchablePickerSheetState extends State<_SearchablePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final matches = q.isEmpty ? widget.items : widget.items.where((i) => i.toLowerCase().contains(q)).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  Expanded(child: Text(widget.title, style: AppTheme.serif(size: 26))),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                autofocus: false,
                style: AppTheme.sans(color: Colors.white),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: matches.isEmpty
                  ? Center(child: Text('No matches', style: AppTheme.sans(color: AppColors.textSecondary)))
                  : ListView.builder(
                      controller: controller,
                      itemCount: matches.length,
                      itemBuilder: (context, i) {
                        final item = matches[i];
                        final isSelected = item == widget.selected;
                        return ListTile(
                          title: Text(
                            item,
                            style: AppTheme.sans(
                              color: isSelected ? AppColors.gold : AppColors.textPrimary,
                              weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                          trailing: isSelected ? const Icon(Icons.check, color: AppColors.gold) : null,
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tappable, read-only field that opens a picker (e.g. Country, State).
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.icon = Icons.expand_more,
    this.enabled = true,
    this.errorText,
  });

  final String? value;
  final String placeholder;
  final VoidCallback onTap;
  final IconData icon;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;
    return Semantics(
      button: true,
      label: hasValue ? '$placeholder: $value' : placeholder,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: InputDecorator(
          isEmpty: !hasValue,
          decoration: InputDecoration(
            enabled: enabled,
            errorText: errorText,
            suffixIcon: Icon(icon, color: enabled ? AppColors.gold : AppColors.textMuted),
          ),
          child: Text(
            hasValue ? value! : placeholder,
            style: AppTheme.sans(color: hasValue ? Colors.white : Colors.grey.shade600),
          ),
        ),
      ),
    );
  }
}

const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String formatBirthDate(DateTime date) => '${date.day} ${monthNames[date.month - 1]} ${date.year}';

/// Day / month / year scroll wheels. Returns the chosen date, never later than [latest].
Future<DateTime?> showBirthDatePicker(
  BuildContext context, {
  required DateTime initial,
  required DateTime earliest,
  required DateTime latest,
  String? helpText,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    builder: (_) => _BirthDateSheet(initial: initial, earliest: earliest, latest: latest, helpText: helpText),
  );
}

class _BirthDateSheet extends StatefulWidget {
  const _BirthDateSheet({required this.initial, required this.earliest, required this.latest, this.helpText});
  final DateTime initial;
  final DateTime earliest;
  final DateTime latest;
  final String? helpText;

  @override
  State<_BirthDateSheet> createState() => _BirthDateSheetState();
}

class _BirthDateSheetState extends State<_BirthDateSheet> {
  late int _day = widget.initial.day;
  late int _month = widget.initial.month;
  late int _year = widget.initial.year;
  late final List<int> _years = [for (var y = widget.latest.year; y >= widget.earliest.year; y--) y];
  late final _dayController = FixedExtentScrollController(initialItem: _day - 1);
  late final _monthController = FixedExtentScrollController(initialItem: _month - 1);
  late final _yearController = FixedExtentScrollController(initialItem: _years.indexOf(_year).clamp(0, _years.length - 1));

  @override
  void dispose() {
    _dayController.dispose();
    _monthController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  int get _daysInMonth => DateUtils.getDaysInMonth(_year, _month);

  DateTime get _selected => DateTime(_year, _month, _day.clamp(1, _daysInMonth));

  bool get _tooYoung => _selected.isAfter(widget.latest);

  void _changed() {
    if (_day > _daysInMonth) {
      _day = _daysInMonth;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_dayController.hasClients) _dayController.jumpToItem(_day - 1);
      });
    }
    setState(() {});
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required String Function(int index) label,
    required ValueChanged<int> onSelected,
    required String semanticsLabel,
    int flex = 1,
  }) {
    return Expanded(
      flex: flex,
      child: Semantics(
        label: semanticsLabel,
        child: CupertinoPicker(
          scrollController: controller,
          itemExtent: 40,
          looping: false,
          selectionOverlay: Container(
            decoration: BoxDecoration(
              border: Border.symmetric(horizontal: BorderSide(color: AppColors.gold.withValues(alpha: 0.5))),
            ),
          ),
          onSelectedItemChanged: (index) {
            onSelected(index);
            _changed();
          },
          children: [
            for (var i = 0; i < count; i++)
              Center(child: Text(label(i), style: AppTheme.sans(size: 18, color: AppColors.textPrimary))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Date of birth', style: AppTheme.serif(size: 26)),
            if (widget.helpText != null)
              Text(widget.helpText!, style: AppTheme.sans(size: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: CupertinoTheme(
                data: const CupertinoThemeData(brightness: Brightness.dark),
                child: Row(
                  children: [
                    _wheel(
                      controller: _dayController,
                      count: 31,
                      label: (i) => '${i + 1}',
                      onSelected: (i) => _day = (i + 1).clamp(1, _daysInMonth),
                      semanticsLabel: 'Day',
                    ),
                    _wheel(
                      controller: _monthController,
                      count: 12,
                      label: (i) => monthNames[i],
                      onSelected: (i) => _month = i + 1,
                      semanticsLabel: 'Month',
                      flex: 2,
                    ),
                    _wheel(
                      controller: _yearController,
                      count: _years.length,
                      label: (i) => '${_years[i]}',
                      onSelected: (i) => _year = _years[i],
                      semanticsLabel: 'Year',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _tooYoung ? (widget.helpText ?? 'This date is too recent.') : formatBirthDate(_selected),
              textAlign: TextAlign.center,
              style: AppTheme.sans(color: _tooYoung ? AppColors.error : AppColors.gold, weight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: AppColors.background,
                      minimumSize: const Size(48, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _tooYoung ? null : () => Navigator.pop(context, _selected),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
