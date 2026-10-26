import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/paird_widgets.dart';
import '../../profile/screens/preferences_screen.dart';
import '../member_tile.dart';

/// Eligible profiles from GET /discover/, 20 per page with infinite scroll.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _items = <MemberCard>[];
  final _scroll = ScrollController();
  Map<String, dynamic> _filters = {};
  int _page = 0;
  int _count = 0;
  bool _hasNext = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 0;
      _hasNext = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasNext) return;
    setState(() => _loading = true);
    try {
      final result = await AppScope.read(context).api.discover(page: _page + 1, filters: _filters);
      if (!mounted) return;
      setState(() {
        _page += 1;
        _items.addAll(result.items.where((m) => !_items.any((x) => x.userId == m.userId)));
        _hasNext = result.hasNext;
        _count = result.count;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openFilters() async {
    final options = await AppScope.read(context).api.options();
    if (!mounted) return;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(initial: _filters, options: options),
    );
    if (result != null) {
      _filters = result;
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeFilters = _filters.values.where((v) => v != null && v != false && v != '' && !(v is List && v.isEmpty)).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            tooltip: 'Partner preferences',
            icon: const Icon(Icons.tune),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PreferencesScreen()));
              _reload();
            },
          ),
          IconButton(
            tooltip: 'Filters',
            icon: Badge(isLabelVisible: activeFilters > 0, label: Text('$activeFilters'), child: const Icon(Icons.filter_list)),
            onPressed: _openFilters,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: Builder(
          builder: (context) {
            if (_items.isEmpty && _loading) return const LoadingView();
            if (_items.isEmpty && _error != null) return ErrorView(message: _error!, onRetry: _reload);
            if (_items.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  EmptyView(
                    icon: Icons.explore_outlined,
                    title: 'No profiles right now',
                    message: activeFilters > 0
                        ? 'Try removing some filters.'
                        : 'Nobody matches your preferences yet. Widen your age range or check back later.',
                    action: activeFilters > 0
                        ? OutlinedButton(
                            onPressed: () {
                              _filters = {};
                              _reload();
                            },
                            child: const Text('Clear filters'))
                        : null,
                  ),
                ],
              );
            }
            return ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: _items.length + 2,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Text('$_count ${_count == 1 ? 'profile' : 'profiles'} for you',
                      style: AppTheme.sans(size: 13, color: AppColors.textSecondary));
                }
                if (index == _items.length + 1) {
                  if (_loading) return const Padding(padding: EdgeInsets.all(16), child: LoadingView());
                  if (_error != null) return TextButton(onPressed: _loadMore, child: const Text('Retry loading more'));
                  return const SizedBox(height: 8);
                }
                return MemberTile(member: _items[index - 1], onChanged: _reload);
              },
            );
          },
        ),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.options});
  final Map<String, dynamic> initial;
  final AppOptions options;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final Map<String, dynamic> _f = Map<String, dynamic>.from(widget.initial);
  late final _city = TextEditingController(text: widget.initial['city'] as String? ?? '');
  late final _country = TextEditingController(text: widget.initial['country'] as String? ?? '');

  @override
  void dispose() {
    _city.dispose();
    _country.dispose();
    super.dispose();
  }

  Widget _multi(String key, String choiceName, String label) {
    final selected = {...((_f[key] as List?) ?? const []).map((e) => e.toString())};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(label),
        ChoiceChips(
          multi: true,
          options: [for (final c in widget.options.choices(choiceName)) (value: c.value, label: c.label)],
          selected: selected,
          onChanged: (s) => setState(() => _f[key] = s.toList()),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final min = widget.options.minAge == 0 ? 18 : widget.options.minAge;
    final age = RangeValues(((_f['age_min'] as int?) ?? min).toDouble(), ((_f['age_max'] as int?) ?? 60).toDouble());
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Row(
              children: [
                Expanded(child: Text('Filters', style: AppTheme.serif(size: 28))),
                TextButton(onPressed: () => Navigator.pop(context, <String, dynamic>{}), child: const Text('Reset')),
              ],
            ),
            Text('Filters apply on top of your partner preferences.',
                style: AppTheme.sans(size: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            FieldLabel('Age: ${age.start.round()} – ${age.end.round()}'),
            RangeSlider(
              values: age,
              min: min.toDouble(),
              max: 80,
              divisions: 80 - min,
              onChanged: (v) => setState(() {
                _f['age_min'] = v.start.round();
                _f['age_max'] = v.end.round();
              }),
            ),
            TextField(controller: _city, decoration: const InputDecoration(labelText: 'City contains')),
            const SizedBox(height: 12),
            TextField(controller: _country, decoration: const InputDecoration(labelText: 'Country')),
            const SizedBox(height: 16),
            _multi('religion', 'religion', 'Religion'),
            _multi('education_level', 'education_level', 'Education'),
            _multi('marital_status', 'marital_status', 'Marital status'),
            _multi('marriage_timeline', 'marriage_timeline', 'Marriage timeline'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Verified members only'),
              value: _f['verified_only'] == true,
              onChanged: (v) => setState(() => _f['verified_only'] = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('With photos only'),
              value: _f['with_photo'] == true,
              onChanged: (v) => setState(() => _f['with_photo'] = v),
            ),
            const SizedBox(height: 12),
            GoldButton(
              label: 'Show results',
              onPressed: () => Navigator.pop(context, {
                ..._f,
                'city': _city.text.trim(),
                'country': _country.text.trim(),
              }),
            ),
          ],
        ),
      ),
    );
  }
}
