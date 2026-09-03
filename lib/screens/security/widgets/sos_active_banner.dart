import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/security_models.dart';
import '../../../services/security_service.dart';

class SosActiveBanner extends StatefulWidget {
  final SosAlert alert;
  final VoidCallback onUpdated;

  const SosActiveBanner({
    super.key,
    required this.alert,
    required this.onUpdated,
  });

  @override
  State<SosActiveBanner> createState() => _SosActiveBannerState();
}

class _SosActiveBannerState extends State<SosActiveBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _confirmCancelAlert() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Emergency Alert?'),
        content: const Text(
          'Are you sure you want to cancel this SOS alert? Society admins will be informed that this was a false alarm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Active'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, Cancel Alert'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isCancelling = true);
    try {
      await SecurityService.instance.cancelSosAlert(
        widget.alert.id,
        note: 'Resident marked as resolved / false alarm',
      );
      widget.onUpdated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel alert: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  void _showTimelineModal() async {
    final history = await SecurityService.instance.fetchSosHistoryTrail(widget.alert.id);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(widget.alert.alertType.icon, color: widget.alert.alertType.color),
                  const SizedBox(width: 10),
                  Text(
                    '${widget.alert.alertType.label} - Status Trail',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('No audit history recorded yet.')),
                )
              else
                ...history.map((h) {
                  final timeStr = DateFormat('h:mm a, d MMM').format(h.createdAt.toLocal());
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: h.toStatus == 'active'
                                ? Colors.red.withAlpha(30)
                                : h.toStatus == 'acknowledged'
                                    ? Colors.blue.withAlpha(30)
                                    : Colors.green.withAlpha(30),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            h.toStatus == 'active'
                                ? Icons.emergency
                                : h.toStatus == 'acknowledged'
                                    ? Icons.visibility
                                    : Icons.check,
                            size: 14,
                            color: h.toStatus == 'active'
                                ? Colors.red
                                : h.toStatus == 'acknowledged'
                                    ? Colors.blue
                                    : Colors.green,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    h.toStatus.toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              if (h.note != null && h.note!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    h.note!,
                                    style: TextStyle(
                                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              Text(
                                'Action by ${h.changedByRole.replaceAll('_', ' ')}',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final alert = widget.alert;
    final isAcknowledged = alert.isAcknowledged;
    final timeStr = DateFormat('h:mm a').format(alert.createdAt.toLocal());

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final glowOpacity = isAcknowledged ? 0.2 : 0.2 + (_animController.value * 0.25);
        final baseColor = isAcknowledged ? const Color(0xFF0288D1) : const Color(0xFFD32F2F);

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: baseColor.withAlpha((glowOpacity * 255).toInt()),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: baseColor,
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: baseColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      alert.alertType.icon,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAcknowledged
                              ? '🛡️ SOS ACKNOWLEDGED (HELP IS ON THE WAY)'
                              : '🚨 ACTIVE EMERGENCY SOS BROADCAST',
                          style: TextStyle(
                            color: baseColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 0.4,
                          ),
                        ),
                        Text(
                          '${alert.alertType.label} · Raised at $timeStr',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: _showTimelineModal,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, size: 14),
                          SizedBox(width: 4),
                          Text('Trail', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (alert.note != null && alert.note!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Note: "${alert.note}"',
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isCancelling ? null : _confirmCancelAlert,
                      icon: _isCancelling
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cancel_outlined, size: 16),
                      label: Text(
                        _isCancelling ? 'Cancelling...' : 'Cancel (False Alarm)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: baseColor,
                        side: BorderSide(color: baseColor),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
