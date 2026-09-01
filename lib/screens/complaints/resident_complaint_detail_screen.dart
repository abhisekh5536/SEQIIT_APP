import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/complaint_models.dart';
import '../../services/complaints_service.dart';
import '../../theme/app_theme.dart';
import 'widgets/complaint_timeline_view.dart';

class ResidentComplaintDetailScreen extends StatefulWidget {
  final String complaintId;

  const ResidentComplaintDetailScreen({super.key, required this.complaintId});

  @override
  State<ResidentComplaintDetailScreen> createState() => _ResidentComplaintDetailScreenState();
}

class _ResidentComplaintDetailScreenState extends State<ResidentComplaintDetailScreen> {
  bool _loading = true;
  String? _error;
  ComplaintRecord? _complaint;
  List<ComplaintStatusHistoryRecord> _history = [];
  bool _processingAction = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final complaint = await ComplaintsService.instance.fetchComplaintDetail(widget.complaintId);
      final history = await ComplaintsService.instance.fetchComplaintHistory(widget.complaintId);

      if (mounted) {
        setState(() {
          _complaint = complaint;
          _history = history;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load details: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _confirmFixed() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Resolution'),
        content: const Text(
          'Are you satisfied that this issue has been resolved?\n\nThis will mark the complaint as Closed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
            child: const Text('Confirm Fixed'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _processingAction = true);
    HapticFeedback.mediumImpact();

    try {
      await ComplaintsService.instance.updateStatus(
        complaintId: widget.complaintId,
        newStatus: ComplaintStatus.closed,
        note: 'Resident confirmed issue is resolved',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complaint closed successfully. Thank you for your feedback!'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
        _loadDetails();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processingAction = false);
    }
  }

  Future<void> _markNotFixed() async {
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Issue Not Fixed?'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Please explain what is still unresolved. This will reopen the complaint and notify the society administration.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'e.g. The leak started again this morning...',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a reason';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Reopen Complaint'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _processingAction = true);
    HapticFeedback.mediumImpact();

    try {
      await ComplaintsService.instance.updateStatus(
        complaintId: widget.complaintId,
        newStatus: ComplaintStatus.reopened,
        note: noteController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complaint reopened. The admin queue has been updated.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        _loadDetails();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reopen complaint: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processingAction = false);
    }
  }

  void _viewFullPhoto(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  },
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Complaint Details', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: p.canvas,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context, true),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: p.primary))
            : _error != null || _complaint == null
                ? _buildErrorView(context, p, textTheme)
                : _buildContent(context, _complaint!, p, textTheme),
      ),
      bottomNavigationBar: (_complaint != null && _complaint!.isResolved)
          ? _buildResolutionActionBar(context, p, textTheme)
          : null,
    );
  }

  Widget _buildContent(
    BuildContext context,
    ComplaintRecord item,
    AppPaletteData p,
    TextTheme textTheme,
  ) {
    final cat = item.category;
    final status = item.status;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        // Resolution Action Banner at top if resolved
        if (item.isResolved) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF93C5FD)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.task_alt_rounded, color: Color(0xFF2563EB), size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Action Required: Please Confirm Resolution',
                      style: textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF1E3A8A),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'The society office has resolved this complaint. Please verify if the issue was fixed properly and choose an action below.',
                  style: textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF1E40AF),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Main Summary Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: p.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: cat.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(cat.icon, size: 14, color: cat.color),
                        const SizedBox(width: 5),
                        Text(
                          cat.label,
                          style: TextStyle(
                            color: cat.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  _buildStatusBadge(status),
                ],
              ),
              const SizedBox(height: 14),

              Text(
                item.title,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: p.textPrimary,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),

              if (item.flatNumber != null)
                Row(
                  children: [
                    Icon(Icons.home_work_outlined, size: 16, color: p.textTertiary),
                    const SizedBox(width: 6),
                    Text(
                      item.flatDisplay,
                      style: textTheme.bodyMedium?.copyWith(
                        color: p.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 14),

              if (item.description != null && item.description!.trim().isNotEmpty) ...[
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text(
                  'Description',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: p.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.description!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: p.textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Photo attachment if present
              if (item.photoUrl != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Attachment',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: p.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _viewFullPhoto(item.photoUrl!),
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          item.photoUrl!,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 100,
                            color: p.cardMuted,
                            child: const Center(child: Text('Could not load photo')),
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_in_rounded, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Tap to expand',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Metadata grid
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Raised on', style: textTheme.bodySmall?.copyWith(color: p.textTertiary, fontSize: 11)),
                        const SizedBox(height: 2),
                        Text(
                          item.formattedCreatedAt,
                          style: textTheme.bodySmall?.copyWith(color: p.textPrimary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  if (item.assignedTo != null && item.assignedTo!.trim().isNotEmpty) ...[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Assigned To', style: textTheme.bodySmall?.copyWith(color: p.textTertiary, fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(
                            item.assignedTo!,
                            style: textTheme.bodySmall?.copyWith(color: p.textPrimary, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Prominent Admin Note Card if exists
        if (item.adminNotes != null && item.adminNotes!.trim().isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7).withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.admin_panel_settings_rounded, size: 18, color: Color(0xFFD97706)),
                    SizedBox(width: 8),
                    Text(
                      'Latest Admin Note',
                      style: TextStyle(
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.adminNotes!,
                  style: const TextStyle(
                    color: Color(0xFF78350F),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Audit Trail Section
        Text(
          'Status & Activity Timeline',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        ComplaintTimelineView(history: _history),
      ],
    );
  }

  Widget _buildStatusBadge(ComplaintStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: status.foreground, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              color: status.foreground,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResolutionActionBar(
    BuildContext context,
    AppPaletteData p,
    TextTheme textTheme,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: p.card,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _processingAction ? null : _markNotFixed,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFDC2626)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: const Text('Not Fixed', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _processingAction ? null : _confirmFixed,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.check_circle_rounded, size: 18),
              label: const Text('Confirm Fixed', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, AppPaletteData p, TextTheme textTheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: p.danger),
            const SizedBox(height: 16),
            Text('Complaint Not Found', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unable to find this complaint record.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(backgroundColor: p.primary),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
}
