import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/models.dart';
import '../../shared/widgets/paird_widgets.dart';
import 'screens/member_profile_screen.dart';

/// Profile card used by Discover and dashboard recommendations.
class MemberTile extends StatelessWidget {
  const MemberTile({
    super.key,
    required this.member,
    this.onChanged,
    this.trailing,
  });
  final MemberCard member;
  final VoidCallback? onChanged;
  final Widget? trailing;

  String? get _statusLabel => switch (member.connection?.status) {
    'interest_sent' => 'Interest sent',
    'interest_received' => 'Sent you an interest',
    'matched' => 'Matched',
    'declined' => 'Declined',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Semantics(
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) =>
                    MemberProfileScreen(userId: member.userId, preview: member),
              ),
            );
            if (changed == true) onChanged?.call();
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                MemberPhoto(
                  url: member.photoUrl,
                  name: member.displayName,
                  size: 76,
                  radius: 14,
                  hidden: member.photosHidden,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              member.displayName,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.serif(size: 22),
                            ),
                          ),
                          if (member.isVerified) ...[
                            const SizedBox(width: 6),
                            const VerifiedBadge(),
                          ],
                        ],
                      ),
                      if (member.headline.isNotEmpty)
                        Text(
                          member.headline,
                          style: AppTheme.sans(
                            size: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      if (member.occupation.isNotEmpty)
                        Text(
                          member.occupation,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.sans(
                            size: 13,
                            color: AppColors.textLabel,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          VibeBadge(score: member.vibe?.score),
                          if (_statusLabel != null)
                            Text(
                              _statusLabel!,
                              style: AppTheme.sans(
                                size: 12,
                                color: AppColors.gold,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                trailing ??
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.textSecondary,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
