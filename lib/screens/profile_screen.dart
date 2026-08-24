import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/db_models.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';
import '../widgets/resident_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  Map<String, String> _blockNames = const {};
  bool _loadingBlocks = true;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadBlockNames();
    _loadCurrentUserId();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = AppSession.instance;
      if (!session.isLoaded && !session.isLoading) session.load();
    });
  }

  void _loadCurrentUserId() {
    try {
      _currentUserId = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      _currentUserId = null;
    }
  }

  Future<void> _loadBlockNames() async {
    final session = AppSession.instance;
    final blockIds = session.myResidences
        .map((r) => session.flatOf(r)?.blockId)
        .whereType<String>()
        .toSet()
        .toList();
    if (blockIds.isEmpty) {
      if (mounted) setState(() => _loadingBlocks = false);
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('blocks')
          .select('id, name')
          .inFilter('id', blockIds);
      final map = <String, String>{};
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        map[row['id'] as String] = (row['name'] ?? '') as String;
      }
      if (mounted) {
        setState(() {
          _blockNames = map;
          _loadingBlocks = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingBlocks = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: AppSession.instance,
          builder: (context, _) {
            final session = AppSession.instance;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: p.card,
                        side: BorderSide(color: p.hairline),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'My Profile',
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (session.isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  _profileCard(context, p, session),
                  if (session.isAdmin) ...[
                    const SizedBox(height: 16),
                    _adminInfo(context, p, session),
                  ] else if (session.myResidences.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: _emptyState(context, p, textTheme),
                    )
                  else ...[
                    for (final r in session.myResidences)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: _residenceCard(context, p, session, r),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: _vehiclesCard(context, p, session),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: _householdCard(context, p, session),
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // ---- shared helpers ----------------------------------------------------

  String _initials(String fullName) {
    final parts = fullName.split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String _monthYear(DateTime? date) {
    if (date == null) return '—';
    return '${_months[date.month - 1]} ${date.year}';
  }

  String? get _authEmail {
    try {
      return Supabase.instance.client.auth.currentUser?.email;
    } catch (_) {
      return null;
    }
  }

  Widget _sectionHead(
    BuildContext context,
    AppPaletteData p, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: p.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 19, color: p.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: textTheme.titleSmall),
              Text(subtitle,
                  style: textTheme.bodySmall?.copyWith(fontSize: 11.5)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pill(
    BuildContext context,
    AppPaletteData p, {
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  Widget _detailRow(
    BuildContext context,
    AppPaletteData p,
    IconData icon,
    String label,
    String value,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: p.textTertiary),
          const SizedBox(width: 10),
          SizedBox(width: 118, child: Text(label, style: textTheme.bodySmall)),
          Expanded(
            child: Text(
              value,
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ---- profile hero ------------------------------------------------------

  Widget _profileCard(BuildContext context, AppPaletteData p, AppSession s) {
    final textTheme = Theme.of(context).textTheme;
    final name = s.displayName ?? 'Signed in user';
    final isAdmin = s.isAdmin;
    final primary = s.primaryResidence;
    final roleLabel = isAdmin ? 'Society Admin' : (primary?.roleLabel ?? 'Member');

    final Color pillBg;
    final Color pillFg;
    if (isAdmin) {
      pillBg = p.primary.withValues(alpha: 0.14);
      pillFg = p.primary;
    } else if (primary?.isOwner ?? false) {
      pillBg = p.success.withValues(alpha: 0.14);
      pillFg = p.success;
    } else if (primary?.isFamily ?? false) {
      pillBg = p.warning.withValues(alpha: 0.14);
      pillFg = p.warning;
    } else {
      pillBg = p.secondary.withValues(alpha: 0.22);
      pillFg = p.onSecondary;
    }

    final email = primary?.email.isNotEmpty == true ? primary!.email : _authEmail;
    final phone = primary?.phone;

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ResidentAvatar(initials: _initials(name), size: 62),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _pill(context, p, label: roleLabel, bg: pillBg, fg: pillFg),
                  ],
                ),
              ),
            ],
          ),
          if ((email ?? '').isNotEmpty || (phone ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: p.hairline),
            const SizedBox(height: 14),
            if ((email ?? '').isNotEmpty)
              _detailRow(
                  context, p, Icons.mail_outline_rounded, 'Email', email!),
            if ((phone ?? '').isNotEmpty)
              _detailRow(
                  context, p, Icons.call_outlined, 'Phone', phone!),
          ],
        ],
      ),
    );
  }

  // ---- admin extra -------------------------------------------------------

  Widget _adminInfo(BuildContext context, AppPaletteData p, AppSession s) {
    final textTheme = Theme.of(context).textTheme;
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHead(
            context,
            p,
            icon: Icons.admin_panel_settings_outlined,
            title: 'Admin access',
            subtitle: 'You manage this society from the Directory',
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: p.hairline),
          const SizedBox(height: 14),
          _detailRow(context, p, Icons.apartment_outlined, 'Role',
              'Society administrator'),
          _detailRow(context, p, Icons.badge_outlined, 'Name',
              s.adminName ?? s.displayName ?? '—'),
          _detailRow(
              context, p, Icons.tag_rounded, 'Society ID', s.societyId ?? '—'),
          Text(
            'Use the Directory tab to manage flats, residents and their vehicles.',
            style: textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  // ---- residence ---------------------------------------------------------

  Widget _emptyState(
    BuildContext context,
    AppPaletteData p,
    TextTheme textTheme,
  ) {
    return Surface(
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: p.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.home_work_outlined, size: 34, color: p.primary),
          ),
          const SizedBox(height: 16),
          Text('No flat linked yet',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Your society office has not linked a flat to this account.\n'
            'Sign up with the email you gave to the office and your\n'
            'details will appear here automatically.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _residenceCard(
    BuildContext context,
    AppPaletteData p,
    AppSession s,
    ResidentRecord r,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final flat = s.flatOf(r);
    final blockName =
        _loadingBlocks ? null : (_blockNames[flat?.blockId] ?? '—');
    final locationParts = [
      if (blockName != null && blockName != '—') blockName,
      if (flat != null) 'Floor ${flat.floorNumber}',
      if (flat != null && flat.type.isNotEmpty) flat.type,
    ];

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [p.heroStart, p.heroEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.apartment_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      flat?.flatNumber ?? 'Flat pending',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      locationParts.join(' · '),
                      style: textTheme.bodySmall?.copyWith(
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _pill(
                context,
                p,
                label: flat?.isOccupied ?? true ? 'Occupied' : 'Vacant',
                bg: (flat?.isOccupied ?? true)
                    ? p.success.withValues(alpha: 0.14)
                    : p.warning.withValues(alpha: 0.14),
                fg: (flat?.isOccupied ?? true) ? p.success : p.warning,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: p.hairline),
          const SizedBox(height: 14),
          _detailRow(
              context, p, Icons.person_outline_rounded, 'Registered as',
              r.roleLabel),
          if (r.isPrimary)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _pill(
                context,
                p,
                label: 'Primary contact',
                bg: p.mint,
                fg: p.mintOn,
              ),
            ),
          if ((r.agreementHolderName ?? '').isNotEmpty)
            _detailRow(context, p, Icons.history_edu_outlined,
                'Agreement holder', r.agreementHolderName!),
          if (r.agreementDate != null)
            _detailRow(
              context,
              p,
              Icons.event_available_outlined,
              'Agreement date',
              '${r.agreementDate!.day}/${r.agreementDate!.month}/${r.agreementDate!.year}',
            ),
          if ((r.aadharLast4 ?? '').isNotEmpty)
            _detailRow(context, p, Icons.badge_outlined, 'Aadhar',
                '•••• ${r.aadharLast4}'),
          _detailRow(context, p, Icons.login_rounded, 'Member since',
              _monthYear(r.createdAt)),
        ],
      ),
    );
  }

  // ---- vehicles ----------------------------------------------------------

  bool _canManageVehicle(AppSession s, VehicleRecord v) {
    return s.myResidences.any((r) => r.id == v.residentId && r.userId != null);
  }

  Widget _vehiclesCard(BuildContext context, AppPaletteData p, AppSession s) {
    final textTheme = Theme.of(context).textTheme;
    final vehicles = s.myVehicles;

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHead(
            context,
            p,
            icon: Icons.directions_car_filled_outlined,
            title: 'Parking & vehicles',
            subtitle: vehicles.isEmpty
                ? 'Register your car and parking slot'
                : '${vehicles.length} vehicle${vehicles.length == 1 ? '' : 's'} registered',
          ),
          const SizedBox(height: 14),
          if (vehicles.isEmpty)
            Text(
              'No vehicles yet. Add your car with its number plate so '
              'security can verify it at the gate.',
              style: textTheme.bodySmall,
            )
          else
            Column(
              children: [
                for (var i = 0; i < vehicles.length; i++) ...[
                  if (i > 0) SizedBox(height: 10),
                  _vehicleTile(context, p, s, vehicles[i]),
                ],
              ],
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addVehicle,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
              label: const Text('Add vehicle'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vehicleTile(
    BuildContext context,
    AppPaletteData p,
    AppSession s,
    VehicleRecord v,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final canDelete = _canManageVehicle(s, v);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.cardMuted.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: p.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.directions_car_rounded,
                size: 22, color: p.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.makeModel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  v.registrationNo,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                if ((v.parkingSlot ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_parking_rounded,
                          size: 13, color: p.textTertiary),
                      const SizedBox(width: 4),
                      Text(
                        'Parking ${v.parkingSlot}',
                        style: textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (canDelete)
            IconButton(
              onPressed: () => _removeVehicle(v),
              icon: Icon(Icons.delete_outline_rounded,
                  size: 20, color: p.danger.withValues(alpha: 0.8)),
              tooltip: 'Remove vehicle',
            ),
        ],
      ),
    );
  }

  Future<void> _addVehicle() async {
    final session = AppSession.instance;
    final primary = session.primaryResidence;
    if (primary == null) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddVehicleDialog(primary: primary),
    );
    if (saved == true) await _refreshSession();
  }

  Future<void> _removeVehicle(VehicleRecord v) async {
    final confirmed = await _confirmDelete(
      title: 'Remove vehicle?',
      message: '${v.makeModel} (${v.registrationNo}) will be removed from your profile.',
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client
          .from('resident_vehicles')
          .delete()
          .eq('id', v.id);
      await _refreshSession();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(e.toString()))),
        );
      }
    }
  }

  // ---- household ---------------------------------------------------------

  List<ResidentRecord> _membersOf(AppSession s) {
    final mine = s.myResidences.map((r) => r.id).toSet();
    final userId = _currentUserId;
    return s.householdMembers
        .where((m) =>
            !mine.contains(m.id) &&
            (userId == null || m.userId != userId))
        .toList();
  }

  bool _canRemoveMember(ResidentRecord m) =>
      m.createdBy != null && m.createdBy == _currentUserId;

  Widget _householdCard(BuildContext context, AppPaletteData p, AppSession s) {
    final textTheme = Theme.of(context).textTheme;
    final members = _membersOf(s);

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHead(
            context,
            p,
            icon: Icons.family_restroom_rounded,
            title: 'Family & tenants',
            subtitle: members.isEmpty
                ? 'People living in your flat'
                : '${members.length} member${members.length == 1 ? '' : 's'} living with you',
          ),
          const SizedBox(height: 14),
          if (members.isEmpty)
            Text(
              'No family members or tenants added yet. Add the people '
              'living with you so the office has their details.',
              style: textTheme.bodySmall,
            )
          else
            Column(
              children: [
                for (var i = 0; i < members.length; i++) ...[
                  if (i > 0) SizedBox(height: 8),
                  _memberTile(context, p, members[i]),
                ],
              ],
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _addMember(true),
              icon: const Icon(Icons.family_restroom_rounded, size: 18),
              label: const Text('Add family member'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _addMember(false),
              icon: const Icon(Icons.key_rounded, size: 18),
              label: const Text('Add tenant'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberTile(BuildContext context, AppPaletteData p, ResidentRecord m) {
    final textTheme = Theme.of(context).textTheme;
    final subtitle = [
      if ((m.relation ?? '').isNotEmpty) m.relation!,
      m.phone ?? m.email,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          ResidentAvatar(initials: _initials(m.fullName), size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        m.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _pill(
                      context,
                      p,
                      label: m.roleLabel,
                      bg: m.isOwner
                          ? p.success.withValues(alpha: 0.14)
                          : m.isFamily
                              ? p.warning.withValues(alpha: 0.14)
                              : p.secondary.withValues(alpha: 0.22),
                      fg: m.isOwner
                          ? p.success
                          : m.isFamily
                              ? p.warning
                              : p.onSecondary,
                    ),
                  ],
                ),
                if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(fontSize: 11.5),
                    ),
                  ),
              ],
            ),
          ),
          if (_canRemoveMember(m))
            IconButton(
              onPressed: () => _removeMember(m),
              icon: Icon(Icons.delete_outline_rounded,
                  size: 20, color: p.danger.withValues(alpha: 0.8)),
              tooltip: 'Remove member',
            ),
        ],
      ),
    );
  }

  Future<void> _addMember(bool family) async {
    final session = AppSession.instance;
    final primary = session.primaryResidence;
    if (primary == null) return;
    final flat = session.flatOf(primary);
    if (flat == null) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddMemberSheet(
        societyId: primary.societyId,
        flatId: flat.id,
        flatLabel: flat.flatNumber,
        family: family,
        defaultHolderName: primary.fullName,
      ),
    );
    await _refreshSession();
  }

  Future<void> _removeMember(ResidentRecord m) async {
    final confirmed = await _confirmDelete(
      title: 'Remove ${m.fullName}?',
      message: '${m.fullName} will be removed from your flat\'s register.',
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client
          .from('residents')
          .delete()
          .eq('id', m.id);
      await _refreshSession();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(e.toString()))),
        );
      }
    }
  }

  // ---- misc --------------------------------------------------------------

  Future<bool?> _confirmDelete({
    required String title,
    required String message,
  }) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: p.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshSession() async {
    await AppSession.instance.load();
    if (mounted) setState(() {});
  }

  String _friendlyError(String raw) {
    if (raw.contains('residents_mandatory_fields_check')) {
      return 'All mandatory fields must be filled (phone, agreement holder/date, Aadhaar).';
    }
    if (raw.contains('violates row-level security')) {
      return 'Permission denied. Only the primary contact of a flat can manage its members.';
    }
    if (raw.contains('duplicate') || raw.contains('unique')) {
      return 'This person already exists in the register.';
    }
    return raw.length > 200 ? '${raw.substring(0, 200)}…' : raw;
  }
}

// ---- add vehicle dialog ------------------------------------------------------

class _AddVehicleDialog extends StatefulWidget {
  final ResidentRecord primary;

  const _AddVehicleDialog({required this.primary});

  @override
  State<_AddVehicleDialog> createState() => _AddVehicleDialogState();
}

class _AddVehicleDialogState extends State<_AddVehicleDialog> {
  final _make = TextEditingController();
  final _reg = TextEditingController();
  final _parking = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _make.dispose();
    _reg.dispose();
    _parking.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final make = _make.text.trim();
    final reg = _reg.text.trim().toUpperCase();
    final parking = _parking.text.trim();
    if (make.isEmpty || reg.isEmpty || _submitting) return;

    setState(() => _submitting = true);
    try {
      await Supabase.instance.client.from('resident_vehicles').insert({
        'society_id': widget.primary.societyId,
        'flat_id': widget.primary.flatId,
        'resident_id': widget.primary.id,
        'make_model': make,
        'registration_no': reg,
        if (parking.isNotEmpty) 'parking_slot': parking,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: const Text('Add vehicle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Car name & model *', style: textTheme.labelMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _make,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration:
                  const InputDecoration(hintText: 'e.g. Hyundai Creta'),
            ),
            const SizedBox(height: 16),
            Text('Registration number *', style: textTheme.labelMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _reg,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'e.g. HR-26 CY 9034'),
            ),
            const SizedBox(height: 16),
            Text('Parking slot', style: textTheme.labelMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _parking,
              decoration: const InputDecoration(hintText: 'e.g. B-08'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ---- add member sheet --------------------------------------------------------

class _AddMemberSheet extends StatefulWidget {
  final String societyId;
  final String flatId;
  final String flatLabel;
  final bool family;
  final String defaultHolderName;

  const _AddMemberSheet({
    required this.societyId,
    required this.flatId,
    required this.flatLabel,
    required this.family,
    required this.defaultHolderName,
  });

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _relation = TextEditingController();
  final _holder = TextEditingController();
  final _aadhar = TextEditingController();
  DateTime? _agreementDate;
  bool _triedSubmit = false;
  bool _submitting = false;

  bool get _family => widget.family;

  @override
  void initState() {
    super.initState();
    _holder.text = widget.defaultHolderName;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _relation.dispose();
    _holder.dispose();
    _aadhar.dispose();
    super.dispose();
  }

  bool _isEmailValid(String v) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _agreementDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _agreementDate = picked);
  }

  Future<void> _submit() async {
    setState(() => _triedSubmit = true);
    final name = _name.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    final holder = _holder.text.trim();
    final aadhar = _aadhar.text.trim();

    if (name.isEmpty ||
        !_isEmailValid(email) ||
        phone.isEmpty ||
        holder.isEmpty ||
        _agreementDate == null ||
        !RegExp(r'^[0-9]{4}$').hasMatch(aadhar)) {
      return;
    }

    setState(() => _submitting = true);
    try {
      await Supabase.instance.client.from('residents').insert({
        'society_id': widget.societyId,
        'flat_id': widget.flatId,
        'full_name': name,
        'email': email,
        'phone': phone,
        'resident_type': _family ? 'family' : 'tenant',
        'is_primary': false,
        'agreement_holder_name': holder,
        'agreement_date': _agreementDate!.toIso8601String().split('T')[0],
        'aadhar_last4': aadhar,
        'status': 'active',
        if (_family && _relation.text.trim().isNotEmpty)
          'relation': _relation.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name added to your flat.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final roleLabel = _family ? 'family member' : 'tenant';

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _family ? 'Add family member' : 'Add tenant',
                style: textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Flat ${widget.flatLabel} · they are linked automatically once '
                'they sign up with this email. All * fields are mandatory.',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Text('Full name *', style: textTheme.labelMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'e.g. Priya Roy',
                  errorText: _triedSubmit && _name.text.trim().isEmpty
                      ? 'Name is required'
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              Text('Email *', style: textTheme.labelMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'for automatic linking on signup',
                  errorText: _triedSubmit &&
                          !_isEmailValid(_email.text.trim())
                      ? 'Valid email is required'
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              Text('Phone *', style: textTheme.labelMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: 'e.g. +91 98100 12345',
                  errorText: _triedSubmit && _phone.text.trim().isEmpty
                      ? 'Phone is required'
                      : null,
                ),
              ),
              if (_family) ...[
                const SizedBox(height: 16),
                Text('Relation', style: textTheme.labelMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _relation,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Spouse, Son, Daughter…',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text('Agreement holder name *', style: textTheme.labelMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _holder,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  errorText: _triedSubmit && _holder.text.trim().isEmpty
                      ? 'Required'
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              Text('Agreement date *', style: textTheme.labelMedium),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color:
                          _triedSubmit && _agreementDate == null ? p.danger : p.hairline,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_outlined, size: 18, color: p.textTertiary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _agreementDate == null
                              ? 'Select date'
                              : '${_agreementDate!.day}/${_agreementDate!.month}/${_agreementDate!.year}',
                          style: textTheme.bodyMedium,
                        ),
                      ),
                      Icon(Icons.calendar_today_rounded,
                          size: 16, color: p.textTertiary),
                    ],
                  ),
                ),
              ),
              if (_triedSubmit && _agreementDate == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Agreement date is required',
                      style: textTheme.bodySmall?.copyWith(color: p.danger)),
                ),
              const SizedBox(height: 16),
              Text('Aadhaar last 4 digits *', style: textTheme.labelMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _aadhar,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: InputDecoration(
                  hintText: 'e.g. 1234',
                  counterText: '',
                  errorText: _triedSubmit &&
                          !RegExp(r'^[0-9]{4}$').hasMatch(_aadhar.text.trim())
                      ? 'Exactly 4 digits required'
                      : null,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text('Add $roleLabel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
