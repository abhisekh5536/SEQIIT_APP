import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/db_models.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';

class JoinSocietyScreen extends StatefulWidget {
  const JoinSocietyScreen({super.key});

  @override
  State<JoinSocietyScreen> createState() => _JoinSocietyScreenState();
}

class _JoinSocietyScreenState extends State<JoinSocietyScreen> {
  final _formKey = GlobalKey<FormState>();

  // Data state
  bool _loadingSocieties = true;
  bool _loadingFlats = false;
  bool _submitting = false;
  String? _errorMessage;

  List<SocietyInfo> _societies = [];
  SocietyInfo? _selectedSociety;

  List<VacantFlatOption> _vacantFlats = [];
  VacantFlatOption? _selectedFlat;

  // Form controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _aadharController = TextEditingController();
  final _holderNameController = TextEditingController();
  String _residentType = 'owner';
  DateTime? _agreementDate;

  @override
  void initState() {
    super.initState();
    _initDefaults();
    _loadSocieties();
  }

  void _initDefaults() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final meta = user.userMetadata;
      if (meta != null) {
        final metaName = (meta['full_name'] ?? meta['name'] ?? meta['display_name']) as String?;
        if (metaName != null && metaName.trim().isNotEmpty) {
          _nameController.text = metaName.trim();
        }
      }
      if (_nameController.text.isEmpty && user.email != null) {
        final local = user.email!.split('@').first;
        if (local.isNotEmpty) {
          _nameController.text = local[0].toUpperCase() + local.substring(1);
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _aadharController.dispose();
    _holderNameController.dispose();
    super.dispose();
  }

  Future<void> _loadSocieties() async {
    setState(() {
      _loadingSocieties = true;
      _errorMessage = null;
    });

    try {
      final res = await Supabase.instance.client
          .from('societies')
          .select('id, name, address, city, state, registration_number')
          .eq('status', 'active')
          .order('name');

      final list = (res as List).cast<Map<String, dynamic>>().map(SocietyInfo.fromMap).toList();
      setState(() {
        _societies = list;
        _loadingSocieties = false;
      });
    } catch (e) {
      setState(() {
        _loadingSocieties = false;
        _errorMessage = 'Could not load societies: $e';
      });
    }
  }

  Future<void> _loadFlatsForSociety(String societyId) async {
    setState(() {
      _loadingFlats = true;
      _selectedFlat = null;
      _vacantFlats = [];
    });

    try {
      final client = Supabase.instance.client;
      // 1. Get all blocks for this society
      final blockRes = await client.from('blocks').select('id, name').eq('society_id', societyId);
      final blocks = (blockRes as List).cast<Map<String, dynamic>>();
      final blockMap = {for (var b in blocks) b['id'].toString(): b['name'].toString()};

      if (blockMap.isEmpty) {
        setState(() {
          _loadingFlats = false;
          _vacantFlats = [];
        });
        return;
      }

      // 2. Get vacant flats in these blocks
      final flatRes = await client
          .from('flats')
          .select('id, block_id, floor_number, flat_number, type, status')
          .inFilter('block_id', blockMap.keys.toList())
          .eq('status', 'vacant')
          .order('flat_number');

      final flatsList = (flatRes as List).cast<Map<String, dynamic>>();
      final parsedFlats = flatsList.map((f) {
        final bName = blockMap[f['block_id']?.toString()] ?? 'Block';
        return VacantFlatOption.fromFlatAndBlock(f, bName);
      }).toList();

      setState(() {
        _vacantFlats = parsedFlats;
        _loadingFlats = false;
      });
    } catch (e) {
      setState(() {
        _loadingFlats = false;
        _errorMessage = 'Could not load flats for society: $e';
      });
    }
  }

  Future<void> _pickAgreementDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _agreementDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2040),
    );
    if (picked != null) {
      setState(() => _agreementDate = picked);
    }
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSociety == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your society')),
      );
      return;
    }
    if (_selectedFlat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your vacant flat')),
      );
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || user.email == null) return;

    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final reqMap = {
        'society_id': _selectedSociety!.id,
        'flat_id': _selectedFlat!.flatId,
        'user_id': user.id,
        'full_name': _nameController.text.trim(),
        'email': user.email!.trim(),
        'phone': _phoneController.text.trim(),
        'resident_type': _residentType,
        'is_primary': true,
        'agreement_holder_name': _holderNameController.text.trim().isNotEmpty
            ? _holderNameController.text.trim()
            : _nameController.text.trim(),
        'agreement_date': _agreementDate?.toIso8601String().split('T').first ??
            DateTime.now().toIso8601String().split('T').first,
        'aadhar_last4': _aadharController.text.trim(),
        'status': 'pending',
      };

      await Supabase.instance.client.from('resident_join_requests').insert(reqMap);

      await AppSession.instance.refreshJoinRequest();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Join request submitted! Awaiting admin approval.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to submit request: $e';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign Out')),
        ],
      ),
    );
    if (confirmed == true) {
      await Supabase.instance.client.auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        title: const Text(
          'Join Society',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
        centerTitle: false,
        backgroundColor: p.canvas,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out',
            onPressed: _signOut,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Welcome Banner
                  _buildWelcomeCard(p, userEmail),
                  const SizedBox(height: 24),

                  if (_errorMessage != null) ...[
                    _buildErrorBox(p, _errorMessage!),
                    const SizedBox(height: 16),
                  ],

                  // 1. Select Society Section
                  _buildSectionTitle(p, '1. Select Your Society', Icons.domain_rounded),
                  const SizedBox(height: 12),
                  _buildSocietySelector(p),
                  const SizedBox(height: 24),

                  // 2. Select Flat Section
                  _buildSectionTitle(p, '2. Choose Vacant Flat', Icons.meeting_room_rounded),
                  const SizedBox(height: 12),
                  _buildFlatSelector(p),
                  const SizedBox(height: 24),

                  // 3. Resident Details Section
                  _buildSectionTitle(p, '3. Resident Information', Icons.badge_outlined),
                  const SizedBox(height: 12),
                  _buildResidentDetails(p),
                  const SizedBox(height: 36),

                  // Submit Button
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submitRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: p.primary,
                        foregroundColor: p.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Submit for Admin Approval',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(AppPaletteData p, String userEmail) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
        boxShadow: [
          BoxShadow(
            color: p.shadow.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.apartment_rounded, color: p.primary, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome to SAQIIT!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Signed in as $userEmail.\nTo access your society dashboard, choose your society and select your vacant flat below.',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: p.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(AppPaletteData p, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: p.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: p.textPrimary,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildSocietySelector(AppPaletteData p) {
    if (_loadingSocieties) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.hairline),
        ),
        child: const Center(
          child: SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_societies.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.hairline),
        ),
        child: Text(
          'No active societies found. Please contact support.',
          style: TextStyle(color: p.textSecondary, fontSize: 14),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.hairline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SocietyInfo>(
          isExpanded: true,
          value: _selectedSociety,
          hint: Text(
            'Select your society...',
            style: TextStyle(color: p.textTertiary, fontSize: 15),
          ),
          dropdownColor: p.card,
          items: _societies.map((s) {
            return DropdownMenuItem<SocietyInfo>(
              value: s,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    s.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                  if (s.locationSubtitle.isNotEmpty)
                    Text(
                      s.locationSubtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: p.textTertiary,
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
          onChanged: (SocietyInfo? val) {
            if (val != null && val.id != _selectedSociety?.id) {
              setState(() => _selectedSociety = val);
              _loadFlatsForSociety(val.id);
            }
          },
        ),
      ),
    );
  }

  Widget _buildFlatSelector(AppPaletteData p) {
    if (_selectedSociety == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.cardMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: p.textTertiary),
            const SizedBox(width: 8),
            Text(
              'Select a society first to view vacant flats.',
              style: TextStyle(color: p.textTertiary, fontSize: 13.5),
            ),
          ],
        ),
      );
    }

    if (_loadingFlats) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.hairline),
        ),
        child: const Center(
          child: SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_vacantFlats.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.hairline),
        ),
        child: Text(
          'No vacant flats currently available in ${_selectedSociety!.name}.',
          style: TextStyle(color: p.textSecondary, fontSize: 14),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.hairline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<VacantFlatOption>(
          isExpanded: true,
          value: _selectedFlat,
          hint: Text(
            'Select your vacant flat / unit...',
            style: TextStyle(color: p.textTertiary, fontSize: 15),
          ),
          dropdownColor: p.card,
          items: _vacantFlats.map((flat) {
            return DropdownMenuItem<VacantFlatOption>(
              value: flat,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    flat.displayTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    flat.displaySubtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: p.textTertiary,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (VacantFlatOption? val) {
            setState(() => _selectedFlat = val);
          },
        ),
      ),
    );
  }

  Widget _buildResidentDetails(AppPaletteData p) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Full Name
          TextFormField(
            controller: _nameController,
            style: TextStyle(color: p.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              labelText: 'Full Name *',
              labelStyle: TextStyle(color: p.textTertiary),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.hairline)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.primary, width: 1.5)),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your full name' : null,
          ),
          const SizedBox(height: 16),

          // Phone Number
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            style: TextStyle(color: p.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              labelText: 'Phone Number *',
              hintText: '+919876543210',
              labelStyle: TextStyle(color: p.textTertiary),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.hairline)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.primary, width: 1.5)),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your phone number' : null,
          ),
          const SizedBox(height: 20),

          // Resident Type Segmented Bar
          Text(
            'Resident Type *',
            style: TextStyle(fontSize: 13, color: p.textTertiary, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'owner', label: Text('Owner')),
              ButtonSegment(value: 'tenant', label: Text('Tenant')),
              ButtonSegment(value: 'family', label: Text('Family')),
            ],
            selected: {_residentType},
            onSelectionChanged: (set) {
              setState(() => _residentType = set.first);
            },
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: p.primary.withValues(alpha: 0.15),
              selectedForegroundColor: p.primary,
              foregroundColor: p.textSecondary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 20),

          // Aadhar Last 4 Digits
          TextFormField(
            controller: _aadharController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            style: TextStyle(color: p.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              labelText: 'Aadhar Last 4 Digits *',
              hintText: 'e.g. 1234',
              counterText: '',
              labelStyle: TextStyle(color: p.textTertiary),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.hairline)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.primary, width: 1.5)),
            ),
            validator: (v) {
              if (v == null || v.trim().length != 4 || int.tryParse(v.trim()) == null) {
                return 'Enter exactly 4 digits';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Move-in / Agreement Date Picker
          InkWell(
            onTap: _pickAgreementDate,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _residentType == 'tenant' ? 'Agreement Date' : 'Possession / Move-in Date',
                        style: TextStyle(fontSize: 13, color: p.textTertiary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _agreementDate == null
                            ? 'Today (${DateTime.now().toIso8601String().split('T').first})'
                            : _agreementDate!.toIso8601String().split('T').first,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.textPrimary),
                      ),
                    ],
                  ),
                  Icon(Icons.calendar_today_rounded, size: 20, color: p.primary),
                ],
              ),
            ),
          ),

          if (_residentType != 'owner') ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _holderNameController,
              style: TextStyle(color: p.textPrimary, fontSize: 15),
              decoration: InputDecoration(
                labelText: _residentType == 'tenant' ? 'Agreement Holder / Owner Name' : 'Primary Resident / Head of Family',
                labelStyle: TextStyle(color: p.textTertiary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.hairline)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: p.primary, width: 1.5)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorBox(AppPaletteData p, String error) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: p.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: TextStyle(color: p.danger, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
