import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/visitor_models.dart';
import '../../services/app_session.dart';
import '../../services/visitors_service.dart';
import '../../theme/app_theme.dart';

/// Admin gate stand-in: log a walk-in visitor (Flow A).
class AdminLogVisitorScreen extends StatefulWidget {
  const AdminLogVisitorScreen({super.key});

  @override
  State<AdminLogVisitorScreen> createState() => _AdminLogVisitorScreenState();
}

class _AdminLogVisitorScreenState extends State<AdminLogVisitorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _vehicleCtrl = TextEditingController();

  VisitorCategory _category = VisitorCategory.guest;
  bool _submitting = false;
  Uint8List? _photoBytes;

  // Flat selection
  List<Map<String, dynamic>> _flats = [];
  String? _selectedFlatId;
  Map<String, dynamic>? _selectedFlat;
  bool _loadingFlats = true;

  @override
  void initState() {
    super.initState();
    _loadFlats();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _companyCtrl.dispose();
    _vehicleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFlats() async {
    try {
      final session = AppSession.instance;
      if (!session.isLoaded && !session.isLoading) {
        await session.load();
      }
      final societyId = session.societyId;
      if (societyId == null || societyId.isEmpty) {
        if (mounted) setState(() => _loadingFlats = false);
        return;
      }

      final client = Supabase.instance.client;

      // 1) Fetch all blocks for this society
      final blocksRaw = await client
          .from('blocks')
          .select('id, name')
          .eq('society_id', societyId);
      final blocksList = (blocksRaw as List).cast<Map<String, dynamic>>();
      final blockMap = {
        for (final b in blocksList)
          b['id'].toString(): b['name']?.toString() ?? ''
      };
      final blockIds = blockMap.keys.toList();

      if (blockIds.isEmpty) {
        if (mounted) {
          setState(() {
            _flats = [];
            _loadingFlats = false;
          });
        }
        return;
      }

      // 2) Find active residents to cross-reference occupied flats
      Set<String> residentOccupiedFlatIds = {};
      try {
        final residentsRaw = await client
            .from('residents')
            .select('flat_id')
            .eq('society_id', societyId)
            .eq('status', 'active');
        residentOccupiedFlatIds = (residentsRaw as List)
            .map((r) => r['flat_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
      } catch (err) {
        debugPrint('Residents query note: $err');
      }

      // 3) Query flats belonging to this society's blocks
      final flatsRaw = await client
          .from('flats')
          .select('id, flat_number, block_id, status')
          .inFilter('block_id', blockIds);

      final List<Map<String, dynamic>> occupiedFlats = [];
      for (final f in (flatsRaw as List).cast<Map<String, dynamic>>()) {
        final fid = f['id']?.toString() ?? '';
        final status = f['status']?.toString().toLowerCase().trim() ?? '';
        final isOccupied =
            status == 'occupied' || residentOccupiedFlatIds.contains(fid);

        // FILTER: Only show occupied flats, do not show vacant flats
        if (isOccupied) {
          final bid = f['block_id']?.toString() ?? '';
          occupiedFlats.add({
            'id': fid,
            'flat_number': f['flat_number']?.toString() ?? '',
            'block_id': bid,
            'block_name': blockMap[bid] ?? '',
          });
        }
      }

      // Sort by block name then flat number
      occupiedFlats.sort((a, b) {
        final bA = a['block_name']?.toString() ?? '';
        final bB = b['block_name']?.toString() ?? '';
        if (bA != bB) return bA.compareTo(bB);
        final numA = int.tryParse(a['flat_number']?.toString() ?? '');
        final numB = int.tryParse(b['flat_number']?.toString() ?? '');
        if (numA != null && numB != null) return numA.compareTo(numB);
        return (a['flat_number']?.toString() ?? '')
            .compareTo(b['flat_number']?.toString() ?? '');
      });

      if (mounted) {
        setState(() {
          _flats = occupiedFlats;
          _loadingFlats = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading occupied flats: $e');
      if (mounted) setState(() => _loadingFlats = false);
    }
  }

  String _flatLabel(Map<String, dynamic> flat) {
    final blockName = flat['block_name']?.toString();
    final flatNum = flat['flat_number']?.toString() ?? '';
    return blockName != null && blockName.isNotEmpty
        ? '$blockName · Flat $flatNum'
        : 'Flat $flatNum';
  }

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
                          'Log Visitor Entry',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Gate stand-in · Flow A',
                          style: textTheme.bodySmall?.copyWith(
                            color: p.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Flat selector
                      _buildFlatSelector(p, textTheme),
                      const SizedBox(height: 16),

                      // Photo capture
                      _buildPhotoCapture(p, textTheme),
                      const SizedBox(height: 16),

                      // Category selector
                      Text(
                        'Category',
                        style: textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: p.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: VisitorCategory.values.map((cat) {
                          final isSelected = _category == cat;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _category = cat);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? cat.color.withValues(alpha: 0.15)
                                    : p.card,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? cat.color
                                      : p.hairline,
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(cat.icon,
                                      size: 16, color: cat.color),
                                  const SizedBox(width: 6),
                                  Text(
                                    cat.label,
                                    style: TextStyle(
                                      color: isSelected
                                          ? cat.color
                                          : p.textSecondary,
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // Name
                      _buildField(
                        'Visitor Name',
                        _nameCtrl,
                        Icons.person_outline_rounded,
                        'Full name',
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 14),

                      // Phone
                      _buildField(
                        'Phone (Optional)',
                        _phoneCtrl,
                        Icons.phone_outlined,
                        'Mobile number',
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 14),

                      // Company
                      _buildField(
                        'Company / Context (Optional)',
                        _companyCtrl,
                        Icons.business_outlined,
                        'e.g. Blinkit, friend of...',
                      ),
                      const SizedBox(height: 14),

                      // Vehicle
                      if (_category == VisitorCategory.cab ||
                          _category == VisitorCategory.delivery) ...[
                        _buildField(
                          'Vehicle Number (Optional)',
                          _vehicleCtrl,
                          Icons.directions_car_outlined,
                          'e.g. MH 04 AB 1234',
                          textCapitalization: TextCapitalization.characters,
                        ),
                        const SizedBox(height: 14),
                      ],

                      const SizedBox(height: 10),

                      // Submit
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: p.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 20),
                          label: const Text(
                            'Send Approval Request',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: p.primary,
                            foregroundColor: p.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
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

  Widget _buildFlatSelector(AppPaletteData p, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Select Flat',
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: p.textSecondary,
              ),
            ),
            if (!_loadingFlats && _flats.isNotEmpty)
              Text(
                '${_flats.length} occupied',
                style: TextStyle(
                  color: p.success,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (_loadingFlats)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.hairline),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: p.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text('Loading occupied flats...', style: textTheme.bodyMedium),
              ],
            ),
          )
        else if (_flats.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 20, color: p.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No occupied flats found in this society.',
                    style: TextStyle(
                      color: p.warning,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          DropdownButtonFormField<String>(
            value: _selectedFlatId,
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Select a flat' : null,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.apartment_rounded, size: 20),
              suffixIcon: _flats.length > 3
                  ? IconButton(
                      icon: const Icon(Icons.search_rounded, size: 20),
                      tooltip: 'Search occupied flats',
                      onPressed: () => _showFlatSearchModal(context),
                    )
                  : null,
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
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            hint: const Text('Choose flat'),
            isExpanded: true,
            items: _flats
                .map((f) => DropdownMenuItem<String>(
                      value: f['id'].toString(),
                      child: Text(
                        _flatLabel(f),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ))
                .toList(),
            onChanged: (v) {
              setState(() {
                _selectedFlatId = v;
                _selectedFlat =
                    _flats.where((f) => f['id'].toString() == v).firstOrNull;
              });
            },
          ),
      ],
    );
  }

  void _showFlatSearchModal(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String filter = '';
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filtered = _flats.where((f) {
              final label = _flatLabel(f).toLowerCase();
              return label.contains(filter.toLowerCase().trim());
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: BoxDecoration(
                color: p.canvas,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                      color: p.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                    child: Row(
                      children: [
                        Icon(Icons.apartment_rounded,
                            size: 22, color: p.primary),
                        const SizedBox(width: 10),
                        Text(
                          'Select Occupied Flat',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search flat number or tower...',
                        prefixIcon:
                            const Icon(Icons.search_rounded, size: 20),
                        filled: true,
                        fillColor: p.card,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: p.hairline),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: p.hairline),
                        ),
                      ),
                      onChanged: (q) => setModalState(() => filter = q),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No matching occupied flats',
                              style: TextStyle(color: p.textTertiary),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                Divider(color: p.hairline, height: 1),
                            itemBuilder: (ctx, i) {
                              final f = filtered[i];
                              final isSelected =
                                  f['id'].toString() == _selectedFlatId;
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  Icons.meeting_room_rounded,
                                  color: isSelected
                                      ? p.primary
                                      : p.textTertiary,
                                ),
                                title: Text(
                                  _flatLabel(f),
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? p.primary
                                        : p.textPrimary,
                                  ),
                                ),
                                trailing: isSelected
                                    ? Icon(Icons.check_circle_rounded,
                                        color: p.primary, size: 20)
                                    : null,
                                onTap: () {
                                  setState(() {
                                    _selectedFlatId = f['id'].toString();
                                    _selectedFlat = f;
                                  });
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPhotoCapture(AppPaletteData p, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Visitor Photo',
          style: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: p.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _pickPhoto,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            height: _photoBytes != null ? 180 : 100,
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _photoBytes != null
                    ? p.success.withValues(alpha: 0.5)
                    : p.hairline,
                width: _photoBytes != null ? 2 : 1,
              ),
            ),
            child: _photoBytes != null
                ? Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(
                          _photoBytes!,
                          width: double.infinity,
                          height: 180,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _photoBytes = null;
                          }),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt_rounded,
                          size: 28, color: p.textTertiary),
                      const SizedBox(height: 6),
                      Text(
                        'Tap to capture or select photo',
                        style: TextStyle(
                          color: p.textTertiary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    IconData icon,
    String hint, {
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
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) {
        final p = AppTheme.paletteFor(Theme.of(ctx).brightness);
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt_rounded, color: p.primary),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library_rounded, color: p.primary),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    try {
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() => _photoBytes = bytes);
      }
    } catch (e) {
      debugPrint('Photo pick error: $e');
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);

    try {
      // Upload photo if captured
      String? photoUrl;
      if (_photoBytes != null) {
        photoUrl = await VisitorsService.instance.uploadVisitorPhoto(
          bytes: _photoBytes!,
          fileExtension: 'jpg',
        );
      }

      final selectedFlat = _selectedFlat ??
          _flats.where((f) => f['id'].toString() == _selectedFlatId).firstOrNull;
      if (selectedFlat == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select an occupied flat'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final flatId = selectedFlat['id']?.toString() ?? '';
      final blockId = selectedFlat['block_id']?.toString();
      final societyId = AppSession.instance.societyId!;

      await VisitorsService.instance.createVisitorEntry(
        societyId: societyId,
        flatId: flatId,
        blockId: blockId,
        visitorName: _nameCtrl.text.trim(),
        visitorPhone: _phoneCtrl.text.trim().isNotEmpty
            ? _phoneCtrl.text.trim()
            : null,
        visitorPhotoUrl: photoUrl,
        vehicleNumber: _vehicleCtrl.text.trim().isNotEmpty
            ? _vehicleCtrl.text.trim()
            : null,
        category: _category,
        companyOrContext: _companyCtrl.text.trim().isNotEmpty
            ? _companyCtrl.text.trim()
            : null,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Visitor logged! Waiting for resident approval.'),
            backgroundColor:
                AppTheme.paletteFor(Theme.of(context).brightness).success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

