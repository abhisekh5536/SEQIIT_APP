import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/resident_document_models.dart';
import '../../services/resident_documents_service.dart';
import '../../theme/app_theme.dart';
import '../vehicles/widgets/vehicle_parking_widgets.dart';
import 'widgets/document_widgets.dart';

/// Upload a document for [subject]. Pops `true` once it is sent for review.
class DocumentUploadSheet extends StatefulWidget {
  final DocumentSubject subject;
  final DocumentCategory category;
  final ResidentDocType? initialType;

  const DocumentUploadSheet({
    super.key,
    required this.subject,
    required this.category,
    this.initialType,
  });

  static Future<bool?> show(
    BuildContext context, {
    required DocumentSubject subject,
    required DocumentCategory category,
    ResidentDocType? initialType,
  }) => showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DocumentUploadSheet(
      subject: subject,
      category: category,
      initialType: initialType,
    ),
  );

  @override
  State<DocumentUploadSheet> createState() => _DocumentUploadSheetState();
}

class _DocumentUploadSheetState extends State<DocumentUploadSheet> {
  late final List<ResidentDocType> _types = ResidentDocType.forCategory(
    widget.category,
    widget.subject.residentType,
  );
  late ResidentDocType? _type = _types.contains(widget.initialType)
      ? widget.initialType
      : _types.firstOrNull;
  final _pages = <PickedDocumentPage>[];
  final _reference = TextEditingController();
  DateTime? _from;
  DateTime? _until;
  bool _consent = false;
  bool _busy = false;
  String? _progress;
  String? _error;

  static bool get _hasCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _hasPdf => _pages.any((p) => p.isPdf);

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  void _addPage(PickedDocumentPage page) {
    setState(() {
      if (page.isPdf) _pages.clear();
      _pages.add(page);
      _error = null;
    });
  }

  Future<void> _addImages({required bool camera}) async {
    if (_hasPdf) _pages.clear();
    final room = DocumentFileCheck.maxImages - _pages.length;
    if (room <= 0) {
      setState(() => _error = 'Up to ${DocumentFileCheck.maxImages} photos');
      return;
    }
    final picker = ImagePicker();
    try {
      final List<XFile> files;
      if (camera || room == 1) {
        final one = await picker.pickImage(
          source: camera ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 2000,
          maxHeight: 2000,
          imageQuality: 85,
        );
        files = one == null ? const [] : [one];
      } else {
        files = await picker.pickMultiImage(
          maxWidth: 2000,
          maxHeight: 2000,
          imageQuality: 85,
          limit: room,
        );
      }
      for (final f in files.take(room)) {
        final bytes = await f.readAsBytes();
        final err = DocumentFileCheck.checkFile(bytes);
        final mime = DocumentFileCheck.sniffMime(bytes);
        if (err != null || mime == null || mime == 'application/pdf') {
          setState(() => _error = err ?? 'Only JPG or PNG photos');
          continue;
        }
        _addPage(PickedDocumentPage(bytes, mime));
      }
    } catch (e) {
      setState(
        () => _error = 'Could not open the ${camera ? 'camera' : 'photos'}',
      );
    }
  }

  Future<void> _addPdf() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (file == null) return;
      final size = file.lengthSync() ?? await file.length();
      if (size != null && size > DocumentFileCheck.maxBytes) {
        setState(() => _error = 'Each file must be under 10 MB');
        return;
      }
      final bytes = await file.readAsBytes();
      final err = DocumentFileCheck.checkFile(bytes);
      if (err != null ||
          DocumentFileCheck.sniffMime(bytes) != 'application/pdf') {
        setState(() => _error = err ?? 'That file is not a PDF');
        return;
      }
      _addPage(PickedDocumentPage(bytes, 'application/pdf'));
    } catch (e) {
      setState(() => _error = 'Could not open the file');
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final initial = start
        ? (_from ?? now)
        : (_until ?? (_from ?? now).add(const Duration(days: 334)));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _from = picked;
        // Most agreements run 11 months.
        _until ??= DateTime(picked.year, picked.month + 11, picked.day);
      } else {
        _until = picked;
      }
    });
  }

  Future<void> _upload() async {
    final type = _type;
    if (type == null) return;
    final pageError = DocumentFileCheck.checkPages(
      _pages.map((p) => p.mimeType).toList(),
    );
    String? error = pageError;
    if (error == null &&
        type.requiresValidity &&
        (_from == null || _until == null)) {
      error = 'Enter the start and end dates';
    }
    if (error == null &&
        _from != null &&
        _until != null &&
        _until!.isBefore(_from!)) {
      error = 'The end date is before the start date';
    }
    if (error == null && !_consent) {
      error = 'Please agree to the notice first';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ResidentDocumentsService.instance.upload(
        subject: widget.subject,
        type: type,
        pages: List.of(_pages),
        validFrom: type.requiresValidity ? _from : null,
        validUntil: type.requiresValidity ? _until : null,
        referenceNumber: _reference.text.trim().isEmpty
            ? null
            : _reference.text.trim(),
        onProgress: (done, total) {
          if (!mounted) return;
          setState(
            () => _progress = done < total
                ? 'Uploading page ${done + 1} of $total…'
                : 'Sending for review…',
          );
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _error = ResidentDocumentsService.humanize(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final type = _type;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: p.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: 'Add ${widget.category.label.toLowerCase()} document',
                subtitle:
                    '${widget.subject.fullName} · ${widget.subject.flatLabel}',
              ),
              const SizedBox(height: 16),
              if (_types.length > 1)
                DropdownButtonFormField<ResidentDocType>(
                  initialValue: type,
                  isExpanded: true,
                  decoration: _decoration(
                    p,
                    'Document',
                    Icons.description_outlined,
                  ),
                  items: [
                    for (final t in _types)
                      DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged: _busy ? null : (t) => setState(() => _type = t),
                )
              else if (type != null)
                Text(
                  type.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: p.textPrimary,
                  ),
                ),
              if (type?.help != null) ...[
                const SizedBox(height: 10),
                DocNote(type!.help!, icon: Icons.info_outline_rounded),
              ],
              const SizedBox(height: 16),
              const FieldLabel('Pages', required: true),
              const SizedBox(height: 8),
              _pagesGrid(p),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_hasCamera)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _addImages(camera: true),
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('Camera'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _addImages(camera: false),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Photos'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _addPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('PDF'),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'One PDF, or up to ${DocumentFileCheck.maxImages} photos. 10 MB per file.',
                  style: TextStyle(fontSize: 12, color: p.textTertiary),
                ),
              ),
              if (type?.requiresValidity == true) ...[
                const SizedBox(height: 16),
                const FieldLabel('Agreement period', required: true),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _dateButton('Starts', _from, start: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _dateButton('Ends', _until, start: false)),
                  ],
                ),
              ],
              if (type?.referenceLabel != null) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _reference,
                  enabled: !_busy,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.characters,
                  decoration: _decoration(
                    p,
                    type!.referenceLabel!,
                    Icons.tag_rounded,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _consentBox(p),
              if (_error != null) ...[
                const SizedBox(height: 12),
                FormError(_error!),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy || type == null ? null : _upload,
                  child: _busy
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                            Flexible(child: Text(_progress ?? 'Uploading…')),
                          ],
                        )
                      : const Text('Send for review'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pagesGrid(AppPaletteData p) {
    if (_pages.isEmpty) {
      return Container(
        height: 90,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.cardMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.hairline),
        ),
        child: Text('No pages yet', style: TextStyle(color: p.textTertiary)),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < _pages.length; i++)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 78,
                  height: 96,
                  color: p.cardMuted,
                  child: _pages[i].isPdf
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.picture_as_pdf_rounded, color: p.danger),
                            const SizedBox(height: 4),
                            Text(
                              '${(_pages[i].bytes.length / 1024 / 1024).toStringAsFixed(1)} MB',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        )
                      : Image.memory(
                          _pages[i].bytes,
                          fit: BoxFit.cover,
                          cacheWidth: 200,
                        ),
                ),
              ),
              Positioned(
                left: 4,
                bottom: 4,
                child: DocChip('${i + 1}', Colors.white),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove page',
                  onPressed: _busy
                      ? null
                      : () => setState(() => _pages.removeAt(i)),
                  icon: const Icon(Icons.cancel_rounded, size: 20),
                  color: Colors.white,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _dateButton(String label, DateTime? value, {required bool start}) {
    return OutlinedButton(
      onPressed: _busy ? null : () => _pickDate(start: start),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        alignment: Alignment.centerLeft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          Text(
            value == null ? 'Choose date' : formatDocDate(value),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _consentBox(AppPaletteData p) {
    final onBehalf = !widget.subject.isSelf;
    // A Material, not a coloured box: the checkbox tile paints its ink on
    // the nearest Material, which a coloured box would cover.
    return Material(
      color: p.cardMuted,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kDocumentNoticeText,
              style: TextStyle(fontSize: 12, color: p.textSecondary),
            ),
            CheckboxListTile(
              value: _consent,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _consent = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                onBehalf
                    ? '${widget.subject.fullName.split(' ').first} agreed to share this with the society office'
                    : 'I agree to share this with the society office',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(AppPaletteData p, String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: p.card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
