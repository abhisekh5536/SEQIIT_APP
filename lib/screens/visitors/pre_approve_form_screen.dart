import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/visitor_models.dart';
import '../../services/app_session.dart';
import '../../services/visitors_service.dart';
import '../../theme/app_theme.dart';

class PreApproveFormScreen extends StatefulWidget {
  final VisitorCategory category;
  final VoidCallback? onCreated;

  const PreApproveFormScreen({
    super.key,
    required this.category,
    this.onCreated,
  });

  @override
  State<PreApproveFormScreen> createState() => _PreApproveFormScreenState();
}

class _PreApproveFormScreenState extends State<PreApproveFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _vehicleCtrl = TextEditingController();

  VisitorDurationType _durationType = VisitorDurationType.oneDay;
  DateTime _validFrom = DateTime.now();
  DateTime? _validUntil;
  bool _isPrivate = false;
  bool _submitting = false;

  // Group invite members
  final List<Map<String, TextEditingController>> _groupMembers = [];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _companyCtrl.dispose();
    _vehicleCtrl.dispose();
    for (final m in _groupMembers) {
      m['name']?.dispose();
      m['phone']?.dispose();
    }
    super.dispose();
  }

  bool get _showVehicle =>
      widget.category == VisitorCategory.cab ||
      widget.category == VisitorCategory.delivery;

  bool get _showGroupMembers =>
      widget.category == VisitorCategory.groupInvite;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pre-Approve ${widget.category.label}',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          widget.category.hint,
                          style: textTheme.bodySmall?.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: widget.category.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      widget.category.icon,
                      color: widget.category.color,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Form
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Duration toggle
                      _buildDurationToggle(p, textTheme),
                      const SizedBox(height: 20),

                      // Visitor name
                      _buildField(
                        label: 'Visitor Name',
                        controller: _nameCtrl,
                        icon: Icons.person_outline_rounded,
                        hint: 'Enter visitor\'s full name',
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Name is required'
                            : null,
                      ),
                      const SizedBox(height: 14),

                      // Phone
                      _buildField(
                        label: 'Phone (Optional)',
                        controller: _phoneCtrl,
                        icon: Icons.phone_outlined,
                        hint: 'Mobile number',
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 14),

                      // Company / Context
                      _buildField(
                        label: widget.category == VisitorCategory.cab
                            ? 'Service (e.g. Uber, Ola)'
                            : widget.category == VisitorCategory.delivery
                                ? 'Company (e.g. Zomato, Blinkit)'
                                : 'Purpose / Context (Optional)',
                        controller: _companyCtrl,
                        icon: Icons.business_outlined,
                        hint: widget.category == VisitorCategory.cab
                            ? 'Cab service name'
                            : widget.category == VisitorCategory.delivery
                                ? 'Delivery company'
                                : 'Any additional context',
                      ),
                      const SizedBox(height: 14),

                      // Vehicle number
                      if (_showVehicle) ...[
                        _buildField(
                          label: 'Vehicle Number (Optional)',
                          controller: _vehicleCtrl,
                          icon: Icons.directions_car_outlined,
                          hint: 'e.g. MH 04 AB 1234',
                          textCapitalization: TextCapitalization.characters,
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Date picker
                      _buildDatePicker(p, textTheme),
                      const SizedBox(height: 14),

                      // Valid until (for long duration)
                      if (_durationType == VisitorDurationType.longDuration) ...[
                        _buildValidUntilPicker(p, textTheme),
                        const SizedBox(height: 14),
                      ],

                      // Group members
                      if (_showGroupMembers) ...[
                        _buildGroupMembersSection(p, textTheme),
                        const SizedBox(height: 14),
                      ],

                      // Make it private
                      _buildPrivateToggle(p, textTheme),

                      const SizedBox(height: 24),

                      // Submit button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _submitting ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: p.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _submitting
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: p.onPrimary,
                                  ),
                                )
                              : Text(
                                  'Create Invite',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: p.onPrimary,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationToggle(AppPaletteData p, TextTheme textTheme) {
    return Container(
      decoration: BoxDecoration(
        color: p.cardMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: VisitorDurationType.values.map((dt) {
          final selected = _durationType == dt;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _durationType = dt);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? p.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: p.shadow.withValues(alpha: 0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  dt.label,
                  textAlign: TextAlign.center,
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? p.primary : p.textTertiary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.words,
  }) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: p.textSecondary,
              ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          decoration: InputDecoration(
            hintText: hint,
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
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: p.primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker(AppPaletteData p, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Date',
          style: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: p.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _validFrom,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked != null) {
              setState(() => _validFrom = picked);
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded,
                    size: 20, color: p.primary),
                const SizedBox(width: 12),
                Text(
                  DateFormat('EEE, dd MMM yyyy').format(_validFrom),
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: p.textTertiary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildValidUntilPicker(AppPaletteData p, TextTheme textTheme) {
    final displayDate = _validUntil ?? _validFrom.add(const Duration(days: 30));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Valid Until',
          style: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: p.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: displayDate,
              firstDate: _validFrom.add(const Duration(days: 1)),
              lastDate: _validFrom.add(const Duration(days: 365)),
            );
            if (picked != null) {
              setState(() => _validUntil = picked);
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                Icon(Icons.event_rounded, size: 20, color: p.secondary),
                const SizedBox(width: 12),
                Text(
                  DateFormat('EEE, dd MMM yyyy').format(displayDate),
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: p.textTertiary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupMembersSection(AppPaletteData p, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Guest List',
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: p.textSecondary,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _addGroupMember,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Guest'),
              style: TextButton.styleFrom(
                foregroundColor: p.primary,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (_groupMembers.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                Icon(Icons.group_add_rounded,
                    size: 24, color: p.textTertiary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tap "Add Guest" to add members to this group invite',
                    style: textTheme.bodySmall?.copyWith(
                      color: p.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ...List.generate(_groupMembers.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.hairline),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: p.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: p.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        children: [
                          SizedBox(
                            height: 36,
                            child: TextFormField(
                              controller: _groupMembers[i]['name'],
                              decoration: InputDecoration(
                                hintText: 'Guest name',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: p.hairline),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: p.hairline),
                                ),
                              ),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 36,
                            child: TextFormField(
                              controller: _groupMembers[i]['phone'],
                              decoration: InputDecoration(
                                hintText: 'Phone (optional)',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: p.hairline),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: p.hairline),
                                ),
                              ),
                              keyboardType: TextInputType.phone,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _removeGroupMember(i),
                      icon: Icon(Icons.close_rounded,
                          size: 18, color: p.danger),
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildPrivateToggle(AppPaletteData p, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 22, color: p.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Make It Private',
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Only you will be notified, not other flat members',
                  style: textTheme.bodySmall?.copyWith(
                    color: p.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _isPrivate,
            onChanged: (v) => setState(() => _isPrivate = v),
            activeColor: p.primary,
          ),
        ],
      ),
    );
  }

  void _addGroupMember() {
    setState(() {
      _groupMembers.add({
        'name': TextEditingController(),
        'phone': TextEditingController(),
      });
    });
  }

  void _removeGroupMember(int index) {
    _groupMembers[index]['name']?.dispose();
    _groupMembers[index]['phone']?.dispose();
    setState(() => _groupMembers.removeAt(index));
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final session = AppSession.instance;
    final primary = session.primaryResidence;
    if (primary == null) {
      _showError('No residence found. Please link your flat first.');
      return;
    }

    setState(() => _submitting = true);

    try {
      final members = _groupMembers
          .where((m) =>
              m['name']?.text.trim().isNotEmpty == true)
          .map((m) => {
                'name': m['name']!.text.trim(),
                'phone': m['phone']?.text.trim() ?? '',
              })
          .toList();

      final result = await VisitorsService.instance.createPreApproval(
        societyId: primary.societyId,
        flatId: primary.flatId,
        blockId: session.flatOf(primary)?.blockId,
        visitorName: _nameCtrl.text.trim(),
        visitorPhone: _phoneCtrl.text.trim().isNotEmpty
            ? _phoneCtrl.text.trim()
            : null,
        vehicleNumber: _vehicleCtrl.text.trim().isNotEmpty
            ? _vehicleCtrl.text.trim()
            : null,
        category: widget.category,
        companyOrContext: _companyCtrl.text.trim().isNotEmpty
            ? _companyCtrl.text.trim()
            : null,
        durationType: _durationType,
        validFrom: _validFrom,
        validUntil: _validUntil,
        isPrivate: _isPrivate,
        groupMembers: members,
      );

      if (mounted) {
        widget.onCreated?.call();
        Navigator.pop(context);
        _showSuccess(result['approval_code'] ?? '');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  void _showSuccess(String code) {
    if (!mounted) return;
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pre-approval created! Code: $code',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: p.success,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
