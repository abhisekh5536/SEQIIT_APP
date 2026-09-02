import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/visitor_models.dart';
import '../../services/app_session.dart';
import '../../services/visitors_service.dart';
import '../../theme/app_theme.dart';
import 'widgets/visitor_card.dart';
import 'widgets/visitor_timeline.dart';

class VisitorDetailScreen extends StatefulWidget {
  final String visitorId;

  const VisitorDetailScreen({super.key, required this.visitorId});

  @override
  State<VisitorDetailScreen> createState() => _VisitorDetailScreenState();
}

class _VisitorDetailScreenState extends State<VisitorDetailScreen> {
  VisitorRecord? _visitor;
  List<VisitorStatusHistoryRecord> _history = [];
  List<VisitorGroupMember> _groupMembers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        VisitorsService.instance.fetchVisitorDetail(widget.visitorId),
        VisitorsService.instance.fetchVisitorHistory(widget.visitorId),
        VisitorsService.instance.fetchGroupMembers(widget.visitorId),
      ]);

      if (mounted) {
        setState(() {
          _visitor = results[0] as VisitorRecord?;
          _history = results[1] as List<VisitorStatusHistoryRecord>;
          _groupMembers = results[2] as List<VisitorGroupMember>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: p.card,
                      side: BorderSide(color: p.hairline),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Visitor Details',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_visitor != null)
                    VisitorStatusBadge(status: _visitor!.status),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _visitor == null
                      ? _buildNotFound(p, textTheme)
                      : RefreshIndicator(
                          onRefresh: _loadDetail,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                            children: [
                              _buildInfoCard(p, textTheme),
                              const SizedBox(height: 14),
                              if (_visitor!.isPreApproved &&
                                  _visitor!.approvalCode != null)
                                ...[
                                  _buildApprovalCodeCard(p, textTheme),
                                  const SizedBox(height: 14),
                                ],
                              if (_visitor!.isPending) ...[
                                _buildApprovalActions(p, textTheme),
                                const SizedBox(height: 14),
                              ],
                              if (_groupMembers.isNotEmpty) ...[
                                _buildGroupMembersList(p, textTheme),
                                const SizedBox(height: 14),
                              ],
                              if (_visitor!.canCancel &&
                                  !AppSession.instance.isAdmin) ...[
                                _buildCancelButton(p),
                                const SizedBox(height: 14),
                              ],
                              VisitorTimeline(history: _history),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotFound(AppPaletteData p, TextTheme textTheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: p.textTertiary),
          const SizedBox(height: 12),
          Text('Visitor not found',
              style: textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildInfoCard(AppPaletteData p, TextTheme textTheme) {
    final v = _visitor!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.hairline),
        boxShadow: [
          BoxShadow(
            color: p.shadow.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Photo
              _buildPhotoAvatar(p, v, size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.visitorName,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(v.category.icon,
                            size: 14, color: v.category.color),
                        const SizedBox(width: 4),
                        Text(
                          v.category.label,
                          style: TextStyle(
                            color: v.category.color,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: p.cardMuted,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            v.entryType.label,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: p.hairline, height: 1),
          const SizedBox(height: 14),

          // Detail rows
          if (v.visitorPhone != null && v.visitorPhone!.isNotEmpty)
            _infoRow(p, Icons.phone_outlined, 'Phone', v.visitorPhone!),
          if (v.companyOrContext != null && v.companyOrContext!.isNotEmpty)
            _infoRow(p, Icons.business_outlined, 'Company / Context',
                v.companyOrContext!),
          if (v.vehicleNumber != null && v.vehicleNumber!.isNotEmpty)
            _infoRow(p, Icons.directions_car_outlined, 'Vehicle',
                v.vehicleNumber!),
          _infoRow(p, Icons.apartment_rounded, 'Flat', v.flatDisplay),
          _infoRow(p, Icons.schedule_rounded, 'Created', v.formattedCreatedAt),
          if (v.validityDisplay != null)
            _infoRow(p, Icons.event_rounded, 'Validity', v.validityDisplay!),
          if (v.deniedReason != null && v.deniedReason!.isNotEmpty)
            _infoRow(p, Icons.block_rounded, 'Denial Reason',
                v.deniedReason!, color: p.danger),
          if (v.checkedInAt != null)
            _infoRow(p, Icons.login_rounded, 'Checked In',
                v.checkedInAt.toString().substring(0, 19)),
          if (v.checkedOutAt != null)
            _infoRow(p, Icons.logout_rounded, 'Checked Out',
                v.checkedOutAt.toString().substring(0, 19)),
        ],
      ),
    );
  }

  Widget _infoRow(
    AppPaletteData p,
    IconData icon,
    String label,
    String value, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? p.textTertiary),
          const SizedBox(width: 10),
          Text(
            '$label:',
            style: TextStyle(
              color: p.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: color ?? p.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalCodeCard(AppPaletteData p, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [p.primary.withValues(alpha: 0.08), p.secondary.withValues(alpha: 0.08)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.qr_code_2_rounded, size: 20, color: p.primary),
              const SizedBox(width: 8),
              Text(
                'Approval Code',
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: p.primary,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: _visitor!.approvalCode!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Code copied!')),
                  );
                },
                child: Row(
                  children: [
                    Icon(Icons.copy_rounded, size: 14, color: p.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Copy',
                      style: TextStyle(
                        color: p.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _visitor!.approvalCode!,
            style: textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
              fontFamily: 'monospace',
              color: p.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Share this code with the visitor for gate entry',
            style: textTheme.bodySmall?.copyWith(
              color: p.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalActions(AppPaletteData p, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pending_actions_rounded,
                  size: 20, color: p.warning),
              const SizedBox(width: 8),
              Text(
                'Action Required',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: p.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'A visitor is waiting at the gate. Please approve or deny entry.',
            style: textTheme.bodySmall?.copyWith(
              color: p.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showDenyDialog(),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Deny'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.danger,
                    side: BorderSide(color: p.danger),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => _approve(),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Approve'),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.success,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupMembersList(AppPaletteData p, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              Icon(Icons.groups_rounded, size: 20, color: p.primary),
              const SizedBox(width: 8),
              Text(
                'Group Members (${_groupMembers.length})',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(_groupMembers.length, (i) {
            final member = _groupMembers[i];
            return Padding(
              padding: EdgeInsets.only(
                  bottom: i < _groupMembers.length - 1 ? 8 : 0),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: p.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: p.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.guestName,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (member.guestPhone != null &&
                            member.guestPhone!.isNotEmpty)
                          Text(
                            member.guestPhone!,
                            style: TextStyle(
                              color: p.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCancelButton(AppPaletteData p) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _cancel,
        icon: Icon(Icons.cancel_outlined, size: 18, color: p.danger),
        label: Text(
          'Cancel Pre-Approval',
          style: TextStyle(color: p.danger),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: p.danger.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoAvatar(AppPaletteData p, VisitorRecord v, {double size = 48}) {
    if (v.visitorPhotoUrl != null && v.visitorPhotoUrl!.isNotEmpty) {
      final url = v.visitorPhotoUrl!;
      if (url.startsWith('data:image')) {
        try {
          final comma = url.indexOf(',');
          final b64 = comma != -1 ? url.substring(comma + 1) : url;
          final bytes = base64Decode(b64);
          return ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.25),
            child: Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _defaultAvatar(p, v, size: size),
            ),
          );
        } catch (_) {}
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.25),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultAvatar(p, v, size: size),
        ),
      );
    }
    return _defaultAvatar(p, v, size: size);
  }

  Widget _defaultAvatar(AppPaletteData p, VisitorRecord v,
      {double size = 48}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: v.category.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Icon(v.category.icon, color: v.category.color, size: size * 0.4),
    );
  }

  Future<void> _approve() async {
    try {
      await VisitorsService.instance.respondToVisitorRequest(
        visitorId: widget.visitorId,
        action: 'approved',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Visitor approved! ✅'),
            backgroundColor:
                AppTheme.paletteFor(Theme.of(context).brightness).success,
          ),
        );
        _loadDetail();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showDenyDialog() {
    final reasonCtrl = TextEditingController();
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deny Visitor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please provide a reason for denying entry.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Reason for denial',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (reasonCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Reason is required'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                await VisitorsService.instance.respondToVisitorRequest(
                  visitorId: widget.visitorId,
                  action: 'denied',
                  deniedReason: reasonCtrl.text.trim(),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Visitor denied'),
                      backgroundColor: p.danger,
                    ),
                  );
                  _loadDetail();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.redAccent),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: p.danger),
            child: const Text('Deny'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Pre-Approval'),
        content: const Text(
            'Are you sure you want to cancel this pre-approval? The approval code will no longer be valid.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor:
                  AppTheme.paletteFor(Theme.of(context).brightness).danger,
            ),
            child: const Text('Cancel It'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await VisitorsService.instance.cancelPreApproval(widget.visitorId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pre-approval cancelled')),
        );
        _loadDetail();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }
}
