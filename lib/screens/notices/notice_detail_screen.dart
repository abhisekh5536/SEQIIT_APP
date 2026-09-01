import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/notice_models.dart';
import '../../services/app_session.dart';
import '../../services/notices_service.dart';
import '../../theme/app_theme.dart';
import 'admin_notice_detail_screen.dart';
import 'create_edit_notice_screen.dart';

class NoticeDetailScreen extends StatefulWidget {
  final NoticeRecord notice;

  const NoticeDetailScreen({super.key, required this.notice});

  @override
  State<NoticeDetailScreen> createState() => _NoticeDetailScreenState();
}

class _NoticeDetailScreenState extends State<NoticeDetailScreen> {
  late NoticeRecord _notice;
  bool _isAckSubmitting = false;

  @override
  void initState() {
    super.initState();
    _notice = widget.notice;
    _markReadAndRefresh();
  }

  Future<void> _markReadAndRefresh() async {
    // Fire and forget read logging for residents
    if (!AppSession.instance.isAdmin) {
      NoticesService.instance.markAsRead(_notice.id);
    }

    try {
      final updated = await NoticesService.instance.fetchNoticeById(_notice.id);
      if (mounted && updated != null) {
        setState(() => _notice = updated);
      }
    } catch (_) {}
  }

  Future<void> _handleAcknowledge() async {
    HapticFeedback.mediumImpact();
    setState(() => _isAckSubmitting = true);

    try {
      await NoticesService.instance.acknowledgeNotice(_notice.id);
      if (mounted) {
        setState(() {
          _notice = _notice.copyWith(
            isAcknowledgedByMe: true,
            myAcknowledgedAt: DateTime.now(),
          );
          _isAckSubmitting = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(child: Text('Notice acknowledged successfully.')),
              ],
            ),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAckSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to acknowledge: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final isAdmin = AppSession.instance.isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _notice.category.label,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (isAdmin) ...[
            IconButton(
              icon: const Icon(Icons.analytics_outlined),
              tooltip: 'Read & Ack Analytics',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminNoticeDetailScreen(notice: _notice),
                  ),
                ).then((_) => _markReadAndRefresh());
              },
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Notice',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateEditNoticeScreen(noticeToEdit: _notice),
                  ),
                ).then((_) => _markReadAndRefresh());
              },
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            // Pinned & Scope badges row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _notice.category.color(p).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _notice.category.color(p).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _notice.category.icon,
                        size: 14,
                        color: _notice.category.color(p),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _notice.category.label,
                        style: textTheme.labelSmall?.copyWith(
                          color: _notice.category.color(p),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_notice.isPinned) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: p.warning.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.push_pin_rounded, size: 12, color: p.warning),
                        const SizedBox(width: 4),
                        Text(
                          'Pinned',
                          style: textTheme.labelSmall?.copyWith(
                            color: p.warning,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                if (_notice.targetType == NoticeTargetType.block)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: p.hairline),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.domain_outlined, size: 12, color: p.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          _notice.targetBlockName ?? 'Block Specific',
                          style: textTheme.labelSmall?.copyWith(color: p.textSecondary),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    'All Residents',
                    style: textTheme.labelSmall?.copyWith(color: p.textTertiary),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Title
            Text(
              _notice.title,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),

            // Metadata row (Date & Publisher)
            Row(
              children: [
                Icon(Icons.access_time_rounded, size: 14, color: p.textTertiary),
                const SizedBox(width: 5),
                Text(
                  _notice.formattedPublishDate,
                  style: textTheme.bodySmall?.copyWith(color: p.textTertiary),
                ),
                if (_notice.expiresAt != null) ...[
                  const SizedBox(width: 8),
                  Text('·', style: TextStyle(color: p.textTertiary)),
                  const SizedBox(width: 8),
                  Icon(Icons.timer_outlined, size: 13, color: p.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    'Expires ${DateFormat('d MMM').format(_notice.expiresAt!.toLocal())}',
                    style: textTheme.bodySmall?.copyWith(color: p.textTertiary),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),

            // Prominent Event Card (if isEvent)
            if (_notice.isEvent && _notice.eventStartsAt != null) ...[
              _buildEventCard(context, p),
              const SizedBox(height: 20),
            ],

            // Body text
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: p.hairline),
              ),
              child: SelectableText(
                _notice.body,
                style: textTheme.bodyLarge?.copyWith(
                  height: 1.6,
                  color: p.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Attachment section
            if (_notice.attachmentUrl != null && _notice.attachmentUrl!.isNotEmpty) ...[
              _buildAttachmentCard(context, p),
              const SizedBox(height: 20),
            ],

            // Mandatory Acknowledgment Section
            if (_notice.requiresAcknowledgment) ...[
              _buildAcknowledgmentSection(context, p),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, AppPaletteData p) {
    final textTheme = Theme.of(context).textTheme;
    final start = _notice.eventStartsAt!.toLocal();
    final monthStr = DateFormat('MMM').format(start).toUpperCase();
    final dayStr = DateFormat('d').format(start);
    final weekdayStr = DateFormat('EEEE').format(start);

    final startTimeStr = DateFormat('h:mm a').format(start);
    final endTimeStr = _notice.eventEndsAt != null
        ? DateFormat('h:mm a').format(_notice.eventEndsAt!.toLocal())
        : null;

    final timeLine = endTimeStr != null ? '$startTimeStr – $endTimeStr' : startTimeStr;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            p.secondary.withValues(alpha: 0.12),
            p.primary.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.secondary.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Calendar Date Tile
          Container(
            width: 60,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.secondary.withValues(alpha: 0.4)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  monthStr,
                  style: textTheme.labelSmall?.copyWith(
                    color: p.secondary,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dayStr,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Event Timing & Venue details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  weekdayStr,
                  style: textTheme.labelMedium?.copyWith(
                    color: p.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 14, color: p.secondary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        timeLine,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_notice.eventVenue != null && _notice.eventVenue!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.place_outlined, size: 14, color: p.textTertiary),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          _notice.eventVenue!,
                          style: textTheme.bodySmall?.copyWith(
                            color: p.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentCard(BuildContext context, AppPaletteData p) {
    final textTheme = Theme.of(context).textTheme;
    final isImage = _notice.attachmentUrl!.toLowerCase().endsWith('.png') ||
        _notice.attachmentUrl!.toLowerCase().endsWith('.jpg') ||
        _notice.attachmentUrl!.toLowerCase().endsWith('.jpeg') ||
        _notice.attachmentUrl!.toLowerCase().endsWith('.webp');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.attach_file_rounded, size: 16, color: p.textSecondary),
            const SizedBox(width: 6),
            Text('Attachment', style: textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 8),
        if (isImage)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: p.card,
              child: Image.network(
                _notice.attachmentUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    height: 180,
                    alignment: Alignment.center,
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 120,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text('Could not load image attachment'),
                ),
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                Icon(Icons.description_outlined, color: p.primary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Attached Document',
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    // Open attachment link
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('View'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAcknowledgmentSection(BuildContext context, AppPaletteData p) {
    final textTheme = Theme.of(context).textTheme;

    if (_notice.isAcknowledgedByMe) {
      final ackDateStr = _notice.myAcknowledgedAt != null
          ? DateFormat('d MMM yyyy, h:mm a').format(_notice.myAcknowledgedAt!.toLocal())
          : 'earlier';

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2E7D32).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFF2E7D32),
              child: Icon(Icons.check_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Acknowledged',
                    style: textTheme.titleSmall?.copyWith(
                      color: const Color(0xFF2E7D32),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Confirmed on $ackDateStr',
                    style: textTheme.bodySmall?.copyWith(
                      color: p.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_turned_in_outlined, color: p.warning, size: 22),
              const SizedBox(width: 10),
              Text(
                'Acknowledgment Required',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: p.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'The management committee requires all residents to confirm they have read and understood this notice.',
            style: textTheme.bodySmall?.copyWith(
              color: p.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isAckSubmitting ? null : _handleAcknowledge,
              style: FilledButton.styleFrom(
                backgroundColor: p.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _isAckSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.thumb_up_alt_outlined, size: 18),
              label: Text(
                _isAckSubmitting ? 'Acknowledging...' : 'I Understand / Acknowledge',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
