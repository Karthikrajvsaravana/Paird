import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/widgets/paird_widgets.dart';

/// Upload, delete and choose the main profile photo.
class PhotoManager extends StatefulWidget {
  const PhotoManager({super.key, required this.photos, required this.maxPhotos, this.onChanged});
  final List<Map<String, dynamic>> photos;
  final int maxPhotos;
  final ValueChanged<List<Map<String, dynamic>>>? onChanged;

  @override
  State<PhotoManager> createState() => _PhotoManagerState();
}

class _PhotoManagerState extends State<PhotoManager> {
  late List<Map<String, dynamic>> _photos = List.of(widget.photos);
  bool _busy = false;
  String? _error;

  Future<void> _reload() async {
    final profile = await AppScope.read(context).api.myProfile();
    if (!mounted) return;
    setState(() => _photos = (profile['photos'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    widget.onChanged?.call(_photos);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _reload();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.fieldError('image') ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;
    final api = AppScope.read(context).api;
    await _run(() async {
      final bytes = await picked.readAsBytes();
      await api.uploadPhoto(bytes, picked.name);
    });
  }

  Future<void> _options(Map<String, dynamic> photo) async {
    final api = AppScope.read(context).api;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (photo['is_primary'] != true)
              ListTile(
                leading: const Icon(Icons.star_outline, color: AppColors.gold),
                title: const Text('Make main photo'),
                onTap: () => Navigator.pop(context, 'primary'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('Delete photo'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    final id = photo['id'] as int;
    if (choice == 'primary') await _run(() => api.makePrimaryPhoto(id));
    if (choice == 'delete') await _run(() => api.deletePhoto(id));
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = _photos.length < widget.maxPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            for (final photo in _photos)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _busy ? null : () => _options(photo),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MemberPhoto(url: photo['url'] as String?, name: 'You', size: 120, radius: 12),
                    if (photo['is_primary'] == true)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(6)),
                          child: Text('Main',
                              style: AppTheme.sans(size: 10, color: AppColors.background, weight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
              ),
            if (canAdd)
              Semantics(
                button: true,
                label: 'Add photo',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _busy ? null : _add,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Center(
                      child: _busy
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_a_photo_outlined, color: AppColors.gold),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Up to ${widget.maxPhotos} photos. Location data is removed from photos when you upload them. '
          'Tap a photo to make it your main photo or delete it.',
          style: AppTheme.sans(size: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }
}
