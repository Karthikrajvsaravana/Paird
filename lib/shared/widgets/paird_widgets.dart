import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';

/// Label-above text field in the style of the original auth screens.
class PairdTextField extends StatefulWidget {
  const PairdTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.validator,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.maxLength,
    this.autofillHints,
    this.onFieldSubmitted,
    this.errorText,
    this.enabled = true,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int maxLines;
  final int? maxLength;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onFieldSubmitted;
  final String? errorText;
  final bool enabled;

  @override
  State<PairdTextField> createState() => _PairdTextFieldState();
}

class _PairdTextFieldState extends State<PairdTextField> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label, style: AppTheme.sans(size: 13, color: AppColors.textLabel, weight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          obscureText: _hidden,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          maxLength: widget.maxLength,
          autofillHints: widget.autofillHints,
          onFieldSubmitted: widget.onFieldSubmitted,
          style: AppTheme.sans(color: Colors.white),
          validator: widget.validator,
          decoration: InputDecoration(
            hintText: widget.hint,
            errorText: widget.errorText,
            errorMaxLines: 3,
            suffixIcon: widget.obscure
                ? IconButton(
                    tooltip: _hidden ? 'Show password' : 'Hide password',
                    icon: Icon(_hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: Colors.grey.shade400),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

/// Gold gradient primary action, matching "Create Account".
class GoldButton extends StatelessWidget {
  const GoldButton({super.key, required this.label, this.onPressed, this.busy = false, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.5,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: AppColors.goldGradient,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: AppColors.goldDeep.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 4)),
          ],
        ),
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[Icon(icon, color: AppColors.background, size: 20), const SizedBox(width: 8)],
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.sans(
                          size: 15,
                          color: AppColors.background,
                          weight: FontWeight.w700,
                        ).copyWith(letterSpacing: 0.5),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Red-bordered error banner used by the auth screens.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade800.withValues(alpha: 0.2),
          border: Border.all(color: Colors.red.shade800),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(message, style: AppTheme.sans(color: Colors.red.shade200, size: 13)),
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner(this.message, {super.key, this.icon = Icons.info_outline});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.gold, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: AppTheme.sans(size: 13, color: AppColors.textLabel))),
        ],
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, color: AppColors.textSecondary, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: AppTheme.sans(color: AppColors.textSecondary)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.gold, size: 40),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: AppTheme.serif(size: 24)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: AppTheme.sans(color: AppColors.textSecondary)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.child, this.trailing, this.padding = const EdgeInsets.all(16)});
  final String? title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(child: Text(title!, style: AppTheme.serif(size: 22))),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Network photo served by the authenticated API.
class MemberPhoto extends StatelessWidget {
  const MemberPhoto({
    super.key,
    required this.url,
    required this.name,
    this.size = 56,
    this.radius = 28,
    this.hidden = false,
  });

  final String? url;
  final String name;
  final double size;
  final double radius;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final headers = AppScope.of(context).api.client.imageHeaders;
    Widget placeholder() => Container(
          color: AppColors.surfaceRaised,
          alignment: Alignment.center,
          child: hidden
              ? Icon(Icons.lock_outline, color: AppColors.textSecondary, size: size * 0.35)
              : Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: AppTheme.serif(size: size * 0.42, color: AppColors.gold),
                ),
        );
    return Semantics(
      label: hidden ? 'Photo visible to matches only' : 'Photo of $name',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: size,
          height: size,
          child: url == null
              ? placeholder()
              : Image.network(
                  url!,
                  headers: headers,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => placeholder(),
                  loadingBuilder: (context, child, progress) => progress == null ? child : placeholder(),
                ),
        ),
      ),
    );
  }
}

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 16});
  final double size;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Photo verified by the Paird team',
        child: Icon(Icons.verified, color: AppColors.success, size: size, semanticLabel: 'Photo verified'),
      );
}

class VibeBadge extends StatelessWidget {
  const VibeBadge({super.key, required this.score});
  final int? score;

  @override
  Widget build(BuildContext context) {
    if (score == null) return const SizedBox.shrink();
    return Semantics(
      label: 'Vibe Score $score percent: matches $score percent of your preferences',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
        ),
        child: Text('Vibe $score%', style: AppTheme.sans(size: 12, color: AppColors.gold, weight: FontWeight.w700)),
      ),
    );
  }
}

/// Single or multi-select chips built from server-provided choices.
class ChoiceChips extends StatelessWidget {
  const ChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.multi = false,
  });

  final List<({String value, String label})> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          FilterChip(
            label: Text(option.label),
            selected: selected.contains(option.value),
            showCheckmark: multi,
            labelStyle: AppTheme.sans(
              size: 13,
              color: selected.contains(option.value) ? AppColors.gold : AppColors.textLabel,
              weight: selected.contains(option.value) ? FontWeight.w600 : FontWeight.w400,
            ),
            side: BorderSide(color: selected.contains(option.value) ? AppColors.gold : AppColors.border),
            onSelected: (isOn) {
              final next = {...selected};
              if (multi) {
                isOn ? next.add(option.value) : next.remove(option.value);
              } else {
                next
                  ..clear()
                  ..addAll(isOn ? {option.value} : {});
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.optional = false});
  final String text;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text.rich(
        TextSpan(
          text: text,
          style: AppTheme.sans(size: 13, color: AppColors.textLabel, weight: FontWeight.w500),
          children: [
            if (optional) TextSpan(text: '  optional', style: AppTheme.sans(size: 12, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: destructive ? AppColors.error : AppColors.gold),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Asks for the account password (for deactivate / delete).
Future<String?> passwordDialog(BuildContext context,
    {required String title, required String message, required String confirmLabel}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PasswordDialog(title: title, message: message, confirmLabel: confirmLabel),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.title, required this.message, required this.confirmLabel});
  final String title;
  final String message;
  final String confirmLabel;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.message),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Your password'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
