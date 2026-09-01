import 'package:flutter/material.dart';

import '../../../models/complaint_models.dart';
import '../../../theme/app_theme.dart';

class ComplaintTimelineView extends StatelessWidget {
  final List<ComplaintStatusHistoryRecord> history;
  final bool isLoading;

  const ComplaintTimelineView({
    super.key,
    required this.history,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: p.primary),
          ),
        ),
      );
    }

    if (history.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          children: [
            Icon(Icons.history_rounded, size: 20, color: p.textTertiary),
            const SizedBox(width: 10),
            Text(
              'No status history recorded yet',
              style: textTheme.bodyMedium?.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < history.length; i++)
          _buildTimelineNode(context, history[i], isFirst: i == 0, isLast: i == history.length - 1, p: p),
      ],
    );
  }

  Widget _buildTimelineNode(
    BuildContext context,
    ComplaintStatusHistoryRecord item, {
    required bool isFirst,
    required bool isLast,
    required AppPaletteData p,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final status = item.toStatus;

    Color nodeColor = status.foreground;
    IconData nodeIcon = status.icon;

    if (item.fromStatus == null) {
      nodeColor = p.primary;
      nodeIcon = Icons.add_circle_outline_rounded;
    } else if (item.fromStatus == item.toStatus) {
      nodeColor = const Color(0xFF8B5CF6);
      nodeIcon = Icons.comment_outlined;
    }

    String headingText;
    if (item.fromStatus == null) {
      headingText = 'Complaint Raised';
    } else if (item.fromStatus == item.toStatus) {
      headingText = 'Note Added';
    } else {
      headingText = 'Status updated to ${status.label}';
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator line + circle
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: nodeColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: nodeColor, width: 2),
                  ),
                  child: Center(
                    child: Icon(nodeIcon, size: 13, color: nodeColor),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: p.hairline,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Content card
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            headingText,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                        _buildRoleBadge(item.changedByRole, p, textTheme),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.formattedTime,
                      style: textTheme.bodySmall?.copyWith(
                        color: p.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    if (item.note != null && item.note!.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: p.cardMuted,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: p.hairline),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.format_quote_rounded, size: 16, color: p.textTertiary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.note!,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: p.textPrimary,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleBadge(String role, AppPaletteData p, TextTheme textTheme) {
    final isAdmin = role == 'society_admin';
    final bg = isAdmin ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9);
    final fg = isAdmin ? const Color(0xFFD97706) : const Color(0xFF475569);
    final label = isAdmin ? 'Admin' : 'Resident';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
            size: 11,
            color: fg,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
