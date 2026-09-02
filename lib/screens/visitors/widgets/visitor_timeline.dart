import 'package:flutter/material.dart';

import '../../../models/visitor_models.dart';
import '../../../theme/app_theme.dart';

/// Status history timeline widget for visitor detail screens.
/// Same style as complaint history timeline.
class VisitorTimeline extends StatelessWidget {
  final List<VisitorStatusHistoryRecord> history;

  const VisitorTimeline({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    if (history.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.hairline),
        ),
        child: Center(
          child: Text(
            'No history yet',
            style: textTheme.bodySmall?.copyWith(color: p.textTertiary),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Status Timeline',
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(history.length, (index) {
            final record = history[index];
            final isLast = index == history.length - 1;
            return _buildTimelineItem(context, p, textTheme, record, isLast);
          }),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(
    BuildContext context,
    AppPaletteData p,
    TextTheme textTheme,
    VisitorStatusHistoryRecord record,
    bool isLast,
  ) {
    final statusColor = record.toStatus.foreground;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline column
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    record.toStatus.icon,
                    size: 14,
                    color: statusColor,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: p.hairline,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Content column
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          record.toStatus.label,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ),
                      Text(
                        record.timeAgo,
                        style: TextStyle(
                          color: p.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  if (record.note != null && record.note!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      record.note!,
                      style: textTheme.bodySmall?.copyWith(
                        color: p.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    '${record.roleLabel} · ${record.formattedTime}',
                    style: TextStyle(
                      color: p.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
