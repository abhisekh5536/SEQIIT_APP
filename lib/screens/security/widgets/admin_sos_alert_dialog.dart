import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../models/security_models.dart';
import '../../../services/security_service.dart';

class AdminSosAlertDialog extends StatefulWidget {
  final SosAlert alert;
  final VoidCallback onDismiss;

  const AdminSosAlertDialog({
    super.key,
    required this.alert,
    required this.onDismiss,
  });

  static Future<void> show(BuildContext context, SosAlert alert) {
    HapticFeedback.heavyImpact();
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AdminSosAlertDialog(
        alert: alert,
        onDismiss: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  State<AdminSosAlertDialog> createState() => _AdminSosAlertDialogState();
}

class _AdminSosAlertDialogState extends State<AdminSosAlertDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _acknowledgeAlert() async {
    setState(() => _isProcessing = true);
    try {
      await SecurityService.instance.acknowledgeSosAlert(widget.alert.id);
      if (mounted) {
        widget.onDismiss();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to acknowledge: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _resolveAlert() async {
    setState(() => _isProcessing = true);
    try {
      await SecurityService.instance.resolveSosAlert(widget.alert.id);
      if (mounted) {
        widget.onDismiss();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resolve: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final alert = widget.alert;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeStr = DateFormat('h:mm a').format(alert.createdAt.toLocal());

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          final pulseBorder = alert.isActive
              ? Color.lerp(const Color(0xFFD32F2F), Colors.orange, _animController.value)!
              : const Color(0xFF0288D1);

          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: pulseBorder, width: 3),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Emergency Banner
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: alert.alertType.color.withAlpha(40),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        alert.alertType.icon,
                        color: alert.alertType.color,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🚨 ${alert.status.label.toUpperCase()}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: alert.alertType.color,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            alert.alertType.label,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: widget.onDismiss,
                    ),
                  ],
                ),

                const Divider(height: 24),

                // Flat and Resident Details Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF262626) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Unit / Flat:',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                          Text(
                            alert.formattedFlat,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Resident:',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                          Text(
                            alert.residentName ?? 'Resident',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Raised at:',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                          Text(
                            timeStr,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (alert.note != null && alert.note!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.amber.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Note: "${alert.note}"',
                            style: const TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Call Resident Action
                if (alert.residentPhone != null && alert.residentPhone!.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: () {
                      SecurityService.instance.launchCall(
                        phoneNumber: alert.residentPhone!,
                        societyId: alert.societyId,
                        flatId: alert.flatId,
                      );
                    },
                    icon: const Icon(Icons.phone_in_talk, color: Colors.white),
                    label: Text(
                      'Call Resident (${alert.residentPhone})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                // Action Buttons
                Row(
                  children: [
                    if (alert.isActive)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _acknowledgeAlert,
                          icon: const Icon(Icons.visibility_rounded),
                          label: const Text('Acknowledge'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0288D1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      )
                    else if (alert.isAcknowledged)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _resolveAlert,
                          icon: const Icon(Icons.check_circle_rounded),
                          label: const Text('Mark Resolved'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: widget.onDismiss,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
