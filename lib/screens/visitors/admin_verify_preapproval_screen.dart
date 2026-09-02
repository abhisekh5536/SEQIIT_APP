import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/visitor_models.dart';
import '../../services/visitors_service.dart';
import '../../theme/app_theme.dart';

/// Admin gate stand-in: verify a pre-approved visitor by code.
class AdminVerifyPreapprovalScreen extends StatefulWidget {
  const AdminVerifyPreapprovalScreen({super.key});

  @override
  State<AdminVerifyPreapprovalScreen> createState() =>
      _AdminVerifyPreapprovalScreenState();
}

class _AdminVerifyPreapprovalScreenState
    extends State<AdminVerifyPreapprovalScreen> {
  final _codeCtrl = TextEditingController();
  bool _searching = false;
  bool _actioning = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Verify Pre-Approval',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Gate stand-in · Lookup by code',
                          style: textTheme.bodySmall?.copyWith(
                            color: p.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Code input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 6,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '000000',
                        hintStyle: TextStyle(
                          color: p.textTertiary.withValues(alpha: 0.4),
                          letterSpacing: 6,
                        ),
                        filled: true,
                        fillColor: p.card,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: p.hairline),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: p.hairline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                              color: p.primary, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 18),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: _searching ? null : _search,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      child: _searching
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: p.onPrimary,
                              ),
                            )
                          : Icon(Icons.search_rounded,
                              color: p.onPrimary),
                    ),
                  ),
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 18, color: p.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: p.danger,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Result
            Expanded(
              child: _result == null
                  ? _buildPlaceholder(p, textTheme)
                  : _buildResult(p, textTheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(AppPaletteData p, TextTheme textTheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: p.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.qr_code_scanner_rounded,
                size: 36, color: p.textTertiary),
          ),
          const SizedBox(height: 16),
          Text(
            'Enter Approval Code',
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Enter the 6-digit code shared by the resident',
            style: textTheme.bodySmall?.copyWith(color: p.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(AppPaletteData p, TextTheme textTheme) {
    final visitorData = _result!['visitor'];
    if (visitorData == null) {
      return Center(
        child: Text('Invalid result',
            style: textTheme.bodyMedium?.copyWith(color: p.danger)),
      );
    }

    final visitor = visitorData is Map<String, dynamic>
        ? VisitorRecord.fromMap(visitorData)
        : null;

    if (visitor == null) return const SizedBox.shrink();

    final flatNum = _result!['flat_number']?.toString() ?? '';
    final blockName = _result!['block_name']?.toString() ?? '';
    final groupMembers = _result!['group_members'] as List? ?? [];

    final status = visitor.status;
    final isValid = visitor.isApproved && visitor.isWithinValidity;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isValid
                  ? p.success.withValues(alpha: 0.08)
                  : status == VisitorStatus.checkedIn
                      ? const Color(0xFF2563EB).withValues(alpha: 0.08)
                      : p.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isValid
                    ? p.success.withValues(alpha: 0.3)
                    : status == VisitorStatus.checkedIn
                        ? const Color(0xFF2563EB).withValues(alpha: 0.3)
                        : p.danger.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isValid
                      ? Icons.verified_rounded
                      : status == VisitorStatus.checkedIn
                          ? Icons.login_rounded
                          : Icons.warning_rounded,
                  color: isValid
                      ? p.success
                      : status == VisitorStatus.checkedIn
                          ? const Color(0xFF2563EB)
                          : p.danger,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isValid
                            ? 'Valid Pre-Approval ✅'
                            : status == VisitorStatus.checkedIn
                                ? 'Already Checked In'
                                : 'Invalid: ${status.label}',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: isValid
                              ? p.success
                              : status == VisitorStatus.checkedIn
                                  ? const Color(0xFF2563EB)
                                  : p.danger,
                        ),
                      ),
                      if (visitor.validUntil != null)
                        Text(
                          'Valid until ${DateFormat('dd MMM yyyy, hh:mm a').format(visitor.validUntil!.toLocal())}',
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Visitor info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  visitor.visitorName,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                _detailRow(p, Icons.category_rounded, visitor.category.label),
                if (visitor.visitorPhone != null)
                  _detailRow(p, Icons.phone_outlined, visitor.visitorPhone!),
                if (visitor.companyOrContext != null)
                  _detailRow(p, Icons.business_outlined, visitor.companyOrContext!),
                if (visitor.vehicleNumber != null)
                  _detailRow(p, Icons.directions_car_outlined, visitor.vehicleNumber!),
                _detailRow(
                    p,
                    Icons.apartment_rounded,
                    blockName.isNotEmpty
                        ? '$blockName · Flat $flatNum'
                        : 'Flat $flatNum'),
              ],
            ),
          ),

          // Group members
          if (groupMembers.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
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
                      Icon(Icons.groups_rounded,
                          size: 18, color: p.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Group Members (${groupMembers.length})',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...List.generate(groupMembers.length, (i) {
                    final m = groupMembers[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: p.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  color: p.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            m['guest_name']?.toString() ?? '',
                            style: textTheme.bodyMedium,
                          ),
                          if (m['guest_phone'] != null &&
                              m['guest_phone'].toString().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              m['guest_phone'].toString(),
                              style: TextStyle(
                                color: p.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Action buttons
          if (visitor.canCheckIn)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _actioning ? null : () => _checkIn(visitor.id),
                icon: _actioning
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: p.onPrimary,
                        ),
                      )
                    : const Icon(Icons.login_rounded, size: 20),
                label: const Text(
                  'Mark Checked In',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: p.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),

          if (visitor.canCheckOut) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _actioning ? null : () => _checkOut(visitor.id),
                icon: const Icon(Icons.logout_rounded, size: 20),
                label: const Text(
                  'Mark Checked Out',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.primary,
                  side: BorderSide(color: p.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _detailRow(AppPaletteData p, IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: p.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _search() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _searching = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await VisitorsService.instance.verifyPreApproval(code);
      if (mounted) {
        if (result == null) {
          setState(() {
            _error = 'No visitor found with code "$code"';
            _searching = false;
          });
        } else {
          setState(() {
            _result = result;
            _searching = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _searching = false;
        });
      }
    }
  }

  Future<void> _checkIn(String visitorId) async {
    setState(() => _actioning = true);
    try {
      await VisitorsService.instance.checkInVisitor(visitorId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Visitor checked in ✅'),
            backgroundColor:
                AppTheme.paletteFor(Theme.of(context).brightness).success,
          ),
        );
        // Refresh the result
        _search();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _actioning = false);
    }
  }

  Future<void> _checkOut(String visitorId) async {
    setState(() => _actioning = true);
    try {
      await VisitorsService.instance.checkOutVisitor(visitorId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Visitor checked out ✅'),
            backgroundColor:
                AppTheme.paletteFor(Theme.of(context).brightness).success,
          ),
        );
        _search();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _actioning = false);
    }
  }
}
