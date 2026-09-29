import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/guard_models.dart';
import '../../services/app_session.dart';
import '../../services/guard_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/resident_widgets.dart';
import '../../widgets/text_input_dialog.dart';
import '../vehicles/widgets/vehicle_parking_widgets.dart';

/// Society admin: who may work the gate, and what the gates are called.
///
/// Adding a guard here is what makes an account a guard — the app no longer
/// trusts anything the user can set on their own profile (migration 17).
class SecurityStaffScreen extends StatefulWidget {
  const SecurityStaffScreen({super.key});

  @override
  State<SecurityStaffScreen> createState() => _SecurityStaffScreenState();
}

class _SecurityStaffScreenState extends State<SecurityStaffScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() {
      if (mounted) setState(() {});
    });

  List<GuardProfile> _guards = const [];
  List<SocietyGate> _gates = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait<Object>([
        GuardService.instance.fetchGuards(),
        GuardService.instance.fetchAllGates(),
      ]);
      if (!mounted) return;
      setState(() {
        _guards = results[0] as List<GuardProfile>;
        _gates = results[1] as List<SocietyGate>;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _errorText(e);
        _loading = false;
      });
    }
  }

  static String _errorText(Object e) {
    if (e is PostgrestException) {
      if (e.code == '23505') {
        return 'A guard with this email is already listed.';
      }
      if (e.code == '42P01' || e.code == 'PGRST205') {
        return 'Guards are not set up on this database yet — run migrations 17 and 18.';
      }
      return e.message;
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  void _snack(String msg, {bool danger = false}) {
    if (!mounted) return;
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: danger ? p.danger : null,
      ),
    );
  }

  Future<void> _toggleGuard(GuardProfile g) async {
    final turningOff = g.isActive;
    if (turningOff) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Turn off ${g.firstName}?'),
          content: const Text(
            'Their gate access ends on their next action. Their past entries stay in the register.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Turn off'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await GuardService.instance.setGuardActive(g.id, !g.isActive);
      await _load();
      _snack(
        turningOff
            ? '${g.firstName} can no longer use the gate app'
            : '${g.firstName} is back on',
      );
    } catch (e) {
      _snack(_errorText(e), danger: true);
    }
  }

  Future<void> _editGuard([GuardProfile? existing]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GuardFormSheet(existing: existing, gates: _gates),
    );
    if (saved == true) {
      await _load();
      _snack(
        existing == null
            ? 'Guard added. They get access when they sign in with that email.'
            : 'Guard updated',
      );
    }
  }

  Future<void> _editGate([SocietyGate? existing]) async {
    final name = await showTextInputDialog(
      context,
      title: existing == null ? 'Add gate' : 'Rename gate',
      hint: 'e.g. Main Gate, Gate 2 (Service)',
      initialText: existing?.name ?? '',
      textCapitalization: TextCapitalization.words,
      requiredMessage: 'Enter a gate name',
    );
    if (name == null) return;
    try {
      if (existing == null) {
        await GuardService.instance.createGate(name);
      } else {
        await GuardService.instance.updateGate(existing.id, name: name);
      }
      await _load();
    } catch (e) {
      _snack(
        e is PostgrestException && e.code == '23505'
            ? 'A gate with that name already exists'
            : _errorText(e),
        danger: true,
      );
    }
  }

  Future<void> _toggleGate(SocietyGate g, bool active) async {
    try {
      await GuardService.instance.updateGate(g.id, isActive: active);
      await _load();
    } catch (e) {
      _snack(_errorText(e), danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final onGuards = _tabs.index == 0;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ModuleHeader(
              title: 'Guards & gates',
              subtitle: AppSession.instance.societyName,
            ),
            SegmentedTabs(
              controller: _tabs,
              labels: [
                'Guards (${_guards.length})',
                'Gates (${_gates.length})',
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? ModuleEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Could not load',
                      message: _error!,
                      actionLabel: 'Retry',
                      onAction: _load,
                    )
                  : TabBarView(
                      controller: _tabs,
                      children: [_guardsTab(p), _gatesTab(p)],
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: onGuards ? () => _editGuard() : () => _editGate(),
              icon: Icon(
                onGuards ? Icons.person_add_alt_1_rounded : Icons.add_rounded,
              ),
              label: Text(onGuards ? 'Add guard' : 'Add gate'),
              backgroundColor: p.primary,
              foregroundColor: p.onPrimary,
            ),
    );
  }

  Widget _guardsTab(AppPaletteData p) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
        children: [
          _note(
            p,
            'A guard signs in with the email you enter here. They see the gate — visitors, vehicles, SOS — and never residents\' numbers, dues or complaints.',
          ),
          const SizedBox(height: 12),
          if (_guards.isEmpty)
            const ModuleEmptyState(
              icon: Icons.local_police_outlined,
              title: 'No guards yet',
              message: 'Add the people who work your gate.',
            )
          else
            ..._guards.map((g) => _guardCard(p, g)),
        ],
      ),
    );
  }

  Widget _guardCard(AppPaletteData p, GuardProfile g) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(
            opacity: g.isActive ? 1 : 0.45,
            child: ResidentAvatar(initials: g.initials, size: 46),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  g.fullName,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: g.isActive ? p.textPrimary : p.textTertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    g.phone,
                    if (g.agencyName != null) g.agencyName!,
                    if (g.employeeCode != null) '#${g.employeeCode}',
                  ].join(' · '),
                  style: TextStyle(color: p.textSecondary, fontSize: 12.5),
                ),
                Text(
                  g.email,
                  style: TextStyle(color: p.textTertiary, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _chip(
                      p,
                      g.isActive ? 'Active' : 'Turned off',
                      g.isActive ? p.success : p.textTertiary,
                    ),
                    if (!g.isLinked)
                      _chip(p, 'Waiting for first sign-in', p.warning),
                    if (g.defaultGateName != null)
                      _chip(p, g.defaultGateName!, p.primary),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') _editGuard(g);
              if (v == 'toggle') _toggleGuard(g);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'toggle',
                child: Text(
                  g.isActive ? 'Turn off access' : 'Turn access back on',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gatesTab(AppPaletteData p) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
        children: [
          _note(
            p,
            'Guards pick the gate they are at. Visitor check-ins record it.',
          ),
          const SizedBox(height: 12),
          if (_gates.isEmpty)
            const ModuleEmptyState(
              icon: Icons.sensor_door_outlined,
              title: 'No gates yet',
              message: 'Add at least your main gate.',
            )
          else
            ..._gates.map(
              (g) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.hairline),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    leading: Icon(
                      Icons.sensor_door_rounded,
                      color: g.isActive ? p.primary : p.textTertiary,
                    ),
                    title: Text(
                      g.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: g.isActive ? p.textPrimary : p.textTertiary,
                      ),
                    ),
                    subtitle: Text(g.isActive ? 'In use' : 'Disabled'),
                    onTap: () => _editGate(g),
                    trailing: Switch(
                      value: g.isActive,
                      onChanged: (v) => _toggleGate(g, v),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _note(AppPaletteData p, String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: p.primary.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 18, color: p.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, color: p.textSecondary),
          ),
        ),
      ],
    ),
  );

  Widget _chip(AppPaletteData p, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

class _GuardFormSheet extends StatefulWidget {
  final GuardProfile? existing;
  final List<SocietyGate> gates;

  const _GuardFormSheet({this.existing, required this.gates});

  @override
  State<_GuardFormSheet> createState() => _GuardFormSheetState();
}

class _GuardFormSheetState extends State<_GuardFormSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.fullName);
  late final _email = TextEditingController(text: widget.existing?.email);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _agency = TextEditingController(text: widget.existing?.agencyName);
  late final _code = TextEditingController(text: widget.existing?.employeeCode);
  late String? _gateId = widget.existing?.defaultGateId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _agency, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.existing;
      if (existing == null) {
        await GuardService.instance.createGuard(
          fullName: _name.text,
          email: _email.text,
          phone: _phone.text,
          agencyName: _agency.text,
          employeeCode: _code.text,
          defaultGateId: _gateId,
        );
      } else {
        await GuardService.instance.updateGuard(
          existing.id,
          fullName: _name.text,
          email: _email.text,
          phone: _phone.text,
          agencyName: _agency.text,
          employeeCode: _code.text,
          defaultGateId: _gateId,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _SecurityStaffScreenState._errorText(e);
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final activeGates = widget.gates.where((g) => g.isActive).toList();
    final gateIds = activeGates.map((g) => g.id).toSet();

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: p.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetHeader(
                  title: widget.existing == null ? 'Add guard' : 'Edit guard',
                  subtitle: 'They sign in with this email to open the gate app',
                ),
                const SizedBox(height: 16),
                _field(
                  _name,
                  'Full name',
                  Icons.person_outline_rounded,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                _field(
                  _email,
                  'Sign-in email',
                  Icons.alternate_email_rounded,
                  keyboard: TextInputType.emailAddress,
                  capitalization: TextCapitalization.none,
                  validator: (v) {
                    final t = (v ?? '').trim();
                    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)
                        ? null
                        : 'Enter a valid email';
                  },
                ),
                _field(
                  _phone,
                  'Phone',
                  Icons.phone_outlined,
                  keyboard: TextInputType.phone,
                  validator: (v) =>
                      (v ?? '').replaceAll(RegExp(r'\D'), '').length < 8
                      ? 'Enter a phone number'
                      : null,
                ),
                _field(
                  _agency,
                  'Agency (optional)',
                  Icons.business_center_outlined,
                ),
                _field(
                  _code,
                  'Badge / employee no. (optional)',
                  Icons.badge_outlined,
                  capitalization: TextCapitalization.characters,
                ),
                DropdownButtonFormField<String?>(
                  initialValue: gateIds.contains(_gateId) ? _gateId : null,
                  decoration: _decoration(
                    p,
                    'Usual gate',
                    Icons.sensor_door_outlined,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Not set'),
                    ),
                    ...activeGates.map(
                      (g) => DropdownMenuItem<String?>(
                        value: g.id,
                        child: Text(g.name),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _gateId = v),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  FormError(_error!),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.existing == null ? 'Add guard' : 'Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(AppPaletteData p, String label, IconData icon) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: p.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.hairline),
        ),
      );

  Widget _field(
    TextEditingController c,
    String label,
    IconData icon, {
    TextInputType? keyboard,
    TextCapitalization capitalization = TextCapitalization.words,
    String? Function(String?)? validator,
  }) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: keyboard,
        textCapitalization: capitalization,
        validator: validator,
        decoration: _decoration(p, label, icon),
      ),
    );
  }
}
