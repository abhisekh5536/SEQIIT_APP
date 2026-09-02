import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/visitor_models.dart';
import '../../services/visitors_service.dart';
import '../../theme/app_theme.dart';

/// Full-screen modal for approving/denying a gate visitor request.
/// Shows a prominent photo, visitor details, and Approve / Deny actions.
class GateApprovalModal extends StatefulWidget {
  final VisitorRecord visitor;
  final VoidCallback? onResponded;

  const GateApprovalModal({
    super.key,
    required this.visitor,
    this.onResponded,
  });

  /// Shows the modal from anywhere in the app (e.g., from a notification tap).
  static void show(BuildContext context, VisitorRecord visitor,
      {VoidCallback? onResponded}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (_) => GateApprovalModal(
        visitor: visitor,
        onResponded: onResponded,
      ),
    );
  }

  @override
  State<GateApprovalModal> createState() => _GateApprovalModalState();
}

class _GateApprovalModalState extends State<GateApprovalModal> {
  bool _processing = false;
  final _reasonCtrl = TextEditingController();
  bool _showDenyReason = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final v = widget.visitor;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: p.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: p.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header with pulsing indicator
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: p.warning,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: p.warning.withValues(alpha: 0.5),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Visitor at Gate',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: p.cardMuted,
                    ),
                  ),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  children: [
                    // Photo (prominent)
                    _buildProminentPhoto(p, v),

                    const SizedBox(height: 16),

                    // Name + category
                    Text(
                      v.visitorName,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(v.category.icon,
                            size: 16, color: v.category.color),
                        const SizedBox(width: 6),
                        Text(
                          v.category.label,
                          style: TextStyle(
                            color: v.category.color,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (v.companyOrContext != null &&
                            v.companyOrContext!.isNotEmpty) ...[
                          Text(' · ',
                              style: TextStyle(color: p.textTertiary)),
                          Flexible(
                            child: Text(
                              v.companyOrContext!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Details
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: p.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: p.hairline),
                      ),
                      child: Column(
                        children: [
                          if (v.visitorPhone != null &&
                              v.visitorPhone!.isNotEmpty)
                            _detailRow(p, Icons.phone_outlined, v.visitorPhone!),
                          if (v.vehicleNumber != null &&
                              v.vehicleNumber!.isNotEmpty)
                            _detailRow(p, Icons.directions_car_outlined,
                                v.vehicleNumber!),
                          _detailRow(
                              p, Icons.apartment_rounded, v.flatDisplay),
                          _detailRow(p, Icons.schedule_rounded, v.timeAgo),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Deny reason field (shown when deny is tapped)
                    if (_showDenyReason) ...[
                      TextField(
                        controller: _reasonCtrl,
                        maxLines: 3,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Reason for denial (required)',
                          filled: true,
                          fillColor: p.card,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: p.danger),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                BorderSide(color: p.danger, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  setState(() => _showDenyReason = false),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text('Back'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed:
                                  _processing ? null : () => _deny(),
                              icon: _processing
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: p.onPrimary,
                                      ),
                                    )
                                  : const Icon(Icons.close_rounded,
                                      size: 18),
                              label: const Text('Confirm Deny'),
                              style: FilledButton.styleFrom(
                                backgroundColor: p.danger,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _processing
                                  ? null
                                  : () =>
                                      setState(() => _showDenyReason = true),
                              icon: Icon(Icons.close_rounded,
                                  size: 18, color: p.danger),
                              label: Text('Deny',
                                  style: TextStyle(color: p.danger)),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: p.danger),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: _processing ? null : _approve,
                              icon: _processing
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: p.onPrimary,
                                      ),
                                    )
                                  : const Icon(Icons.check_rounded,
                                      size: 20),
                              label: const Text('Approve Entry'),
                              style: FilledButton.styleFrom(
                                backgroundColor: p.success,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProminentPhoto(AppPaletteData p, VisitorRecord v) {
    if (v.visitorPhotoUrl != null && v.visitorPhotoUrl!.isNotEmpty) {
      final url = v.visitorPhotoUrl!;
      if (url.startsWith('data:image')) {
        try {
          final comma = url.indexOf(',');
          final b64 = comma != -1 ? url.substring(comma + 1) : url;
          final bytes = base64Decode(b64);
          return ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.memory(
              bytes,
              width: double.infinity,
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _photoPlaceholder(p, v),
            ),
          );
        } catch (_) {}
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.network(
          url,
          width: double.infinity,
          height: 220,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _photoPlaceholder(p, v),
        ),
      );
    }
    return _photoPlaceholder(p, v);
  }

  Widget _photoPlaceholder(AppPaletteData p, VisitorRecord v) {
    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        color: v.category.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: v.category.color.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(v.category.icon, size: 48, color: v.category.color),
          const SizedBox(height: 8),
          Text(
            'No photo captured',
            style: TextStyle(
              color: p.textTertiary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(AppPaletteData p, IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: p.textTertiary),
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

  Future<void> _approve() async {
    setState(() => _processing = true);
    try {
      await VisitorsService.instance.respondToVisitorRequest(
        visitorId: widget.visitor.id,
        action: 'approved',
      );
      widget.onResponded?.call();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Visitor approved! ✅'),
            backgroundColor:
                AppTheme.paletteFor(Theme.of(context).brightness).success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _deny() async {
    if (_reasonCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide a reason for denial'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _processing = true);
    try {
      await VisitorsService.instance.respondToVisitorRequest(
        visitorId: widget.visitor.id,
        action: 'denied',
        deniedReason: _reasonCtrl.text.trim(),
      );
      widget.onResponded?.call();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Visitor denied'),
            backgroundColor:
                AppTheme.paletteFor(Theme.of(context).brightness).danger,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }
}
