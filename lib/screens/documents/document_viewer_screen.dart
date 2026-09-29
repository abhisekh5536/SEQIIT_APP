import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../models/resident_document_models.dart';
import '../../services/app_session.dart';
import '../../services/resident_documents_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/text_input_dialog.dart';
import 'widgets/document_widgets.dart';

/// Shows a document's pages. Opening it logs the view on the server; pages
/// are downloaded one at a time as they come on screen and kept only in
/// memory while this screen is open.
///
/// Pops `true` when the office verified or rejected it.
class DocumentViewerScreen extends StatefulWidget {
  final ResidentDocument document;
  final String subjectName;

  /// Show Verify / Reject (society office, pending documents only).
  final bool canReview;

  const DocumentViewerScreen({
    super.key,
    required this.document,
    required this.subjectName,
    this.canReview = false,
  });

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  final _pager = PageController();
  final Map<int, Future<Uint8List>> _bytes = {};
  List<DocumentPage> _pages = const [];
  bool _loading = true;
  String? _error;
  int _index = 0;
  bool _maskedChecked = false;
  bool _saving = false;
  late final String _watermark;

  ResidentDocument get _doc => widget.document;

  @override
  void initState() {
    super.initState();
    final who = AppSession.instance.displayName ?? 'Saqiit user';
    _watermark =
        '$who · ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())} · Saqiit';
    _open();
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pages = await ResidentDocumentsService.instance.open(_doc.id);
      if (!mounted) return;
      setState(() {
        _pages = pages;
        _bytes.clear();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ResidentDocumentsService.humanize(e);
        _loading = false;
      });
    }
  }

  Future<Uint8List> _page(int i) => _bytes.putIfAbsent(
    i,
    () => ResidentDocumentsService.instance.downloadPage(_doc.id, _pages[i]),
  );

  void _snack(String msg, {bool danger = false}) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: danger ? p.danger : null,
      ),
    );
  }

  Future<void> _decide(bool verified) async {
    String? note;
    if (!verified) {
      note = await showTextInputDialog(
        context,
        title: 'Reject ${_doc.type.label.toLowerCase()}?',
        message: 'Tell ${widget.subjectName} what to fix. They will see this.',
        hint: _doc.type == ResidentDocType.maskedAadhaar
            ? 'e.g. All 12 digits are visible — upload the masked Aadhaar'
            : 'e.g. Page 2 is missing',
        confirmLabel: 'Reject',
        maxLines: 3,
        requiredMessage: 'Give a reason',
      );
      if (note == null) return;
    }
    setState(() => _saving = true);
    try {
      await ResidentDocumentsService.instance.review(
        _doc.id,
        verified: verified,
        note: note,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(ResidentDocumentsService.humanize(e), danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reviewable =
        widget.canReview && _doc.status == ResidentDocStatus.pending;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_doc.type.label, style: const TextStyle(fontSize: 16)),
            Text(
              [
                widget.subjectName,
                if (_pages.length > 1) 'Page ${_index + 1} of ${_pages.length}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _body()),
          _details(),
          if (reviewable) _reviewBar(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                color: Colors.white54,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _open, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_pages.isEmpty) {
      return const Center(
        child: Text('No pages', style: TextStyle(color: Colors.white70)),
      );
    }
    return Stack(
      children: [
        PageView.builder(
          controller: _pager,
          itemCount: _pages.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) => FutureBuilder<Uint8List>(
            future: _page(i),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ResidentDocumentsService.humanize(snap.error!),
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: () => setState(() => _bytes.remove(i)),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final page = _pages[i];
              if (page.isPdf) {
                return PdfViewer.data(
                  snap.data!,
                  sourceName: 'resident-document-${_doc.id}-${page.pageNo}',
                );
              }
              return InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Image.memory(
                    snap.data!,
                    fit: BoxFit.contain,
                    cacheWidth: 2000,
                    gaplessPlayback: true,
                  ),
                ),
              );
            },
          ),
        ),
        Positioned.fill(child: IgnorePointer(child: _Watermark(_watermark))),
      ],
    );
  }

  Widget _details() {
    final lines = <String>[
      ?validityText(_doc),
      if (_doc.referenceNumber != null) 'Ref. ${_doc.referenceNumber}',
      if (_doc.note != null) _doc.note!,
      'Status: ${_doc.status.label}',
    ];
    return Container(
      width: double.infinity,
      color: const Color(0xFF111111),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Text(
        lines.join('  ·  '),
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }

  Widget _reviewBar() {
    final needsMaskCheck = _doc.type == ResidentDocType.maskedAadhaar;
    final canVerify = !_saving && (!needsMaskCheck || _maskedChecked);
    final palette = AppTheme.paletteFor(Theme.of(context).brightness);
    return Material(
      color: palette.canvas,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (needsMaskCheck)
                CheckboxListTile(
                  value: _maskedChecked,
                  onChanged: (v) => setState(() => _maskedChecked = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'Only the last 4 digits of the Aadhaar number are visible',
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : () => _decide(false),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.danger,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: canVerify ? () => _decide(true) : null,
                      icon: const Icon(Icons.verified_rounded),
                      label: const Text('Verify'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Repeating diagonal "who is looking, when" text over the page. It does
/// not stop a photo of the screen, but it marks every copy with its source.
class _Watermark extends StatelessWidget {
  final String text;

  const _Watermark(this.text);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, box) {
          final rows = (box.maxHeight / 110).ceil() + 2;
          return OverflowBox(
            maxWidth: box.maxWidth * 2,
            maxHeight: box.maxHeight * 2,
            child: Transform.rotate(
              angle: -math.pi / 7,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < rows * 2; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        '$text     $text',
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        softWrap: false,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.13),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.13),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
