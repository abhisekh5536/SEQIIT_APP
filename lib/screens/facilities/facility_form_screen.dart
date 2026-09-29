import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/facility_models.dart';
import '../../services/facilities_service.dart';
import '../../theme/app_theme.dart';
import 'facility_categories_screen.dart';
import 'widgets/facility_widgets.dart';

/// A photo in the form's gallery: either already uploaded, or just picked.
class _GalleryItem {
  final FacilityImage? existing;
  final XFile? file;
  final Uint8List? bytes;

  const _GalleryItem.existing(FacilityImage image)
      : existing = image,
        file = null,
        bytes = null;

  const _GalleryItem.picked(XFile this.file, Uint8List this.bytes)
      : existing = null;
}

/// Admin: add or edit a facility.
class FacilityFormScreen extends StatefulWidget {
  final FacilityRecord? facility;

  const FacilityFormScreen({super.key, this.facility});

  @override
  State<FacilityFormScreen> createState() => _FacilityFormScreenState();
}

class _FacilityFormScreenState extends State<FacilityFormScreen> {
  static const _maxPhotos = 10;

  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.facility?.name);
  late final _description =
      TextEditingController(text: widget.facility?.description);
  late final _hours =
      TextEditingController(text: widget.facility?.operatingHours);
  late final _location = TextEditingController(text: widget.facility?.location);
  late final _rules = TextEditingController(text: widget.facility?.rulesText);
  late final _statusNote =
      TextEditingController(text: widget.facility?.statusNote);

  late FacilityStatus _status = widget.facility?.status ?? FacilityStatus.active;
  late String? _categoryId = widget.facility?.categoryId;
  List<FacilityCategory> _categories = [];

  late final List<_GalleryItem> _gallery = [
    for (final img in widget.facility?.images ?? const <FacilityImage>[])
      _GalleryItem.existing(img),
  ];
  final List<FacilityImage> _removed = [];

  bool _saving = false;
  String? _progress;

  bool get _isEdit => widget.facility != null;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _hours, _location, _rules, _statusNote]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final list = await FacilitiesService.instance.fetchCategories();
      if (!mounted) return;
      setState(() {
        _categories = list;
        // A deleted category leaves a dangling selection.
        if (_categoryId != null && !list.any((c) => c.id == _categoryId)) {
          _categoryId = null;
        }
      });
    } catch (_) {}
  }

  Future<void> _pickPhotos() async {
    HapticFeedback.lightImpact();
    final remaining = _maxPhotos - _gallery.length;
    if (remaining <= 0) return;

    final picked = await ImagePicker().pickMultiImage(
      imageQuality: 80,
      maxWidth: 1600,
      limit: remaining > 1 ? remaining : null,
    );
    if (picked.isEmpty) return;

    final items = <_GalleryItem>[];
    for (final f in picked.take(remaining)) {
      items.add(_GalleryItem.picked(f, await f.readAsBytes()));
    }
    if (!mounted) return;
    setState(() => _gallery.addAll(items));
    if (picked.length > remaining && mounted) {
      _snack('Only $_maxPhotos photos per facility; extra photos were skipped.');
    }
  }

  void _removePhoto(int index) {
    setState(() {
      final item = _gallery.removeAt(index);
      if (item.existing != null) _removed.add(item.existing!);
    });
  }

  void _makeCover(int index) {
    HapticFeedback.selectionClick();
    setState(() => _gallery.insert(0, _gallery.removeAt(index)));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _progress = 'Saving details…';
    });

    final service = FacilitiesService.instance;
    try {
      final id = await service.saveFacility(
        id: widget.facility?.id,
        name: _name.text,
        description: _description.text,
        categoryId: _categoryId,
        status: _status,
        statusNote: _statusNote.text,
        operatingHours: _hours.text,
        location: _location.text,
        rulesText: _rules.text,
      );

      for (final img in _removed) {
        await service.deleteImage(img);
      }

      // Gallery position is the sort order; position 0 is the cover.
      final newCount = _gallery.where((g) => g.file != null).length;
      var uploaded = 0;
      for (var i = 0; i < _gallery.length; i++) {
        final item = _gallery[i];
        if (item.existing != null) {
          if (item.existing!.sortOrder != i) {
            await service.setImageSortOrder(item.existing!.id, i);
          }
        } else {
          uploaded++;
          if (mounted) {
            setState(() => _progress = 'Uploading photo $uploaded of $newCount…');
          }
          await service.uploadImage(id, item.file!, sortOrder: i);
        }
      }

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _snack(_isEdit ? 'Facility updated' : 'Facility added');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _progress = null;
      });
      _snack('Could not save: $e');
    }
  }

  Future<void> _delete() async {
    final f = widget.facility;
    if (f == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${f.name}?'),
        content: const Text(
          'Residents will no longer see it and its photos are removed. '
          'To take it offline temporarily, set it to Maintenance or Closed instead.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _saving = true;
      _progress = 'Deleting…';
    });
    try {
      await FacilitiesService.instance.deleteFacility(f);
      if (!mounted) return;
      _snack('${f.name} deleted');
      // Out of both the form and the detail page behind it.
      Navigator.of(context).popUntil(
          (r) => r.isFirst || r.settings.name == '/facilities');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _progress = null;
      });
      _snack('Could not delete: $e');
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  InputDecoration _decoration(
    AppPaletteData p,
    String label, {
    String? hint,
    IconData? icon,
  }) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        filled: true,
        fillColor: p.card,
        alignLabelWithHint: true,
      );

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? 'Edit Facility' : 'Add Facility'),
          actions: [
            if (_isEdit)
              IconButton(
                tooltip: 'Delete',
                onPressed: _saving ? null : _delete,
                icon: Icon(Icons.delete_outline_rounded, color: p.danger),
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _buildPhotos(context, p),
              const SizedBox(height: 24),
              TextFormField(
                controller: _name,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                decoration: _decoration(p, 'Facility name *',
                    hint: 'e.g. Swimming Pool'),
                style: const TextStyle(fontWeight: FontWeight.w600),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Give the facility a name.'
                    : null,
              ),
              const SizedBox(height: 6),
              _buildCategoryField(context, p),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: _decoration(p, 'Description',
                    hint: 'What it is, what it has, who it is for'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _hours,
                decoration: _decoration(p, 'Operating hours',
                    hint: 'e.g. 6:00 AM – 10:00 PM, closed Mondays',
                    icon: Icons.schedule_rounded),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _location,
                decoration: _decoration(p, 'Location',
                    hint: 'e.g. Clubhouse, ground floor',
                    icon: Icons.place_outlined),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _rules,
                minLines: 3,
                maxLines: 10,
                textCapitalization: TextCapitalization.sentences,
                decoration: _decoration(p, 'Rules & guidelines',
                    hint: 'One rule per line\nMax 20 people\nNo outside food'),
              ),
              const SizedBox(height: 24),
              Text('Status', style: textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<FacilityStatus>(
                showSelectedIcon: false,
                segments: [
                  for (final s in FacilityStatus.values)
                    ButtonSegment(
                      value: s,
                      icon: Icon(s.icon, size: 16),
                      label: Text(s.shortLabel),
                    ),
                ],
                selected: {_status},
                onSelectionChanged: (v) {
                  HapticFeedback.selectionClick();
                  setState(() => _status = v.first);
                },
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _status.isAvailable
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextFormField(
                          controller: _statusNote,
                          maxLength: 120,
                          decoration: _decoration(p, 'Note for residents',
                              hint: 'e.g. Cleaning until Friday'),
                        ),
                      ),
              ),
              if (_isEdit &&
                  widget.facility!.status != _status) ...[
                const SizedBox(height: 4),
                Text(
                  'Residents will be notified of this status change.',
                  style: textTheme.bodySmall?.copyWith(color: p.textTertiary),
                ),
              ],
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _saving
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(_progress ?? 'Saving…'),
                      ],
                    )
                  : Text(_isEdit ? 'Save changes' : 'Add facility'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryField(BuildContext context, AppPaletteData p) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            initialValue: _categoryId,
            isExpanded: true,
            decoration: _decoration(p, 'Category', icon: Icons.category_outlined),
            items: [
              const DropdownMenuItem(value: null, child: Text('Uncategorised')),
              for (final c in _categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: IconButton.filledTonal(
            tooltip: 'Manage categories',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const FacilityCategoriesScreen()),
              );
              _loadCategories();
            },
            icon: const Icon(Icons.tune_rounded),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotos(BuildContext context, AppPaletteData p) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Photos', style: textTheme.titleSmall),
            const Spacer(),
            Text('${_gallery.length}/$_maxPhotos',
                style: textTheme.bodySmall?.copyWith(color: p.textTertiary)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'The first photo is the cover. Tap a photo to make it the cover.',
          style: textTheme.bodySmall?.copyWith(color: p.textTertiary),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 112,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < _gallery.length; i++)
                _photoTile(p, i),
              if (_gallery.length < _maxPhotos)
                InkWell(
                  onTap: _saving ? null : _pickPhotos,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 112,
                    decoration: BoxDecoration(
                      color: p.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: p.primary.withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            color: p.primary, size: 28),
                        const SizedBox(height: 6),
                        Text('Add photos',
                            style: TextStyle(
                                color: p.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _photoTile(AppPaletteData p, int index) {
    final item = _gallery[index];
    final isCover = index == 0;

    final image = item.bytes != null
        ? Image.memory(item.bytes!, fit: BoxFit.cover)
        : FacilityImageView(
            url: item.existing!.imageUrl,
            fallbackIcon: Icons.image_outlined,
            iconSize: 24,
          );

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: _saving || isCover ? null : () => _makeCover(index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 112,
            height: 112,
            child: Stack(
              fit: StackFit.expand,
              children: [
                image,
                if (isCover)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: p.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Cover',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _saving ? null : () => _removePhoto(index),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded,
                            size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
