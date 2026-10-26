import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/widgets/paird_widgets.dart';

/// Plans and entitlements come from GET /subscription/. Purchases are not
/// enabled until a payment provider is integrated; nothing is simulated.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await AppScope.read(context).api.subscription();
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

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('Premium')),
      body: d == null
          ? (_error != null ? ErrorView(message: _error!, onRetry: _load) : const LoadingView())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: _content(d),
            ),
    );
  }

  List<Widget> _content(Map<String, dynamic> d) {
    final ent = d['entitlements'] as Map;
    final current = ent['plan'] as String;
    final expires = ent['expires_at'] != null ? DateTime.tryParse(ent['expires_at'] as String)?.toLocal() : null;
    final purchasesEnabled = d['purchases_enabled'] == true;
    return [
      Text('Your plan: ${current == 'premium' ? 'Premium' : 'Free'}', style: AppTheme.serif(size: 30)),
      if (expires != null)
        Text('Active until ${expires.day}/${expires.month}/${expires.year}',
            style: AppTheme.sans(color: AppColors.textSecondary)),
      if (ent['daily_interest_limit'] != null)
        Text('You can send ${ent['daily_interest_limit']} interests per day.',
            style: AppTheme.sans(color: AppColors.textSecondary)),
      const SizedBox(height: 16),
      for (final plan in (d['plans'] as List).cast<Map>()) ...[
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: plan['id'] == 'premium' ? AppColors.gold : AppColors.border, width: plan['id'] == 'premium' ? 1.5 : 1),
            color: AppColors.surface,
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(plan['name'] as String, style: AppTheme.serif(size: 24))),
                  if (plan['id'] == current)
                    Text('Current', style: AppTheme.sans(size: 12, color: AppColors.gold, weight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 10),
              for (final f in (plan['features'] as List).cast<String>())
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check, size: 18, color: AppColors.gold),
                      const SizedBox(width: 8),
                      Expanded(child: Text(f, style: AppTheme.sans(color: AppColors.textLabel))),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (current != 'premium') ...[
        const SizedBox(height: 8),
        if (!purchasesEnabled) InfoBanner(d['purchases_message'] as String? ?? 'Purchases are not available yet.'),
        const SizedBox(height: 12),
        GoldButton(label: purchasesEnabled ? 'Upgrade to Premium' : 'Purchases coming soon', onPressed: null),
      ],
    ];
  }
}
