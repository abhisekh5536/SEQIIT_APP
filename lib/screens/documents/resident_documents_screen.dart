import 'package:flutter/material.dart';

import '../../models/resident_document_models.dart';
import '../../services/app_session.dart';
import '../../services/resident_documents_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/resident_widgets.dart';
import '../../widgets/text_input_dialog.dart';
import '../vehicles/widgets/vehicle_parking_widgets.dart';
import 'document_upload_sheet.dart';
import 'document_viewer_screen.dart';
import 'widgets/document_widgets.dart';

/// Documents of the people the caller may see: for a resident, their own
/// household (and, for an owner, their tenants); for the office, one flat.
/// Who appears and what they may do is decided by the server.
class ResidentDocumentsScreen extends StatefulWidget {
  /// One flat (the office, from the directory). Null: the caller's flats.
  final String? flatId;
  final String? title;
  final bool showBack;

  const ResidentDocumentsScreen({
    super.key,
    this.flatId,
    this.title,
    this.showBack = true,
  });

  @override
  State<ResidentDocumentsScreen> createState() =>
      _ResidentDocumentsScreenState();
}

class _ResidentDocumentsScreenState extends State<ResidentDocumentsScreen> {
  List<DocumentSubject> _subjects = const [];
  Map<String, List<ResidentDocument>> _docs = const {};
  final Map<String, String> _panShown = {};
  bool _loading = true;
  String? _error;

  bool get _isAdmin => AppSession.instance.isAdmin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = ResidentDocumentsService.instance;
    if (service.isOffline) {
      setState(() {
        _loading = false;
        _error = 'Documents need a connection to the server.';
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final subjects = await service.fetchSubjects(flatId: widget.flatId);
      final docs = await service.fetchDocuments(
        subjects.map((s) => s.residentId).toList(),
      );
      final byResident = <String, List<ResidentDocument>>{};
      for (final d in docs) {
        if (d.residentId == null) continue;
        byResident.putIfAbsent(d.residentId!, () => []).add(d);
      }
      if (!mounted) return;
      setState(() {
        _subjects = subjects;
        _docs = byResident;
        _error = null;
        _loading = false;
      });
      service.refreshCounts();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ResidentDocumentsService.humanize(e);
        _loading = false;
      });
    }
  }

  void _snack(String msg, {bool danger = false}) {
    if (!mounted) return;
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: danger ? p.danger : null,
      ),
    );
  }

  Future<void> _upload(
    DocumentSubject s,
    DocumentCategory c, [
    ResidentDocType? type,
  ]) async {
    final sent = await DocumentUploadSheet.show(
      context,
      subject: s,
      category: c,
      initialType: type,
    );
    if (sent == true) {
      _snack('Sent to the society office for review');
      _load();
    }
  }

  Future<void> _open(DocumentSubject s, ResidentDocument d) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentViewerScreen(
          document: d,
          subjectName: s.fullName,
          canReview: _isAdmin,
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _withdraw(ResidentDocument d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Withdraw ${d.type.label.toLowerCase()}?'),
        content: const Text(
          'The office will not review it, and its files are deleted tonight.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ResidentDocumentsService.instance.withdraw(d.id);
      _load();
    } catch (e) {
      _snack(ResidentDocumentsService.humanize(e), danger: true);
    }
  }

  Future<void> _editPan(DocumentSubject s) async {
    final pan = await showTextInputDialog(
      context,
      title: s.hasPan ? 'Change PAN' : 'Add PAN',
      message: 'Stored encrypted. Others see only the last 4 characters.',
      label: 'PAN',
      hint: 'ABCDE1234F',
      confirmLabel: 'Save',
      textCapitalization: TextCapitalization.characters,
      enableSuggestions: false,
      autocorrect: false,
      requiredMessage: 'Enter the PAN',
      validator: PanNumber.validate,
    );
    if (pan == null) return;
    try {
      await ResidentDocumentsService.instance.setPan(s.residentId, pan);
      _panShown.remove(s.residentId);
      _snack('PAN saved');
      _load();
    } catch (e) {
      _snack(ResidentDocumentsService.humanize(e), danger: true);
    }
  }

  Future<void> _revealPan(DocumentSubject s) async {
    String? reason;
    if (!s.isSelf) {
      reason = await showTextInputDialog(
        context,
        title: 'Show full PAN?',
        message:
            'This is logged with your name. ${s.fullName.split(' ').first} can see who viewed it.',
        label: 'Why do you need it?',
        hint: 'e.g. Police verification form for the tenant',
        confirmLabel: 'Show',
        maxLines: 2,
        requiredMessage: 'Give a reason',
        validator: (v) => v.length < 5 ? 'A few more words, please' : null,
      );
      if (reason == null) return;
    }
    try {
      final pan = await ResidentDocumentsService.instance.revealPan(
        s.residentId,
        reason: reason,
      );
      if (!mounted) return;
      setState(() => _panShown[s.residentId] = pan);
      // Back to masked after half a minute.
      Future.delayed(const Duration(seconds: 30), () {
        if (mounted) setState(() => _panShown.remove(s.residentId));
      });
    } catch (e) {
      _snack(ResidentDocumentsService.humanize(e), danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ModuleHeader(
              title: widget.title ?? 'Documents',
              subtitle: widget.flatId == null
                  ? 'Agreements, ID and ownership proofs'
                  : AppSession.instance.societyName,
              showBack: widget.showBack,
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? ModuleEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Could not load',
                      message: _error!,
                      actionLabel: 'Retry',
                      onAction: _load,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                        children: [
                          DocNote(
                            _isAdmin
                                ? 'Every document you open and every PAN you view is logged with your name.'
                                : 'Only the person, the society office and — for tenancy papers — the flat\'s owner can see these. Every view is logged. They are deleted 12 months after the person moves out.',
                          ),
                          const SizedBox(height: 12),
                          if (_subjects.isEmpty)
                            const ModuleEmptyState(
                              icon: Icons.folder_off_outlined,
                              title: 'No one to show',
                              message:
                                  'Documents appear here once you are linked to a flat.',
                            )
                          else
                            for (final s in _subjects) _personCard(p, s),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _personCard(AppPaletteData p, DocumentSubject s) {
    final docs = _docs[s.residentId] ?? const <ResidentDocument>[];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ResidentAvatar(initials: s.initials, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.fullName,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        DocChip(s.roleLabel, p.primary),
                        if (s.flatLabel.isNotEmpty)
                          DocChip(s.flatLabel, p.textSecondary),
                        if (s.isSelf) DocChip('You', p.success),
                        if (!s.isActive) DocChip('Moved out', p.textTertiary),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          for (final c in s.categories) _section(p, s, c, docs),
        ],
      ),
    );
  }

  Widget _section(
    AppPaletteData p,
    DocumentSubject s,
    DocumentCategory c,
    List<ResidentDocument> all,
  ) {
    final docs = all.where((d) => d.type.category == c && d.isVisible).toList();
    final current = docs
        .where((d) => d.isCurrent || d.status == ResidentDocStatus.rejected)
        .where(
          (d) =>
              d.status != ResidentDocStatus.rejected ||
              // A rejection stops mattering once something newer was sent.
              !docs.any(
                (n) =>
                    n.type == d.type &&
                    n.isCurrent &&
                    n.createdAt.isAfter(d.createdAt),
              ),
        )
        .toList();
    final history = docs.where((d) => !current.contains(d)).toList();
    final canOpen = s.canOpen(c);
    final canUpload = s.canUpload(c);

    final missing = <ResidentDocType>[
      if (c == DocumentCategory.tenancy &&
          !docs.any(
            (d) => d.type == ResidentDocType.rentAgreement && d.isCurrent,
          ))
        ResidentDocType.rentAgreement,
      if (c == DocumentCategory.ownership && !docs.any((d) => d.isCurrent))
        ResidentDocType.saleDeed,
      if (c == DocumentCategory.identity &&
          !docs.any(
            (d) => d.type == ResidentDocType.maskedAadhaar && d.isCurrent,
          ))
        ResidentDocType.maskedAadhaar,
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w800,
                    color: p.textTertiary,
                  ),
                ),
              ),
              if (canUpload)
                TextButton.icon(
                  onPressed: () => _upload(s, c),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          if (c == DocumentCategory.identity) _idNumbers(p, s),
          for (final d in current)
            DocumentTile(
              document: d,
              onOpen: canOpen && d.hasFiles ? () => _open(s, d) : null,
              onWithdraw: d.status == ResidentDocStatus.pending && canUpload
                  ? () => _withdraw(d)
                  : null,
            ),
          for (final t in missing) _missingRow(p, s, c, t, canUpload),
          if (history.isNotEmpty)
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'Older (${history.length})',
                  style: TextStyle(fontSize: 13, color: p.textSecondary),
                ),
                children: [
                  for (final d in history)
                    DocumentTile(
                      document: d,
                      onOpen: canOpen && d.hasFiles ? () => _open(s, d) : null,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _missingRow(
    AppPaletteData p,
    DocumentSubject s,
    DocumentCategory c,
    ResidentDocType t,
    bool canUpload,
  ) {
    final optional = t == ResidentDocType.maskedAadhaar;
    final color = optional ? p.textTertiary : p.warning;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            optional
                ? Icons.add_circle_outline_rounded
                : Icons.error_outline_rounded,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(switch (t) {
              ResidentDocType.rentAgreement => 'No rent agreement yet',
              ResidentDocType.saleDeed => 'No ownership proof yet',
              _ => 'Masked Aadhaar not added (optional)',
            }, style: TextStyle(fontSize: 13, color: p.textSecondary)),
          ),
          if (canUpload)
            TextButton(
              onPressed: () => _upload(s, c, t),
              child: const Text('Upload'),
            ),
        ],
      ),
    );
  }

  Widget _idNumbers(AppPaletteData p, DocumentSubject s) {
    final shown = _panShown[s.residentId];
    final canEditPan = s.canUploadIdentity;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: p.cardMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _numberRow(
            p,
            'Aadhaar',
            s.aadharLast4 == null || s.aadharLast4!.isEmpty
                ? 'Not given'
                : '•••• •••• ${s.aadharLast4}',
            const [],
          ),
          _numberRow(p, 'PAN', shown ?? PanNumber.mask(s.panLast4), [
            if (s.hasPan && s.canRevealPan)
              TextButton(
                onPressed: shown != null
                    ? () => setState(() => _panShown.remove(s.residentId))
                    : () => _revealPan(s),
                child: Text(shown != null ? 'Hide' : 'Show'),
              ),
            if (canEditPan)
              TextButton(
                onPressed: () => _editPan(s),
                child: Text(s.hasPan ? 'Change' : 'Add'),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _numberRow(
    AppPaletteData p,
    String label,
    String value,
    List<Widget> actions,
  ) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: p.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: p.textPrimary,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
