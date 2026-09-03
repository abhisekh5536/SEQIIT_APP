import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/security_models.dart';
import '../../../services/app_session.dart';
import '../../../services/security_service.dart';

class CallHistorySheet extends StatefulWidget {
  const CallHistorySheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const CallHistorySheet(),
    );
  }

  @override
  State<CallHistorySheet> createState() => _CallHistorySheetState();
}

class _CallHistorySheetState extends State<CallHistorySheet> {
  List<EmergencyCallLog> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final flatIds = AppSession.instance.myResidences.map((r) => r.flatId).toList();
    if (flatIds.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    final logs = await SecurityService.instance.fetchMyCallLogs(flatIds);
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
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
                  Icon(Icons.history_rounded, color: Colors.teal),
                  SizedBox(width: 8),
                  Text(
                    'My Call History',
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
            'Calls made to emergency and society contacts from your unit',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.phone_missed_rounded,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No emergency calls logged yet',
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
                        itemCount: _logs.length,
                        separatorBuilder: (ctx, i) => Divider(
                          color: isDark ? Colors.grey[800] : Colors.grey[200],
                          height: 1,
                        ),
                        itemBuilder: (ctx, i) {
                          final log = _logs[i];
                          final formattedTime =
                              DateFormat('d MMM, h:mm a').format(log.calledAt.toLocal());

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 0,
                              vertical: 4,
                            ),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.teal.withAlpha(25),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.call_made_rounded,
                                color: Colors.teal,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              log.contactName ?? 'Emergency Contact',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              '${log.contactPhone ?? ''} · $formattedTime',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.phone_in_talk, color: Colors.teal, size: 20),
                              tooltip: 'Call Again',
                              onPressed: log.contactPhone == null
                                  ? null
                                  : () {
                                      SecurityService.instance.launchCall(
                                        phoneNumber: log.contactPhone!,
                                        societyId: log.societyId,
                                        contactId: log.contactId,
                                        flatId: log.flatId,
                                      );
                                    },
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
