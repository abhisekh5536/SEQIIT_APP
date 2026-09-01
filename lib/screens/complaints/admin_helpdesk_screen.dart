import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/complaint_models.dart';
import '../../services/app_session.dart';
import '../../services/complaints_service.dart';
import '../../theme/app_theme.dart';
import 'admin_complaint_detail_screen.dart';

class AdminHelpdeskScreen extends StatefulWidget {
  final bool showBack;

  const AdminHelpdeskScreen({super.key, this.showBack = true});

  @override
  State<AdminHelpdeskScreen> createState() => _AdminHelpdeskScreenState();
}

class _AdminHelpdeskScreenState extends State<AdminHelpdeskScreen> {
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<ComplaintRecord> _allComplaints = [];
  HelpdeskStats _stats = const HelpdeskStats();

  String _statusFilter = 'all';
  String _categoryFilter = 'all';
  String _priorityFilter = 'all';
  String _sortBy = 'newest'; // 'newest' | 'oldest' | 'priority'

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        ComplaintsService.instance.fetchSocietyComplaints(
          statusFilter: _statusFilter,
          categoryFilter: _categoryFilter,
          priorityFilter: _priorityFilter,
          searchQuery: _searchController.text,
          sortBy: _sortBy,
        ),
        ComplaintsService.instance.getSocietyHelpdeskStats(),
      ]);

      if (mounted) {
        setState(() {
          _allComplaints = results[0] as List<ComplaintRecord>;
          _stats = results[1] as HelpdeskStats;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load helpdesk queue: $e';
          _loading = false;
        });
      }
    }
  }

  void _onFilterChanged() {
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: p.primary,
          child: CustomScrollView(
            slivers: [
              // Header Sliver
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                          if (widget.showBack) const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Helpdesk Queue',
                                  style: textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                Text(
                                  AppSession.instance.societyName,
                                  style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _loadData,
                            icon: const Icon(Icons.refresh_rounded),
                            tooltip: 'Refresh',
                            style: IconButton.styleFrom(
                              backgroundColor: p.card,
                              side: BorderSide(color: p.hairline),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Metrics Cards Row
                      _buildStatsRow(p, textTheme),
                      const SizedBox(height: 16),

                      // Search bar
                      TextField(
                        controller: _searchController,
                        onSubmitted: (_) => _onFilterChanged(),
                        decoration: InputDecoration(
                          hintText: 'Search complaints, flats, residents...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    _onFilterChanged();
                                  },
                                )
                              : null,
                          fillColor: p.card,
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: p.hairline),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: p.hairline),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Filter chips row: Status
                      _buildFilterRow(
                        title: 'Status',
                        selected: _statusFilter,
                        options: const [
                          {'label': 'All', 'value': 'all'},
                          {'label': 'Open', 'value': 'open'},
                          {'label': 'In Progress', 'value': 'in_progress'},
                          {'label': 'Resolved', 'value': 'resolved'},
                          {'label': 'Reopened', 'value': 'reopened'},
                          {'label': 'Closed', 'value': 'closed'},
                        ],
                        onSelected: (val) {
                          setState(() => _statusFilter = val);
                          _onFilterChanged();
                        },
                        p: p,
                      ),
                      const SizedBox(height: 8),

                      // Filter chips row: Category & Sorting
                      Row(
                        children: [
                          Expanded(
                            child: _buildDropdownFilter(
                              label: 'Category',
                              value: _categoryFilter,
                              items: const [
                                DropdownMenuItem(value: 'all', child: Text('All Categories')),
                                DropdownMenuItem(value: 'plumbing', child: Text('Plumbing')),
                                DropdownMenuItem(value: 'electrical', child: Text('Electrical')),
                                DropdownMenuItem(value: 'security', child: Text('Security (Alerts)')),
                                DropdownMenuItem(value: 'cleanliness', child: Text('Cleanliness')),
                                DropdownMenuItem(value: 'billing', child: Text('Billing')),
                                DropdownMenuItem(value: 'lift', child: Text('Lift')),
                                DropdownMenuItem(value: 'other', child: Text('Other')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _categoryFilter = val);
                                  _onFilterChanged();
                                }
                              },
                              p: p,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildDropdownFilter(
                              label: 'Sort By',
                              value: _sortBy,
                              items: const [
                                DropdownMenuItem(value: 'newest', child: Text('Newest first')),
                                DropdownMenuItem(value: 'oldest', child: Text('Oldest first')),
                                DropdownMenuItem(value: 'priority', child: Text('High Priority')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _sortBy = val);
                                  _onFilterChanged();
                                }
                              },
                              p: p,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),

              // Queue List Sliver
              if (_loading)
                SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: p.primary)),
                )
              else if (_error != null)
                SliverFillRemaining(
                  child: _buildErrorView(context, p, textTheme),
                )
              else if (_allComplaints.isEmpty)
                SliverFillRemaining(
                  child: _buildEmptyView(p, textTheme),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final complaint = _allComplaints[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildAdminComplaintCard(context, complaint, p, textTheme),
                        );
                      },
                      childCount: _allComplaints.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow(AppPaletteData p, TextTheme textTheme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildStatCard('Open', _stats.open.toString(), const Color(0xFF64748B), const Color(0xFFF1F5F9)),
          const SizedBox(width: 8),
          _buildStatCard('In Progress', _stats.inProgress.toString(), const Color(0xFFD97706), const Color(0xFFFEF3C7)),
          const SizedBox(width: 8),
          _buildStatCard('Reopened', _stats.reopened.toString(), const Color(0xFFDC2626), const Color(0xFFFEE2E2)),
          const SizedBox(width: 8),
          _buildStatCard('Resolved', _stats.resolved.toString(), const Color(0xFF2563EB), const Color(0xFFDBEAFE)),
          if (_stats.securityCount > 0) ...[
            const SizedBox(width: 8),
            _buildStatCard('Security ⚠', _stats.securityCount.toString(), const Color(0xFFB91C1C), const Color(0xFFFFE4E6)),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow({
    required String title,
    required String selected,
    required List<Map<String, String>> options,
    required ValueChanged<String> onSelected,
    required AppPaletteData p,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((opt) {
          final isSelected = selected == opt['value'];
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(opt['label']!),
              selected: isSelected,
              onSelected: (_) => onSelected(opt['value']!),
              selectedColor: p.primary,
              backgroundColor: p.card,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : p.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: isSelected ? p.primary : p.hairline),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDropdownFilter({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
    required AppPaletteData p,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.hairline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          items: items,
          onChanged: onChanged,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.textPrimary),
        ),
      ),
    );
  }

  Widget _buildAdminComplaintCard(
    BuildContext context,
    ComplaintRecord item,
    AppPaletteData p,
    TextTheme textTheme,
  ) {
    final cat = item.category;
    final status = item.status;
    final isSecurity = item.isSecurity;

    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          HapticFeedback.lightImpact();
          final updated = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => AdminComplaintDetailScreen(complaintId: item.id),
            ),
          );
          if (updated == true) {
            _loadData();
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSecurity
                  ? const Color(0xFFEF4444)
                  : item.isReopened
                      ? const Color(0xFFFCA5A5)
                      : p.hairline,
              width: isSecurity ? 2.0 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Security Alert Ribbon if category is security
              if (isSecurity) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFDC2626)),
                      SizedBox(width: 6),
                      Text(
                        'SECURITY ALERT · HIGH PRIORITY',
                        style: TextStyle(
                          color: Color(0xFFB91C1C),
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Top Row: Category + Flat + Status
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cat.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(cat.icon, size: 13, color: cat.color),
                        const SizedBox(width: 4),
                        Text(
                          cat.label,
                          style: TextStyle(
                            color: cat.color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item.flatDisplay,
                    style: textTheme.bodySmall?.copyWith(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _buildStatusBadge(status),
                ],
              ),
              const SizedBox(height: 10),

              // Title
              Text(
                item.title,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: p.textPrimary,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              if (item.description != null && item.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  item.description!,
                  style: textTheme.bodySmall?.copyWith(
                    color: p.textSecondary,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Resident & Assigned Info
              Row(
                children: [
                  Icon(Icons.person_outline_rounded, size: 14, color: p.textTertiary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      item.residentName ?? 'Resident',
                      style: textTheme.bodySmall?.copyWith(
                        color: p.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (item.assignedTo != null && item.assignedTo!.trim().isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: p.cardMuted,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Assigned: ${item.assignedTo!}',
                        style: TextStyle(color: p.primary, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    item.timeAgo,
                    style: textTheme.bodySmall?.copyWith(color: p.textTertiary, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(ComplaintStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: status.foreground, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              color: status.foreground,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView(AppPaletteData p, TextTheme textTheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, size: 54, color: p.textTertiary),
            const SizedBox(height: 16),
            Text(
              'No complaints in queue',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'No complaints matching the selected filters.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, AppPaletteData p, TextTheme textTheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: p.danger),
            const SizedBox(height: 16),
            Text('Error loading queue', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(_error ?? '', textAlign: TextAlign.center, style: textTheme.bodySmall?.copyWith(color: p.textSecondary)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loadData,
              style: FilledButton.styleFrom(backgroundColor: p.primary),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
