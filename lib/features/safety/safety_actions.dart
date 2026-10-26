import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme/app_theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/models.dart';
import '../../shared/widgets/paird_widgets.dart';

/// Confirm and block a member. Returns true if blocked.
Future<bool> blockMember(BuildContext context, {required int userId, required String name}) async {
  final api = AppScope.read(context).api;
  final ok = await confirmDialog(
    context,
    title: 'Block $name?',
    message: 'They won’t be able to see your profile, send you interests or message you. '
        'Any match or pending interest between you will end. They won’t be told.',
    confirmLabel: 'Block',
    destructive: true,
  );
  if (!ok) return false;
  try {
    await api.block(userId);
    if (context.mounted) showSnack(context, '$name has been blocked.');
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showSnack(context, e.message);
    return false;
  }
}

/// Report sheet. Returns true if a report was submitted with "block" ticked.
Future<bool> reportMember(BuildContext context, {required int userId, required String name, int? messageId}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReportSheet(userId: userId, name: name, messageId: messageId),
  );
  return result ?? false;
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.userId, required this.name, this.messageId});
  final int userId;
  final String name;
  final int? messageId;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  late final Future<List<ChoiceOption>> _reasons = AppScope.read(context).api.reportReasons();
  final _details = TextEditingController();
  String? _reason;
  bool _block = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null || _busy) {
      setState(() => _error = 'Please choose a reason.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).api.report(
            widget.userId,
            _reason!,
            details: _details.text.trim(),
            messageId: widget.messageId,
            block: _block,
          );
      if (!mounted) return;
      showSnack(context, 'Thanks — our team will review your report.');
      Navigator.pop(context, _block);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: FutureBuilder<List<ChoiceOption>>(
            future: _reasons,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return snapshot.hasError
                    ? const ErrorView(message: 'Could not load report reasons.')
                    : const SizedBox(height: 120, child: LoadingView());
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Report ${widget.name}', style: AppTheme.serif(size: 28)),
                  const SizedBox(height: 4),
                  Text('Reports are confidential.', style: AppTheme.sans(size: 13)),
                  const SizedBox(height: 12),
                  if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 8)],
                  RadioGroup<String>(
                    groupValue: _reason,
                    onChanged: (v) => setState(() => _reason = v),
                    child: Column(
                      children: [
                        for (final r in snapshot.data!)
                          RadioListTile<String>(contentPadding: EdgeInsets.zero, value: r.value, title: Text(r.label)),
                      ],
                    ),
                  ),
                  TextField(
                    controller: _details,
                    maxLines: 3,
                    maxLength: 1000,
                    decoration: const InputDecoration(hintText: 'Anything else we should know? (optional)'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _block,
                    title: Text('Also block ${widget.name}'),
                    onChanged: (v) => setState(() => _block = v ?? false),
                  ),
                  const SizedBox(height: 8),
                  GoldButton(label: 'Submit report', busy: _busy, onPressed: _submit),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
