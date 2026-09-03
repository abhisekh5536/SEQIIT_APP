import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/notification_model.dart';
import '../services/app_session.dart';
import '../services/notifications_service.dart';
import '../theme/app_theme.dart';
import 'admin_approvals_screen.dart';
import 'complaints/admin_complaint_detail_screen.dart';
import 'complaints/resident_complaint_detail_screen.dart';
import 'visitors/visitor_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _selectedFilter = 'all'; // 'all' | 'unread' | 'complaints' | 'approvals'

  @override
  void initState() {
    super.initState();
    NotificationsService.instance.fetchNotifications();
  }

  void _handleNotificationTap(AppNotification notification) async {
    HapticFeedback.lightImpact();
    await NotificationsService.instance.markAsRead(notification.id);

    if (!mounted) return;

    final isAdmin = AppSession.instance.isAdmin;
    final entityType = notification.entityType;
    final entityId = notification.entityId;

    if (entityType == 'complaint' && entityId != null && entityId.isNotEmpty) {
      if (isAdmin) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AdminComplaintDetailScreen(complaintId: entityId),
          ),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ResidentComplaintDetailScreen(complaintId: entityId),
          ),
        );
      }
      return;
    }

    if (entityType == 'join_request' && isAdmin) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const AdminApprovalsScreen(),
        ),
      );
      return;
    }

    if (entityType == 'notice' || notification.type == 'notice') {
      Navigator.pushNamed(context, '/notices');
      return;
    }

    if (entityType == 'sos_alert' || notification.type.startsWith('sos_alert')) {
      Navigator.pushNamed(context, '/security');
      return;
    }

    if ((entityType == 'visitor' || notification.type.startsWith('visitor')) &&
        entityId != null &&
        entityId.isNotEmpty &&
        !entityId.contains('_')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VisitorDetailScreen(visitorId: entityId),
        ),
      );
      return;
    }

    if (notification.route != null && notification.route!.isNotEmpty) {
      Navigator.pushNamed(context, notification.route!);
    }
  }

  List<AppNotification> _filterList(List<AppNotification> list) {
    switch (_selectedFilter) {
      case 'unread':
        return list.where((n) => !n.isRead).toList();
      case 'complaints':
        return list.where((n) => n.isComplaint).toList();
      case 'notices':
        return list.where((n) => n.isNotice).toList();
      case 'approvals':
        return list.where((n) => n.isApproval).toList();
      default:
        return list;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: p.canvas,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          AnimatedBuilder(
            animation: NotificationsService.instance,
            builder: (context, _) {
              final unread = NotificationsService.instance.unreadCount;
              if (unread == 0) return const SizedBox.shrink();
              return TextButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  NotificationsService.instance.markAllAsRead();
                },
                icon: const Icon(Icons.done_all_rounded, size: 16),
                label: const Text(
                  'Mark all read',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
                style: TextButton.styleFrom(foregroundColor: p.primary),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: NotificationsService.instance,
          builder: (context, _) {
            final service = NotificationsService.instance;
            final allList = service.notifications;
            final filteredList = _filterList(allList);
            final retention = service.retention;

            return RefreshIndicator(
              onRefresh: service.fetchNotifications,
              color: p.primary,
              child: CustomScrollView(
                slivers: [
                  // Filter Chips & Retention info Sliver
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Retention Caption
                          Row(
                            children: [
                              Icon(Icons.history_toggle_off_rounded, size: 14, color: p.textTertiary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Showing history for: ${retention.label}',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: p.textTertiary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => Navigator.pushNamed(context, '/settings'),
                                child: Text(
                                  'Change',
                                  style: TextStyle(
                                    color: p.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Filter chips
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildFilterChip('All', 'all', allList.length, p),
                                const SizedBox(width: 8),
                                _buildFilterChip('Unread', 'unread', service.unreadCount, p),
                                const SizedBox(width: 8),
                                _buildFilterChip(
                                  'Complaints',
                                  'complaints',
                                  allList.where((n) => n.isComplaint).length,
                                  p,
                                ),
                                const SizedBox(width: 8),
                                _buildFilterChip(
                                  'Notices',
                                  'notices',
                                  allList.where((n) => n.isNotice).length,
                                  p,
                                ),
                                if (AppSession.instance.isAdmin) ...[
                                  const SizedBox(width: 8),
                                  _buildFilterChip(
                                    'Approvals',
                                    'approvals',
                                    allList.where((n) => n.isApproval).length,
                                    p,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Notifications list or empty state
                  if (service.isLoading && allList.isEmpty)
                    SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator(color: p.primary)),
                    )
                  else if (filteredList.isEmpty)
                    SliverFillRemaining(
                      child: _buildEmptyState(p, textTheme),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = filteredList[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _buildNotificationTile(item, p, textTheme),
                            );
                          },
                          childCount: filteredList.length,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, int count, AppPaletteData p) {
    final isSelected = _selectedFilter == value;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedFilter = value);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? p.primary : p.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? p.primary : p.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : p.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 12,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : (value == 'unread' ? p.danger.withValues(alpha: 0.15) : p.cardMuted),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : (value == 'unread' ? p.danger : p.textPrimary),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationTile(
    AppNotification item,
    AppPaletteData p,
    TextTheme textTheme,
  ) {
    final isRead = item.isRead;

    // UNSEEN (Unread): Crisp, fresh card color with high contrast, bright icon and left color strip
    // SEEN (Read): Distinctly faded / muted gray appearance
    final cardColor = isRead ? p.cardMuted.withValues(alpha: 0.45) : p.card;
    final titleColor = isRead ? p.textSecondary : p.textPrimary;
    final bodyColor = isRead ? p.textTertiary : p.textSecondary;
    final iconBg = isRead ? p.cardMuted : item.iconBgColor;
    final iconColor = isRead ? p.textTertiary : item.iconColor;

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(16),
      elevation: isRead ? 0 : 2,
      shadowColor: p.shadow.withValues(alpha: isRead ? 0 : 0.06),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _handleNotificationTap(item),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isRead
                  ? p.hairline.withValues(alpha: 0.6)
                  : item.iconColor.withValues(alpha: 0.35),
              width: isRead ? 1.0 : 1.2,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Unread left accent strip
                if (!isRead)
                  Container(
                    width: 4.5,
                    height: 80,
                    color: item.iconColor,
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Icon with status background
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: iconBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Icon(item.icon, size: 22, color: iconColor),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Title, Body, and Timestamp
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      style: textTheme.titleSmall?.copyWith(
                                        fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                                        color: titleColor,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ),
                                  if (!isRead) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: item.iconColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'NEW',
                                        style: TextStyle(
                                          color: item.iconColor,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.body,
                                style: textTheme.bodySmall?.copyWith(
                                  color: bodyColor,
                                  height: 1.35,
                                  fontSize: 12,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item.timeAgo,
                                style: textTheme.bodySmall?.copyWith(
                                  color: isRead ? p.textTertiary : p.textSecondary,
                                  fontSize: 11,
                                  fontWeight: isRead ? FontWeight.normal : FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppPaletteData p, TextTheme textTheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: p.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.notifications_none_rounded, size: 36, color: p.primary),
            ),
            const SizedBox(height: 16),
            Text(
              _selectedFilter == 'unread' ? 'No unread notifications' : 'No notifications yet',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Activity on complaints, join approvals, and society notices will appear here.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
