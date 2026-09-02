import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/visitor_models.dart';
import '../../services/notifications_service.dart';
import '../../services/visitors_service.dart';
import '../../theme/app_theme.dart';
import 'admin_log_visitor_screen.dart';
import 'admin_verify_preapproval_screen.dart';
import 'visitor_detail_screen.dart';
import 'widgets/visitor_card.dart';

class AdminVisitorsDashboard extends StatefulWidget {
  final bool showBack;

  const AdminVisitorsDashboard({super.key, this.showBack = true});

  @override
  State<AdminVisitorsDashboard> createState() =>
      _AdminVisitorsDashboardState();
}

class _AdminVisitorsDashboardState extends State<AdminVisitorsDashboard> {
  bool _loading = true;
  String? _error;
  List<VisitorRecord> _visitors = [];
  String _statusFilter = 'all';
  String _categoryFilter = 'all';
  DateTime? _dateFilter;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    NotificationsService.instance.markModuleAsRead('visitor');
    _loadVisitors();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVisitors() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await VisitorsService.instance.fetchSocietyVisitors(
        statusFilter: _statusFilter,
        categoryFilter: _categoryFilter,
        dateFilter: _dateFilter,
        searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
      );
      if (mounted) {
        setState(() {
          _visitors = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    final pendingCount =
        _visitors.where((v) => v.isPending).length;
    final todayCount = _visitors
        .where((v) {
          final today = DateTime.now();
          return v.createdAt.year == today.year &&
              v.createdAt.month == today.month &&
              v.createdAt.day == today.day;
        })
        .length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
                children: [
                  if (widget.showBack)
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: p.card,
                        side: BorderSide(color: p.hairline),
                      ),
                    ),
                  if (widget.showBack) const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Visitor Management',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  // Verify button
                  IconButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminVerifyPreapprovalScreen(),
                      ),
                    ).then((_) => _loadVisitors()),
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    tooltip: 'Verify Pre-Approval',
                    style: IconButton.styleFrom(
                      backgroundColor: p.card,
                      side: BorderSide(color: p.hairline),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Stats row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _statChip(
                    p,
                    Icons.people_alt_rounded,
                    '$todayCount',
                    'Today',
                    p.primary,
                  ),
                  const SizedBox(width: 8),
                  _statChip(
                    p,
                    Icons.hourglass_top_rounded,
                    '$pendingCount',
                    'Pending',
                    p.warning,
                  ),
                  const SizedBox(width: 8),
                  _statChip(
                    p,
                    Icons.check_circle_rounded,
                    '${_visitors.where((v) => v.isApproved).length}',
                    'Approved',
                    p.success,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (q) {
                  _searchQuery = q;
                  _loadVisitors();
                },
                decoration: InputDecoration(
                  hintText: 'Search by name, phone, flat, or code...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            _searchQuery = '';
                            _loadVisitors();
                          },
                          icon: const Icon(Icons.clear_rounded, size: 18),
                        )
                      : null,
                  filled: true,
                  fillColor: p.card,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: p.hairline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: p.hairline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: p.primary, width: 1.5),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Filter chips
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _filterChip(p, 'All', 'all', _statusFilter,
                      (v) => setState(() {
                            _statusFilter = v;
                            _loadVisitors();
                          })),
                  _filterChip(p, 'Pending', 'pending_approval', _statusFilter,
                      (v) => setState(() {
                            _statusFilter = v;
                            _loadVisitors();
                          })),
                  _filterChip(p, 'Approved', 'approved', _statusFilter,
                      (v) => setState(() {
                            _statusFilter = v;
                            _loadVisitors();
                          })),
                  _filterChip(p, 'Checked In', 'checked_in', _statusFilter,
                      (v) => setState(() {
                            _statusFilter = v;
                            _loadVisitors();
                          })),
                  _filterChip(p, 'Denied', 'denied', _statusFilter,
                      (v) => setState(() {
                            _statusFilter = v;
                            _loadVisitors();
                          })),
                  const SizedBox(width: 8),
                  // Date filter
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _dateFilter ?? DateTime.now(),
                        firstDate: DateTime.now()
                            .subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (picked != null) {
                        setState(() => _dateFilter = picked);
                        _loadVisitors();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _dateFilter != null
                            ? p.primary.withValues(alpha: 0.12)
                            : p.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _dateFilter != null
                              ? p.primary
                              : p.hairline,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_rounded,
                              size: 14,
                              color: _dateFilter != null
                                  ? p.primary
                                  : p.textTertiary),
                          const SizedBox(width: 4),
                          Text(
                            _dateFilter != null
                                ? DateFormat('dd MMM').format(_dateFilter!)
                                : 'Date',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _dateFilter != null
                                  ? p.primary
                                  : p.textSecondary,
                            ),
                          ),
                          if (_dateFilter != null) ...[
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () {
                                setState(() => _dateFilter = null);
                                _loadVisitors();
                              },
                              child: Icon(Icons.close_rounded,
                                  size: 14, color: p.primary),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // List
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline_rounded,
                                  size: 48, color: p.danger),
                              const SizedBox(height: 8),
                              Text('Error: $_error'),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _loadVisitors,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : _visitors.isEmpty
                          ? _buildEmpty(p, textTheme)
                          : RefreshIndicator(
                              onRefresh: _loadVisitors,
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 4, 16, 100),
                                itemCount: _visitors.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final v = _visitors[index];
                                  return VisitorCard(
                                    visitor: v,
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              VisitorDetailScreen(
                                                  visitorId: v.id),
                                        ),
                                      ).then((_) => _loadVisitors());
                                    },
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminLogVisitorScreen(),
            ),
          ).then((_) => _loadVisitors());
        },
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Log Visitor'),
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
      ),
    );
  }

  Widget _buildEmpty(AppPaletteData p, TextTheme textTheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: p.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.people_outline_rounded,
                size: 32, color: p.textTertiary),
          ),
          const SizedBox(height: 16),
          Text(
            'No visitors found',
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Visitor entries will appear here',
            style: textTheme.bodySmall?.copyWith(color: p.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _statChip(
    AppPaletteData p,
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: color.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(
    AppPaletteData p,
    String label,
    String value,
    String currentFilter,
    ValueChanged<String> onSelect,
  ) {
    final isSelected = value == currentFilter;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => onSelect(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? p.primary.withValues(alpha: 0.12) : p.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? p.primary : p.hairline,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? p.primary : p.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
