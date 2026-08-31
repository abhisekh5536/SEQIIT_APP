import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/db_models.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';

class AdminApprovalsScreen extends StatefulWidget {
  const AdminApprovalsScreen({super.key});

  @override
  State<AdminApprovalsScreen> createState() => _AdminApprovalsScreenState();
}

class _AdminApprovalsScreenState extends State<AdminApprovalsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  String? _error;
  List<ResidentJoinRequest> _allRequests = [];

  final _processingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    final societyId = AppSession.instance.societyId;
    if (societyId == null) {
      setState(() {
        _loading = false;
        _error = 'No society associated with this admin account.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await Supabase.instance.client
          .from('resident_join_requests')
          .select('*, societies(name), flats(flat_number, blocks(name))')
          .eq('society_id', societyId)
          .order('created_at', ascending: false);

      final list = (res as List).cast<Map<String, dynamic>>().map(ResidentJoinRequest.fromMap).toList();

      setState(() {
        _allRequests = list;
        _loading = false;
      });
      await AppSession.instance.refreshAdminApprovalsCount();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load requests: $e';
      });
    }
  }

  Future<void> _approve(ResidentJoinRequest req) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Request'),
        content: Text(
          'Approve ${req.fullName} as ${req.roleLabel} for ${req.blockName ?? ''} Flat ${req.flatNumber ?? ''}?\n\nThis will activate their resident profile and mark the flat as occupied.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _processingIds.add(req.id));
    HapticFeedback.mediumImpact();

    try {
      final res = await Supabase.instance.client.rpc(
        'approve_resident_join_request',
        params: {'p_request_id': req.id},
      );

      final map = res is Map ? res : {};
      if (map['success'] == false) {
        throw map['error'] ?? 'Approval failed';
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${req.fullName} has been approved as an active resident!'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error approving request: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _processingIds.remove(req.id));
    }
  }

  Future<void> _reject(ResidentJoinRequest req) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Decline ${req.fullName}\'s request for Flat ${req.flatNumber ?? ''}?'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for rejection (optional)',
                hintText: 'e.g. Unit already allotted, verification failed',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final reason = reasonController.text.trim();
    setState(() => _processingIds.add(req.id));
    HapticFeedback.lightImpact();

    try {
      final res = await Supabase.instance.client.rpc(
        'reject_resident_join_request',
        params: {
          'p_request_id': req.id,
          'p_reason': reason.isNotEmpty ? reason : null,
        },
      );

      final map = res is Map ? res : {};
      if (map['success'] == false) {
        throw map['error'] ?? 'Rejection failed';
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request declined.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error rejecting request: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _processingIds.remove(req.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    final pending = _allRequests.where((r) => r.isPending).toList();
    final approved = _allRequests.where((r) => r.isApproved).toList();
    final rejected = _allRequests.where((r) => r.isRejected || r.isCancelled).toList();

    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: const Text('Resident Approvals', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: p.canvas,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadRequests,
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: p.primary,
          unselectedLabelColor: p.textTertiary,
          indicatorColor: p.primary,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Pending'),
                  if (pending.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE68A00),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${pending.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(text: 'Approved (${approved.length})'),
            Tab(text: 'Rejected (${rejected.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 48, color: p.danger),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center, style: textTheme.bodyLarge),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _loadRequests, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildRequestsList(p, pending, 'No pending approval requests.'),
                    _buildRequestsList(p, approved, 'No approved requests yet.'),
                    _buildRequestsList(p, rejected, 'No rejected requests.'),
                  ],
                ),
    );
  }

  Widget _buildRequestsList(AppPaletteData p, List<ResidentJoinRequest> list, String emptyMessage) {
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox_rounded, size: 48, color: p.textTertiary),
              const SizedBox(height: 12),
              Text(
                emptyMessage,
                style: TextStyle(color: p.textSecondary, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final req = list[index];
          return _buildRequestCard(p, req);
        },
      ),
    );
  }

  Widget _buildRequestCard(AppPaletteData p, ResidentJoinRequest req) {
    final isProcessing = _processingIds.contains(req.id);
    final flatStr = '${req.blockName != null ? '${req.blockName} · ' : ''}Flat ${req.flatNumber ?? ''}';

    Color badgeBg;
    Color badgeText;
    if (req.isPending) {
      badgeBg = const Color(0xFFE68A00).withValues(alpha: 0.12);
      badgeText = const Color(0xFFE68A00);
    } else if (req.isApproved) {
      badgeBg = const Color(0xFF10B981).withValues(alpha: 0.12);
      badgeText = const Color(0xFF10B981);
    } else {
      badgeBg = p.danger.withValues(alpha: 0.12);
      badgeText = p.danger;
    }

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
        boxShadow: [
          BoxShadow(
            color: p.shadow.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Name + Status Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: p.primary.withValues(alpha: 0.15),
                foregroundColor: p.primary,
                radius: 20,
                child: Text(
                  req.fullName.isNotEmpty ? req.fullName[0].toUpperCase() : '?',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.fullName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      flatStr,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: p.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  req.status.toUpperCase(),
                  style: TextStyle(
                    color: badgeText,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: p.hairline, height: 1),
          const SizedBox(height: 12),

          // Details grid
          _infoRow(p, Icons.badge_outlined, 'Role: ${req.roleLabel}'),
          _infoRow(p, Icons.phone_outlined, req.phone),
          _infoRow(p, Icons.email_outlined, req.email),
          if (req.aadharLast4 != null)
            _infoRow(p, Icons.fingerprint_rounded, 'Aadhar: •••• •••• ${req.aadharLast4}'),
          if (req.agreementDate != null)
            _infoRow(
              p,
              Icons.calendar_today_outlined,
              'Date: ${req.agreementDate!.toIso8601String().split('T').first}',
            ),
          if (req.rejectionReason != null && req.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: p.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: p.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Rejection reason: ${req.rejectionReason}',
                      style: TextStyle(color: p.danger, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (req.isPending) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isProcessing ? null : () => _reject(req),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.danger,
                      side: BorderSide(color: p.danger.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: isProcessing ? null : () => _approve(req),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    child: isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Approve Resident', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(AppPaletteData p, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 15, color: p.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: p.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
