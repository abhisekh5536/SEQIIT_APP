import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/complaint_models.dart';
import '../../services/complaints_service.dart';
import '../../theme/app_theme.dart';
import 'widgets/complaint_timeline_view.dart';

class AdminComplaintDetailScreen extends StatefulWidget {
  final String complaintId;

  const AdminComplaintDetailScreen({super.key, required this.complaintId});

  @override
  State<AdminComplaintDetailScreen> createState() => _AdminComplaintDetailScreenState();
}

class _AdminComplaintDetailScreenState extends State<AdminComplaintDetailScreen> {
  bool _loading = true;
  String? _error;
  ComplaintRecord? _complaint;
  List<ComplaintStatusHistoryRecord> _history = [];
  bool _saving = false;

  late TextEditingController _assigneeController;
  late TextEditingController _noteController;
  ComplaintPriority _selectedPriority = ComplaintPriority.medium;

  @override
  void initState() {
    super.initState();
    _assigneeController = TextEditingController();
    _noteController = TextEditingController();
    _loadDetails();
  }

  @override
  void dispose() {
    _assigneeController.dispose();
    _noteController.dispose();
    super.dispose();
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
          if (complaint != null) {
            _assigneeController.text = complaint.assignedTo ?? '';
            _selectedPriority = complaint.priority;
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load complaint details: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _changeStatus(ComplaintStatus newStatus) async {
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change Status to ${newStatus.label}'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Move this complaint to ${newStatus.label}? Add a note for the resident below.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: noteController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: newStatus == ComplaintStatus.resolved
                      ? 'e.g. Issue inspected and fixed by plumber.'
                      : 'e.g. Assigned technician Ramesh, will visit at 4 PM.',
                  border: const OutlineInputBorder(),
                ),
                validator: (val) {
                  if (newStatus == ComplaintStatus.resolved && (val == null || val.trim().isEmpty)) {
                    return 'Please enter a resolution note';
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
            style: FilledButton.styleFrom(backgroundColor: newStatus.foreground),
            child: Text('Set to ${newStatus.label}'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _saving = true);
    HapticFeedback.mediumImpact();

    try {
      await ComplaintsService.instance.updateStatus(
        complaintId: widget.complaintId,
        newStatus: newStatus,
        note: noteController.text.trim(),
        assignedTo: _assigneeController.text.trim(),
        priority: _selectedPriority,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to ${newStatus.label}'),
            backgroundColor: const Color(0xFF10B981),
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
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAdminDetails() async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();

    try {
      await ComplaintsService.instance.updateAdminDetails(
        complaintId: widget.complaintId,
        assignedTo: _assigneeController.text.trim(),
        priority: _selectedPriority,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      );

      if (mounted) {
        _noteController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Details saved successfully'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        _loadDetails();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save details: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
        title: const Text('Complaint Management', style: TextStyle(fontWeight: FontWeight.w800)),
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
    final isSecurity = item.isSecurity;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        // Security Alert Banner
        if (isSecurity) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_rounded, color: Color(0xFFDC2626), size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SECURITY COMPLAINT',
                        style: TextStyle(
                          color: Color(0xFFB91C1C),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'This complaint involves security or safety and should be attended to promptly.',
                        style: TextStyle(color: Color(0xFF991B1B), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Reopened Notice if applicable
        if (item.isReopened) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF87171)),
            ),
            child: Row(
              children: [
                const Icon(Icons.replay_rounded, color: Color(0xFFDC2626), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Resident Reopened this Complaint',
                        style: TextStyle(
                          color: Color(0xFFB91C1C),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'The resident indicated that previous work was not satisfactory or needs attention.',
                        style: textTheme.bodySmall?.copyWith(color: const Color(0xFF991B1B), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Resident Contact Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: p.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(Icons.person_rounded, color: p.primary, size: 24),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.residentName ?? 'Resident',
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.flatDisplay,
                      style: textTheme.bodySmall?.copyWith(color: p.primary, fontWeight: FontWeight.w700),
                    ),
                    if (item.residentPhone != null && item.residentPhone!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Phone: ${item.residentPhone!}',
                        style: textTheme.bodySmall?.copyWith(color: p.textTertiary, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Complaint Information Card
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
                  style: textTheme.bodyMedium?.copyWith(color: p.textPrimary, height: 1.4),
                ),
                const SizedBox(height: 8),
              ],

              // Photo Attachment
              if (item.photoUrl != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Resident Photo Attachment',
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

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Created Date', style: textTheme.bodySmall?.copyWith(color: p.textTertiary, fontSize: 11)),
                        const SizedBox(height: 2),
                        Text(item.formattedCreatedAt, style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  if (item.resolvedAt != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Resolved Date', style: textTheme.bodySmall?.copyWith(color: p.textTertiary, fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(item.formattedResolvedAt!, style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Admin Action & Assignment Panel
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
              Text(
                'Admin Management Panel',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),

              // Status transition quick actions
              Text(
                'Update Status',
                style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 8),

              if (status == ComplaintStatus.closed)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 18),
                      SizedBox(width: 8),
                      Text(
                        'This complaint is Closed and verified by resident.',
                        style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    if (status != ComplaintStatus.inProgress)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : () => _changeStatus(ComplaintStatus.inProgress),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFD97706),
                            side: const BorderSide(color: Color(0xFFD97706)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.timelapse_rounded, size: 16),
                          label: const Text('In Progress', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        ),
                      ),
                    if (status != ComplaintStatus.inProgress && status != ComplaintStatus.resolved)
                      const SizedBox(width: 8),
                    if (status != ComplaintStatus.resolved)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving ? null : () => _changeStatus(ComplaintStatus.resolved),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.task_alt_rounded, size: 16),
                          label: const Text('Mark Resolved', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Assigned To & Priority
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Assigned Staff', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 12)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _assigneeController,
                          decoration: InputDecoration(
                            hintText: 'e.g. Ramesh (Plumber)',
                            fillColor: p.cardMuted,
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.hairline)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.hairline)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Priority', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 12)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: p.cardMuted,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: p.hairline),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<ComplaintPriority>(
                              value: _selectedPriority,
                              isExpanded: true,
                              items: ComplaintPriority.values.map((pr) {
                                return DropdownMenuItem(
                                  value: pr,
                                  child: Text(pr.label, style: TextStyle(color: pr.color, fontWeight: FontWeight.w700, fontSize: 12)),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedPriority = val);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Add Admin Note
              Text('Add Note / Log Update', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: _noteController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Write a note visible to resident & audit timeline...',
                  fillColor: p.cardMuted,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.hairline)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.hairline)),
                ),
              ),
              const SizedBox(height: 14),

              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveAdminDetails,
                  style: FilledButton.styleFrom(
                    backgroundColor: p.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text('Save Details & Note', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Activity & Status Timeline
        Text(
          'Activity & Audit Timeline',
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
            Text(_error ?? '', textAlign: TextAlign.center, style: textTheme.bodySmall?.copyWith(color: p.textSecondary)),
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
