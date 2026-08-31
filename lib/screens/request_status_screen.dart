import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/db_models.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';

class RequestStatusScreen extends StatefulWidget {
  final ResidentJoinRequest request;

  const RequestStatusScreen({super.key, required this.request});

  @override
  State<RequestStatusScreen> createState() => _RequestStatusScreenState();
}

class _RequestStatusScreenState extends State<RequestStatusScreen> {
  bool _refreshing = false;
  bool _cancelling = false;

  Future<void> _refresh() async {
    HapticFeedback.selectionClick();
    setState(() => _refreshing = true);
    await AppSession.instance.load();
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _cancelRequest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw Request?'),
        content: const Text(
          'Are you sure you want to cancel this request? You will be able to select a different flat or society.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No, keep it')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _cancelling = true);
    try {
      await Supabase.instance.client
          .from('resident_join_requests')
          .update({'status': 'cancelled'})
          .eq('id', widget.request.id);

      await AppSession.instance.refreshJoinRequest();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request cancelled. You can now choose another flat.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel request: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign Out')),
        ],
      ),
    );
    if (confirmed == true) {
      await Supabase.instance.client.auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final req = widget.request;

    final isPending = req.isPending;
    final isRejected = req.isRejected;

    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: const Text(
          'Request Status',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
        backgroundColor: p.canvas,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out',
            onPressed: _signOut,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status Hero Card
                  _buildHeroStatus(p, req),
                  const SizedBox(height: 24),

                  // Request Summary Card
                  _buildDetailsCard(p, req),
                  const SizedBox(height: 28),

                  // Actions
                  if (isPending) ...[
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _refreshing ? null : _refresh,
                        icon: _refreshing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.refresh_rounded),
                        label: Text(_refreshing ? 'Checking...' : 'Check Approval Status'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: p.primary,
                          foregroundColor: p.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        onPressed: _cancelling ? null : _cancelRequest,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: p.danger,
                          side: BorderSide(color: p.danger.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _cancelling
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Withdraw Request & Choose Another Flat'),
                      ),
                    ),
                  ] else if (isRejected) ...[
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _cancelRequest,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: p.primary,
                          foregroundColor: p.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Submit New Request'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroStatus(AppPaletteData p, ResidentJoinRequest req) {
    Color statusColor;
    IconData statusIcon;
    String statusTitle;
    String statusSubtitle;

    if (req.isPending) {
      statusColor = const Color(0xFFE68A00); // Amber/Orange
      statusIcon = Icons.hourglass_top_rounded;
      statusTitle = 'Approval Pending';
      statusSubtitle =
          'Your flat request has been sent to the Society Admin of ${req.societyName ?? 'the society'}. You will get instant dashboard access once reviewed.';
    } else if (req.isRejected) {
      statusColor = p.danger;
      statusIcon = Icons.cancel_outlined;
      statusTitle = 'Request Declined';
      statusSubtitle = req.rejectionReason != null && req.rejectionReason!.isNotEmpty
          ? 'Reason: "${req.rejectionReason}"'
          : 'The society administration declined this request. You can re-apply or pick another flat.';
    } else {
      statusColor = const Color(0xFF10B981); // Emerald
      statusIcon = Icons.check_circle_outline_rounded;
      statusTitle = 'Approved!';
      statusSubtitle = 'Your request has been approved. Welcome home!';
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.hairline),
        boxShadow: [
          BoxShadow(
            color: p.shadow.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, color: statusColor, size: 40),
          ),
          const SizedBox(height: 16),
          Text(
            statusTitle,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: p.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            statusSubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: p.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard(AppPaletteData p, ResidentJoinRequest req) {
    final society = req.societyName ?? 'Society';
    final flatText = req.flatNumber != null
        ? '${req.blockName != null ? '${req.blockName} · ' : ''}Flat ${req.flatNumber}'
        : 'Assigned Flat';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Application Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: p.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _detailRow(p, 'Society', society, Icons.apartment_rounded),
          _detailRow(p, 'Unit / Flat', flatText, Icons.meeting_room_rounded),
          _detailRow(p, 'Resident Type', req.roleLabel, Icons.badge_outlined),
          _detailRow(p, 'Full Name', req.fullName, Icons.person_outline_rounded),
          _detailRow(p, 'Phone', req.phone, Icons.phone_outlined),
          _detailRow(p, 'Email', req.email, Icons.email_outlined),
          if (req.aadharLast4 != null)
            _detailRow(p, 'Aadhar (Last 4)', '•••• •••• ${req.aadharLast4}', Icons.fingerprint_rounded),
          if (req.createdAt != null)
            _detailRow(
              p,
              'Submitted On',
              req.createdAt!.toLocal().toString().split(' ').first,
              Icons.schedule_rounded,
            ),
        ],
      ),
    );
  }

  Widget _detailRow(AppPaletteData p, String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: p.textTertiary),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(fontSize: 13.5, color: p.textSecondary, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: p.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
