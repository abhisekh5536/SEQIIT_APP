import 'package:flutter/material.dart';

import '../../models/resident_document_models.dart';
import '../../services/app_session.dart';
import '../../services/resident_documents_service.dart';
import '../../theme/app_theme.dart';
import '../vehicles/widgets/vehicle_parking_widgets.dart';
import 'document_viewer_screen.dart';
import 'resident_documents_screen.dart';
import 'widgets/document_widgets.dart';

/// Society office: documents to verify, agreements running out, and flats
/// with nothing on file.
class AdminDocumentsDashboard extends StatefulWidget {
  final bool showBack;

  const AdminDocumentsDashboard({super.key, this.showBack = true});

  @override
  State<AdminDocumentsDashboard> createState() =>
      _AdminDocumentsDashboardState();
}

class _AdminDocumentsDashboardState extends State<AdminDocumentsDashboard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  AdminDocumentsOverview _data = const AdminDocumentsOverview();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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
      final data = await service.fetchOverview();
      if (!mounted) return;
      setState(() {
        _data = data;
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

  Future<void> _review(AdminDocumentItem item) async {
    final id = item.documentId;
    if (id == null) return;
    try {
      final doc = await ResidentDocumentsService.instance.fetchDocument(id);
      if (doc == null || !mounted) return;
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentViewerScreen(
            document: doc,
            subjectName: item.fullName,
            canReview: true,
          ),
        ),
      );
      if (changed == true) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ResidentDocumentsService.humanize(e))),
      );
    }
  }

  Future<void> _openFlat(AdminDocumentItem item) async {
    final flatId = item.flatId;
    if (flatId == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResidentDocumentsScreen(
          flatId: flatId,
          title: item.flatLabel.isEmpty
              ? 'Flat documents'
              : 'Flat ${item.flatLabel}',
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final toVerify = 'To verify (${_data.toVerify.length})';
    final expiring = 'Expiring (${_data.expiryCount})';
    final missing = 'Missing (${_data.missingCount})';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ModuleHeader(
              title: 'Resident documents',
              subtitle: AppSession.instance.societyName,
              showBack: widget.showBack,
            ),
            SegmentedTabs(
              controller: _tabs,
              labels: [toVerify, expiring, missing],
              highlighted: {
                if (_data.toVerify.isNotEmpty) toVerify,
                if (_data.expired.isNotEmpty) expiring,
              },
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
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _list(
                          p,
                          [
                            _Group(
                              null,
                              _data.toVerify,
                              empty: const ModuleEmptyState(
                                icon: Icons.task_alt_rounded,
                                title: 'Nothing to verify',
                                message:
                                    'New uploads from residents appear here.',
                              ),
                            ),
                          ],
                          note:
                              'Every document you open is logged with your name.',
                        ),
                        _list(p, [
                          _Group('Ended', _data.expired),
                          _Group('Ending within 30 days', _data.expiring),
                        ], emptyTitle: 'No agreements running out'),
                        _list(p, [
                          _Group(
                            'Tenants without a rent agreement',
                            _data.missingRentAgreement,
                          ),
                          _Group(
                            'Owners without ownership proof',
                            _data.missingOwnership,
                          ),
                        ], emptyTitle: 'Every flat has its papers'),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(
    AppPaletteData p,
    List<_Group> groups, {
    String? note,
    String emptyTitle = 'Nothing here',
  }) {
    final allEmpty = groups.every((g) => g.items.isEmpty);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
        children: [
          if (note != null) ...[DocNote(note), const SizedBox(height: 12)],
          if (allEmpty)
            groups.first.empty ??
                ModuleEmptyState(
                  icon: Icons.task_alt_rounded,
                  title: emptyTitle,
                  message: 'Pull down to refresh.',
                )
          else
            for (final g in groups)
              if (g.items.isNotEmpty) ...[
                if (g.title != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 6),
                    child: ModuleSectionHeader(
                      title: '${g.title} (${g.items.length})',
                    ),
                  ),
                for (final item in g.items) _itemTile(p, item),
              ],
        ],
      ),
    );
  }

  Widget _itemTile(AppPaletteData p, AdminDocumentItem item) {
    final isDoc = item.documentId != null;
    final pending =
        isDoc && item.submittedAt != null && item.validUntil == null;
    final subtitle = <String>[
      if (item.flatLabel.isNotEmpty) item.flatLabel,
      if (item.type != null) item.type!.label,
      if (item.validUntil != null) 'ends ${formatDocDate(item.validUntil!)}',
      if (item.submittedAt != null && item.validUntil == null)
        'sent ${formatDocDate(item.submittedAt!)}',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.hairline),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          leading: Icon(
            item.type != null
                ? iconForDocType(item.type!)
                : Icons.folder_off_outlined,
            color: p.primary,
          ),
          title: Text(
            item.fullName,
            style: TextStyle(fontWeight: FontWeight.w700, color: p.textPrimary),
          ),
          subtitle: Text(subtitle),
          trailing: item.renewalPending
              ? DocChip('Renewal sent', p.success)
              : Icon(Icons.chevron_right_rounded, color: p.textTertiary),
          // A pending upload opens for review; everything else opens the
          // flat so the office can see (or add) what is there.
          onTap: pending ? () => _review(item) : () => _openFlat(item),
        ),
      ),
    );
  }
}

class _Group {
  final String? title;
  final List<AdminDocumentItem> items;
  final Widget? empty;

  const _Group(this.title, this.items, {this.empty});
}
