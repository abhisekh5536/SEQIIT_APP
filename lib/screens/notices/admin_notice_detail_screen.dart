import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/notice_models.dart';
import '../../services/notices_service.dart';
import '../../theme/app_theme.dart';
import 'create_edit_notice_screen.dart';

class AdminNoticeDetailScreen extends StatefulWidget {
  final NoticeRecord notice;

  const AdminNoticeDetailScreen({super.key, required this.notice});

  @override
  State<AdminNoticeDetailScreen> createState() => _AdminNoticeDetailScreenState();
}

class _AdminNoticeDetailScreenState extends State<AdminNoticeDetailScreen>
    with SingleTickerProviderStateMixin {
  late NoticeRecord _notice;
  List<NoticeReaderInfo> _readers = [];
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _notice = widget.notice;
    _tabController = TabController(
      length: _notice.requiresAcknowledgment ? 3 : 2,
      vsync: this,
    );
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final updatedNotice = await NoticesService.instance.fetchNoticeById(_notice.id);
      final list = await NoticesService.instance.fetchNoticeReaderDetails(_notice.id);
      if (mounted) {
        setState(() {
          if (updatedNotice != null) _notice = updatedNotice;
          _readers = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePublishNow() async {
    HapticFeedback.mediumImpact();
    try {
      await NoticesService.instance.publishNoticeNow(_notice.id);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notice published immediately!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _handleUnpublish() async {
    HapticFeedback.mediumImpact();
    try {
      await NoticesService.instance.unpublishNotice(_notice.id);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notice moved to draft.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _handleArchive() async {
    HapticFeedback.mediumImpact();
    try {
      await NoticesService.instance.archiveNotice(_notice.id);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notice archived.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Notice?'),
        content: const Text('This will permanently delete this notice and all its read history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await NoticesService.instance.deleteNotice(_notice.id);
        if (mounted) {
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    final totalCount = _readers.length;
    final readCount = _readers.where((r) => r.hasRead).length;
    final ackCount = _readers.where((r) => r.hasAcknowledged).length;
    final pendingAckList = _readers.where((r) => !r.hasAcknowledged).toList();
    final ackList = _readers.where((r) => r.hasAcknowledged).toList();

    final readPercent = totalCount > 0 ? (readCount / totalCount) : 0.0;
    final ackPercent = totalCount > 0 ? (ackCount / totalCount) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notice Analytics',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (val) {
              switch (val) {
                case 'edit':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreateEditNoticeScreen(noticeToEdit: _notice),
                    ),
                  ).then((_) => _loadData());
                  break;
                case 'publish_now':
                  _handlePublishNow();
                  break;
                case 'unpublish':
                  _handleUnpublish();
                  break;
                case 'archive':
                  _handleArchive();
                  break;
                case 'delete':
                  _handleDelete();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit Notice')),
              if (_notice.status != NoticeStatus.published)
                const PopupMenuItem(value: 'publish_now', child: Text('Publish Now')),
              if (_notice.status == NoticeStatus.published)
                const PopupMenuItem(value: 'unpublish', child: Text('Unpublish to Draft')),
              if (_notice.status != NoticeStatus.archived)
                const PopupMenuItem(value: 'archive', child: Text('Archive Notice')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete Notice', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Status & Category row
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _notice.status.color(p).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _notice.status.label.toUpperCase(),
                                  style: textTheme.labelSmall?.copyWith(
                                    color: _notice.status.color(p),
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _notice.category.color(p).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _notice.category.label,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: _notice.category.color(p),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          Text(
                            _notice.title,
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Analytics Metrics Cards
                          Row(
                            children: [
                              // Read Rate Card
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: p.card,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: p.hairline),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Read Rate', style: textTheme.labelMedium),
                                          Icon(Icons.visibility_outlined, size: 16, color: p.primary),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '$readCount / $totalCount',
                                        style: textTheme.headlineSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      LinearProgressIndicator(
                                        value: readPercent,
                                        backgroundColor: p.hairline,
                                        color: p.primary,
                                        minHeight: 6,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${(readPercent * 100).toInt()}% seen',
                                        style: textTheme.labelSmall?.copyWith(
                                          color: p.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              if (_notice.requiresAcknowledgment) ...[
                                const SizedBox(width: 12),
                                // Acknowledgment Rate Card
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: p.card,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: p.hairline),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text('Acknowledged', style: textTheme.labelMedium),
                                            Icon(Icons.check_circle_outline, size: 16, color: p.success),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '$ackCount / $totalCount',
                                          style: textTheme.headlineSmall?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: p.success,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        LinearProgressIndicator(
                                          value: ackPercent,
                                          backgroundColor: p.hairline,
                                          color: p.success,
                                          minHeight: 6,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${(ackPercent * 100).toInt()}% confirmed',
                                          style: textTheme.labelSmall?.copyWith(
                                            color: p.textTertiary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _SliverAppBarDelegate(
                      TabBar(
                        controller: _tabController,
                        tabs: [
                          if (_notice.requiresAcknowledgment) ...[
                            Tab(text: 'Pending (${pendingAckList.length})'),
                            Tab(text: 'Acknowledged (${ackList.length})'),
                          ],
                          Tab(text: 'All Residents ($totalCount)'),
                        ],
                      ),
                      p.canvas,
                    ),
                  ),
                ];
              },
              body: TabBarView(
                controller: _tabController,
                children: [
                  if (_notice.requiresAcknowledgment) ...[
                    _buildResidentList(pendingAckList, p, isPendingAck: true),
                    _buildResidentList(ackList, p, isAckList: true),
                  ],
                  _buildResidentList(_readers, p),
                ],
              ),
            ),
    );
  }

  Widget _buildResidentList(
    List<NoticeReaderInfo> list,
    AppPaletteData p, {
    bool isPendingAck = false,
    bool isAckList = false,
  }) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          isPendingAck
              ? 'All residents have acknowledged!'
              : 'No residents in this list.',
          style: TextStyle(color: p.textSecondary),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      itemCount: list.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (ctx, index) {
        final r = list[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.hairline),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: r.hasAcknowledged
                    ? p.success.withValues(alpha: 0.15)
                    : (r.hasRead ? p.primary.withValues(alpha: 0.15) : p.hairline),
                child: Icon(
                  r.hasAcknowledged
                      ? Icons.check_circle_rounded
                      : (r.hasRead ? Icons.visibility_rounded : Icons.person_outline_rounded),
                  color: r.hasAcknowledged
                      ? p.success
                      : (r.hasRead ? p.primary : p.textTertiary),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.residentName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r.flatDisplay,
                      style: TextStyle(color: p.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (r.hasAcknowledged && r.acknowledgedAt != null) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Ack on',
                      style: TextStyle(color: p.textTertiary, fontSize: 10),
                    ),
                    Text(
                      DateFormat('d MMM, h:mm a').format(r.acknowledgedAt!.toLocal()),
                      style: TextStyle(
                        color: p.success,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ] else if (r.hasRead && r.readAt != null) ...[
                Text(
                  'Seen ${DateFormat('d MMM').format(r.readAt!.toLocal())}',
                  style: TextStyle(color: p.textTertiary, fontSize: 12),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: p.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Unread',
                    style: TextStyle(
                      color: p.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;

  _SliverAppBarDelegate(this.tabBar, this.backgroundColor);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: backgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar;
  }
}
