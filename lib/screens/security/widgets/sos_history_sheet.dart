import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/security_models.dart';
import '../../../services/app_session.dart';
import '../../../services/security_service.dart';

class SosHistorySheet extends StatefulWidget {
  final List<SosAlert>? initialAlerts;

  const SosHistorySheet({super.key, this.initialAlerts});

  static Future<void> show(BuildContext context, {List<SosAlert>? initialAlerts}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SosHistorySheet(initialAlerts: initialAlerts),
    );
  }

  @override
  State<SosHistorySheet> createState() => _SosHistorySheetState();
}

class _SosHistorySheetState extends State<SosHistorySheet> {
  List<SosAlert> _alerts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialAlerts != null && widget.initialAlerts!.isNotEmpty) {
      _alerts = widget.initialAlerts!;
      _loading = false;
    } else {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    final flatIds = AppSession.instance.myResidences.map((r) => r.flatId).toList();
    if (flatIds.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    final list = await SecurityService.instance.fetchMySosHistory(flatIds);
    if (!mounted) return;
    setState(() {
      _alerts = list;
      _loading = false;
    });
  }

  void _showTimeline(SosAlert alert) async {
    final history = await SecurityService.instance.fetchSosHistoryTrail(alert.id);
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
                  Icon(alert.alertType.icon, color: alert.alertType.color),
                  const SizedBox(width: 10),
                  Text(
                    '${alert.alertType.label} - Status Trail',
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(top: 16, left: 20, right: 20, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.crisis_alert_rounded, color: Color(0xFFD32F2F)),
                  SizedBox(width: 8),
                  Text(
                    'SOS Emergency History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Text(
            'Past emergency alerts raised from your unit with audit trails',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _alerts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No emergency alerts recorded',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _alerts.length,
                        separatorBuilder: (ctx, i) => Divider(
                          color: isDark ? Colors.grey[800] : Colors.grey[200],
                          height: 1,
                        ),
                        itemBuilder: (ctx, i) {
                          final alert = _alerts[i];
                          final formattedTime =
                              DateFormat('d MMM, h:mm a').format(alert.createdAt.toLocal());

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 0,
                              vertical: 6,
                            ),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: alert.alertType.color.withAlpha(25),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                alert.alertType.icon,
                                color: alert.alertType.color,
                                size: 20,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    alert.alertType.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: alert.status.color.withAlpha(25),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    alert.status.label.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: alert.status.color,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Raised at $formattedTime',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                                if (alert.note != null && alert.note!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      '"${alert.note}"',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            trailing: TextButton(
                              onPressed: () => _showTimeline(alert),
                              child: const Text('Trail'),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
