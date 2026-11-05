import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/api/api_exception.dart';
import '../../shared/widgets/paird_widgets.dart';

/// AI match insight (Claude via the PairD backend). Generated on first view
/// and cached by the server; hidden entirely when the server has AI switched off.
class AiInsightCard extends StatefulWidget {
  const AiInsightCard({super.key, required this.userId});
  final int userId;

  @override
  State<AiInsightCard> createState() => _AiInsightCardState();
}

class _AiInsightCardState extends State<AiInsightCard> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AppScope.read(context).api.memberInsight(widget.userId);
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _ratingColor(String rating) => switch (rating) {
        'strong' => AppColors.success,
        'good' => AppColors.gold,
        'possible' => AppColors.textLabel,
        _ => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SectionCard(
        title: 'AI match insight',
        child: Row(
          children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Expanded(
              child: Text('PairD AI is reading both profiles…',
                  style: AppTheme.sans(size: 13, color: AppColors.textSecondary)),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return SectionCard(
        title: 'AI match insight',
        child: Row(
          children: [
            Expanded(child: Text(_error!, style: AppTheme.sans(size: 13, color: AppColors.textSecondary))),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final data = _data!;
    if (data['status'] != 'ready') {
      final message = data['message'] as String? ?? '';
      // Server has AI switched off: show nothing rather than an empty card.
      if (message.contains("aren't switched on")) return const SizedBox.shrink();
      return SectionCard(
        title: 'AI match insight',
        child: Text(message, style: AppTheme.sans(size: 13, color: AppColors.textSecondary)),
      );
    }
    final insight = Map<String, dynamic>.from(data['insight'] as Map);
    final rating = insight['rating'] as String;
    final strengths = (insight['strengths'] as List).cast<String>();
    final considerations = (insight['considerations'] as List).cast<String>();
    final opener = insight['conversation_starter'] as String? ?? '';

    Widget bullet(IconData icon, Color color, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: AppTheme.sans(size: 13, color: AppColors.textLabel, height: 1.4))),
            ],
          ),
        );

    return SectionCard(
      title: 'AI match insight',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _ratingColor(rating)),
        ),
        child: Text(insight['rating_label'] as String,
            style: AppTheme.sans(size: 12, color: _ratingColor(rating), weight: FontWeight.w700)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(insight['summary'] as String, style: AppTheme.sans(height: 1.5)),
          if (strengths.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('What fits', style: AppTheme.sans(size: 12, color: AppColors.gold, weight: FontWeight.w600)),
            for (final s in strengths) bullet(Icons.check_circle_outline, AppColors.success, s),
          ],
          if (considerations.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Worth talking about', style: AppTheme.sans(size: 12, color: AppColors.gold, weight: FontWeight.w600)),
            for (final c in considerations) bullet(Icons.chat_bubble_outline, AppColors.textSecondary, c),
          ],
          if (opener.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Conversation opener', style: AppTheme.sans(size: 12, color: AppColors.gold, weight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('“$opener”', style: AppTheme.sans(size: 13, height: 1.4)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy'),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: opener));
                        if (context.mounted) showSnack(context, 'Opener copied');
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Written by AI from the profile details you can see. It can be wrong and is not a prediction — '
            'trust your own conversations.',
            style: AppTheme.sans(size: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
