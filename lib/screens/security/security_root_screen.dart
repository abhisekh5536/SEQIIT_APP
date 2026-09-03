import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/security_models.dart';
import '../../services/app_session.dart';
import '../../services/notifications_service.dart';
import '../../services/security_service.dart';
import 'widgets/admin_sos_alert_dialog.dart';
import 'widgets/call_history_sheet.dart';
import 'widgets/category_form_dialog.dart';
import 'widgets/contact_form_dialog.dart';
import 'widgets/sos_active_banner.dart';
import 'widgets/sos_dialog.dart';
import 'widgets/sos_history_sheet.dart';

class SecurityRootScreen extends StatefulWidget {
  const SecurityRootScreen({super.key});

  @override
  State<SecurityRootScreen> createState() => _SecurityRootScreenState();
}

class _SecurityRootScreenState extends State<SecurityRootScreen>
    with SingleTickerProviderStateMixin {
  TabController? _adminTabController;

  bool _loading = true;
  List<EmergencyCategory> _categories = [];
  List<EmergencyContact> _contacts = [];
  List<SosAlert> _myActiveAlerts = [];
  List<SosAlert> _mySosHistory = [];
  List<SosAlert> _societyAlerts = [];
  List<EmergencyCallLog> _societyCallLogs = [];

  String? _selectedCategoryFilter;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final isAdmin = AppSession.instance.isAdmin;
    if (isAdmin) {
      _adminTabController = TabController(length: 3, vsync: this);
    }
    // Auto mark security & SOS notifications as read on screen opening
    NotificationsService.instance.markModuleAsRead('sos_alert');
    NotificationsService.instance.markModuleAsRead('security');
    SecurityService.instance.addListener(_onSecurityServiceChanged);

    _initData();
  }

  @override
  void dispose() {
    SecurityService.instance.removeListener(_onSecurityServiceChanged);
    _adminTabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSecurityServiceChanged() {
    if (mounted) {
      _refreshData();
    }
  }

  Future<void> _initData() async {
    setState(() => _loading = true);
    final societyId = AppSession.instance.societyId;
    if (societyId != null) {
      SecurityService.instance.initRealtime(societyId);
    }

    await _refreshData();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshData() async {
    final societyId = AppSession.instance.societyId;
    if (societyId == null) return;

    final isAdmin = AppSession.instance.isAdmin;

    try {
      final categoriesFuture = SecurityService.instance.fetchCategories(societyId);
      final contactsFuture = SecurityService.instance.fetchContacts(
        societyId,
        activeOnly: !isAdmin,
      );

      if (isAdmin) {
        final alertsFuture = SecurityService.instance.fetchSocietySosAlerts(societyId);
        final callLogsFuture = SecurityService.instance.fetchSocietyCallLogs(societyId);

        final results = await Future.wait([
          categoriesFuture,
          contactsFuture,
          alertsFuture,
          callLogsFuture,
        ]);

        if (!mounted) return;
        setState(() {
          _categories = results[0] as List<EmergencyCategory>;
          _contacts = results[1] as List<EmergencyContact>;
          _societyAlerts = results[2] as List<SosAlert>;
          _societyCallLogs = results[3] as List<EmergencyCallLog>;
        });
      } else {
        final flatIds =
            AppSession.instance.myResidences.map((r) => r.flatId).toList();
        final alertsFuture =
            SecurityService.instance.fetchMyActiveSosAlerts(flatIds);
        final historyFuture =
            SecurityService.instance.fetchMySosHistory(flatIds);

        final results = await Future.wait([
          categoriesFuture,
          contactsFuture,
          alertsFuture,
          historyFuture,
        ]);

        if (!mounted) return;
        setState(() {
          _categories = results[0] as List<EmergencyCategory>;
          _contacts = results[1] as List<EmergencyContact>;
          _myActiveAlerts = results[2] as List<SosAlert>;
          _mySosHistory = results[3] as List<SosAlert>;
        });
      }
    } catch (e) {
      debugPrint('SecurityRootScreen._refreshData error: $e');
    }
  }

  List<EmergencyContact> get _filteredContacts {
    var list = _contacts;
    if (_selectedCategoryFilter != null && _selectedCategoryFilter != 'all') {
      list = list
          .where((c) => c.categoryId == _selectedCategoryFilter)
          .toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      list = list.where((c) {
        final nameMatch = c.name.toLowerCase().contains(q);
        final desigMatch = c.designation?.toLowerCase().contains(q) ?? false;
        final phoneMatch = c.phoneNumber.contains(q);
        final catMatch = c.categoryName?.toLowerCase().contains(q) ?? false;
        return nameMatch || desigMatch || phoneMatch || catMatch;
      }).toList();
    }
    return list;
  }

  // ─────────────────────────────────────────────────────────────
  // Resident View
  // ─────────────────────────────────────────────────────────────

  Widget _buildResidentView(bool isDark) {
    final globalContacts = _filteredContacts.where((c) => c.isGlobal).toList();
    final societyContacts = _filteredContacts.where((c) => !c.isGlobal).toList();

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Active SOS Banner if any open
          if (_myActiveAlerts.isNotEmpty) ...[
            ..._myActiveAlerts.map(
              (alert) => SosActiveBanner(
                alert: alert,
                onUpdated: _refreshData,
              ),
            ),
          ],

          // Big Tactile SOS Action Card
          _buildSosEmergencyCard(isDark),

          const SizedBox(height: 16),

          // Search Bar
          TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'Search contacts, doctor, guard, plumber...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: isDark ? const Color(0xFF262626) : Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),

          const SizedBox(height: 12),

          // Category Chips Filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _selectedCategoryFilter == null || _selectedCategoryFilter == 'all',
                  onSelected: (_) => setState(() => _selectedCategoryFilter = null),
                ),
                const SizedBox(width: 8),
                ..._categories.map((cat) {
                  final isSelected = _selectedCategoryFilter == cat.id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(cat.icon, size: 16),
                      label: Text(cat.name),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _selectedCategoryFilter = cat.id),
                    ),
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Pinned National Emergency Numbers
          if (globalContacts.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.emergency_rounded, size: 18, color: Color(0xFFD32F2F)),
                const SizedBox(width: 6),
                Text(
                  'National Emergency Helplines',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.grey[300] : Colors.grey[800],
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...globalContacts.map((c) => _buildContactCard(c, isDark, isPinned: true)),
            const SizedBox(height: 16),
          ],

          // Society Contacts Section
          Row(
            children: [
              const Icon(Icons.location_city_rounded, size: 18, color: Colors.teal),
              const SizedBox(width: 6),
              Text(
                'Society Contacts & Services',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.grey[300] : Colors.grey[800],
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (societyContacts.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32),
              alignment: Alignment.center,
              child: Text(
                _searchQuery.isNotEmpty
                    ? 'No society contacts matching "$_searchQuery"'
                    : 'No society contacts listed yet.',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            )
          else
            ...societyContacts.map((c) => _buildContactCard(c, isDark)),

          // SOS History Section (User Panel)
          if (_mySosHistory.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.history_rounded, size: 18, color: Color(0xFFD32F2F)),
                    const SizedBox(width: 6),
                    Text(
                      'Emergency SOS History (${_mySosHistory.length})',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.grey[300] : Colors.grey[800],
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => SosHistorySheet.show(context, initialAlerts: _mySosHistory),
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._mySosHistory.take(3).map((a) => _buildResidentSosHistoryCard(a, isDark)),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSosEmergencyCard(bool isDark) {
    return InkWell(
      onTap: () async {
        final res = await SosDialog.show(context, onAlertCreated: () {
          _refreshData();
        });
        if (res == true || mounted) {
          await _refreshData();
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFD32F2F), Color(0xFFC2185B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD32F2F).withAlpha(80),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(50),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.crisis_alert_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EMERGENCY SOS',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      letterSpacing: 0.8,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Instant alert to Guards & Admin with your flat number',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard(EmergencyContact contact, bool isDark, {bool isPinned = false}) {
    final primaryFlat = AppSession.instance.primaryResidence?.flatId ??
        (AppSession.instance.myResidences.isNotEmpty
            ? AppSession.instance.myResidences.first.flatId
            : null);
    final societyId = AppSession.instance.societyId;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: isPinned ? 1.5 : 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isPinned
              ? const Color(0xFFD32F2F).withAlpha(50)
              : (isDark ? Colors.grey[800]! : Colors.grey[200]!),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isPinned
                    ? const Color(0xFFD32F2F).withAlpha(20)
                    : Theme.of(context).primaryColor.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(
                SecurityIconHelper.getIconData(contact.categoryIconKey),
                color: isPinned
                    ? const Color(0xFFD32F2F)
                    : Theme.of(context).primaryColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),

            // Contact Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          contact.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (contact.availability.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[800] : Colors.grey[200],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            contact.availability,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.grey[300] : Colors.grey[700],
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (contact.designation != null && contact.designation!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      contact.designation!,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        contact.phoneNumber,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isPinned ? const Color(0xFFD32F2F) : Colors.teal,
                        ),
                      ),
                      if (contact.alternatePhoneNumber != null &&
                          contact.alternatePhoneNumber!.isNotEmpty)
                        Text(
                          ' / ${contact.alternatePhoneNumber}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Copy Number',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: contact.phoneNumber));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Phone number copied to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Call Button
            ElevatedButton(
              onPressed: () {
                SecurityService.instance.launchCall(
                  phoneNumber: contact.phoneNumber,
                  societyId: societyId,
                  contactId: contact.id,
                  flatId: primaryFlat,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isPinned ? const Color(0xFFD32F2F) : Colors.teal,
                foregroundColor: Colors.white,
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(12),
                elevation: 2,
              ),
              child: const Icon(Icons.phone_in_talk, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Admin View
  // ─────────────────────────────────────────────────────────────

  Widget _buildAdminView(bool isDark) {
    final activeAlerts = _societyAlerts.where((a) => a.isOpen).toList();

    return TabBarView(
      controller: _adminTabController,
      children: [
        // Tab 1: SOS Alerts
        _buildAdminSosTab(isDark, activeAlerts),

        // Tab 2: Directory Management
        _buildAdminDirectoryTab(isDark),

        // Tab 3: Call Logs & Analytics
        _buildAdminCallLogsTab(isDark),
      ],
    );
  }

  Widget _buildAdminSosTab(bool isDark, List<SosAlert> activeAlerts) {
    final resolvedAlerts = _societyAlerts.where((a) => !a.isOpen).toList();

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Active SOS Alerts Section
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: activeAlerts.isNotEmpty ? Colors.red : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Active Emergencies (${activeAlerts.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (activeAlerts.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF262626) : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'All clear! No active SOS alerts.',
                    style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            )
          else
            ...activeAlerts.map((a) => _buildAdminSosCard(a, isDark, isActive: true)),

          const SizedBox(height: 24),

          // Past Alerts Section
          const Text(
            'Emergency History',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          if (resolvedAlerts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No past emergency alerts recorded.',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ),
            )
          else
            ...resolvedAlerts.map((a) => _buildAdminSosCard(a, isDark, isActive: false)),
        ],
      ),
    );
  }

  Widget _buildAdminSosCard(SosAlert alert, bool isDark, {required bool isActive}) {
    final timeStr = DateFormat('h:mm a, d MMM').format(alert.createdAt.toLocal());

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isActive ? alert.alertType.color : Colors.transparent,
          width: isActive ? 1.5 : 0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: alert.alertType.color.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(alert.alertType.icon, color: alert.alertType.color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.alertType.label,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        'Unit: ${alert.formattedFlat} · Raised: $timeStr',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: alert.status.color.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    alert.status.label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: alert.status.color,
                    ),
                  ),
                ),
              ],
            ),
            if (alert.residentName != null || alert.residentPhone != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    '${alert.residentName ?? "Resident"} (${alert.residentPhone ?? "No phone"})',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
            if (alert.note != null && alert.note!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF252525) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Note: "${alert.note}"',
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (alert.residentPhone != null && alert.residentPhone!.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      SecurityService.instance.launchCall(
                        phoneNumber: alert.residentPhone!,
                        societyId: alert.societyId,
                        flatId: alert.flatId,
                      );
                    },
                    icon: const Icon(Icons.phone, size: 16),
                    label: const Text('Call Resident'),
                  ),
                const SizedBox(width: 8),
                if (alert.isActive)
                  ElevatedButton(
                    onPressed: () async {
                      await SecurityService.instance.acknowledgeSosAlert(alert.id);
                      _refreshData();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0288D1),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Acknowledge'),
                  )
                else if (alert.isAcknowledged)
                  ElevatedButton(
                    onPressed: () async {
                      await SecurityService.instance.resolveSosAlert(alert.id);
                      _refreshData();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Mark Resolved'),
                  )
                else
                  TextButton(
                    onPressed: () => AdminSosAlertDialog.show(context, alert),
                    child: const Text('Details'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminDirectoryTab(bool isDark) {
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Action Buttons: Manage Categories + Add Contact
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    CategoryFormDialog.show(context, onSaved: _refreshData);
                  },
                  icon: const Icon(Icons.category_outlined, size: 18),
                  label: const Text('Add Category'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    ContactFormDialog.show(
                      context,
                      categories: _categories,
                      onSaved: _refreshData,
                    );
                  },
                  icon: const Icon(Icons.person_add_outlined, size: 18),
                  label: const Text('Add Contact'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Categories Filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _selectedCategoryFilter == null,
                  onSelected: (_) => setState(() => _selectedCategoryFilter = null),
                ),
                const SizedBox(width: 8),
                ..._categories.map((cat) {
                  final isSelected = _selectedCategoryFilter == cat.id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(cat.icon, size: 16),
                      label: Text(cat.name + (cat.isGlobal ? ' (Global)' : '')),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _selectedCategoryFilter = cat.id),
                    ),
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Contacts List
          ..._filteredContacts.map((c) {
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withAlpha(20),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    SecurityIconHelper.getIconData(c.categoryIconKey),
                    color: Theme.of(context).primaryColor,
                    size: 20,
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (c.isGlobal)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Global', style: TextStyle(fontSize: 10, color: Colors.blue)),
                      )
                    else
                      Switch(
                        value: c.isActive,
                        onChanged: (val) async {
                          await SecurityService.instance.toggleContactActive(c.id, val);
                          _refreshData();
                        },
                      ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (c.designation != null) Text(c.designation!),
                    Text(
                      '${c.phoneNumber} · ${c.availability}',
                      style: TextStyle(color: Colors.teal[700], fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                trailing: c.isGlobal
                    ? null
                    : PopupMenuButton<String>(
                        onSelected: (val) async {
                          if (val == 'edit') {
                            ContactFormDialog.show(
                              context,
                              contact: c,
                              categories: _categories,
                              onSaved: _refreshData,
                            );
                          } else if (val == 'delete') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete Contact?'),
                                content: Text('Remove "${c.name}" from directory?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await SecurityService.instance.deleteContact(c.id);
                              _refreshData();
                            }
                          }
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAdminCallLogsTab(bool isDark) {
    // Analytics Metrics
    final totalCalls = _societyCallLogs.length;

    // Most called contact calculation
    final Map<String, int> contactCounts = {};
    for (final log in _societyCallLogs) {
      final name = log.contactName ?? log.contactPhone ?? 'Unknown';
      contactCounts[name] = (contactCounts[name] ?? 0) + 1;
    }
    String topContact = 'None';
    int topContactCount = 0;
    contactCounts.forEach((k, v) {
      if (v > topContactCount) {
        topContact = k;
        topContactCount = v;
      }
    });

    // Calls per flat count
    final Set<String> activeFlats = {};
    for (final log in _societyCallLogs) {
      if (log.flatNumber != null) activeFlats.add(log.flatNumber!);
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // KPI Metric Cards Row
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Total Calls',
                  '$totalCalls',
                  Icons.phone_in_talk,
                  Colors.teal,
                  isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricCard(
                  'Most Called',
                  topContact,
                  Icons.star_rounded,
                  Colors.amber[800]!,
                  isDark,
                  subtitle: topContactCount > 0 ? '$topContactCount calls' : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricCard(
                  'Units Active',
                  '${activeFlats.length}',
                  Icons.apartment_rounded,
                  Colors.blue,
                  isDark,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Call Logs Table Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Call Attempts',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                '${_societyCallLogs.length} total entries',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),

          const SizedBox(height: 10),

          if (_societyCallLogs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No emergency or vendor calls logged yet.',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ),
            )
          else
            ..._societyCallLogs.map((log) {
              final formattedTime = DateFormat('d MMM, h:mm a').format(log.calledAt.toLocal());
              final flatDisplay = log.blockName != null
                  ? '${log.blockName}-${log.flatNumber ?? ""}'
                  : (log.flatNumber ?? 'Flat');

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.call_made_rounded, color: Colors.teal, size: 18),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          log.contactName ?? 'Emergency Contact',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.grey[200],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Unit: $flatDisplay',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    '${log.contactPhone ?? ""} · $formattedTime',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    IconData icon,
    Color color,
    bool isDark, {
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF262626) : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildResidentSosHistoryCard(SosAlert alert, bool isDark) {
    final timeStr = DateFormat('d MMM, h:mm a').format(alert.createdAt.toLocal());

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: alert.alertType.color.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(alert.alertType.icon, color: alert.alertType.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          alert.alertType.label,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                  const SizedBox(height: 2),
                  Text(
                    'Raised on $timeStr',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  if (alert.note != null && alert.note!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '"${alert.note}"',
                      style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () async {
                final history = await SecurityService.instance.fetchSosHistoryTrail(alert.id);
                if (!mounted) return;
                _showTimelineSheet(alert, history);
              },
              child: const Text('Trail'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTimelineSheet(SosAlert alert, List<SosStatusHistory> history) {
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
    final isAdmin = AppSession.instance.isAdmin;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(isAdmin ? 'Security Management' : 'Security & Helplines'),
        actions: [
          if (!isAdmin) ...[
            IconButton(
              icon: const Icon(Icons.crisis_alert_rounded),
              tooltip: 'SOS History',
              onPressed: () => SosHistorySheet.show(context, initialAlerts: _mySosHistory),
            ),
            IconButton(
              icon: const Icon(Icons.history_rounded),
              tooltip: 'Call History',
              onPressed: () => CallHistorySheet.show(context),
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _refreshData,
            ),
        ],
        bottom: isAdmin && _adminTabController != null
            ? TabBar(
                controller: _adminTabController,
                tabs: [
                  Tab(
                    icon: Badge(
                      isLabelVisible: _societyAlerts.any((a) => a.isOpen),
                      backgroundColor: Colors.red,
                      smallSize: 8,
                      child: const Icon(Icons.crisis_alert_rounded, size: 20),
                    ),
                    text: 'SOS Alerts',
                  ),
                  const Tab(
                    icon: Icon(Icons.contacts_outlined, size: 20),
                    text: 'Directory',
                  ),
                  const Tab(
                    icon: Icon(Icons.analytics_outlined, size: 20),
                    text: 'Call Logs',
                  ),
                ],
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : isAdmin
              ? _buildAdminView(isDark)
              : _buildResidentView(isDark),
    );
  }
}
