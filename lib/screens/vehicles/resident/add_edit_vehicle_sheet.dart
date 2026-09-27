import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/vehicle_parking_models.dart';
import '../../../services/vehicles_parking_service.dart';
import '../../../theme/app_theme.dart';
import '../widgets/vehicle_parking_widgets.dart';

class AddEditVehicleSheet extends StatefulWidget {
  final String societyId;
  final String flatId;
  final String? residentId;
  final VehicleItem? existingVehicle;
  final VoidCallback onSaved;

  const AddEditVehicleSheet({
    super.key,
    required this.societyId,
    required this.flatId,
    this.residentId,
    this.existingVehicle,
    required this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    required String societyId,
    required String flatId,
    String? residentId,
    VehicleItem? existingVehicle,
    required VoidCallback onSaved,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddEditVehicleSheet(
        societyId: societyId,
        flatId: flatId,
        residentId: residentId,
        existingVehicle: existingVehicle,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<AddEditVehicleSheet> createState() => _AddEditVehicleSheetState();
}

class _AddEditVehicleSheetState extends State<AddEditVehicleSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _plateController;
  late final TextEditingController _makeController;
  late final TextEditingController _colorController;

  late VehicleType _type;
  bool _submitting = false;
  String? _error;

  Uint8List? _rcBytes;
  String? _rcExtension;
  String? _rcFileName;
  String? _existingRcUrl;

  bool get _isEdit => widget.existingVehicle != null;

  @override
  void initState() {
    super.initState();
    _plateController =
        TextEditingController(text: widget.existingVehicle?.vehicleNumber ?? '');
    _makeController =
        TextEditingController(text: widget.existingVehicle?.makeModel ?? '');
    _colorController =
        TextEditingController(text: widget.existingVehicle?.color ?? '');
    _type = widget.existingVehicle?.type ?? VehicleType.fourWheeler;
    _existingRcUrl = widget.existingVehicle?.rcPhotoUrl;
  }

  @override
  void dispose() {
    _plateController.dispose();
    _makeController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  Future<void> _pickRcImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );

      if (picked != null) {
        final bytes = await picked.readAsBytes();
        final ext = picked.name.contains('.')
            ? picked.name.split('.').last.toLowerCase()
            : 'jpg';
        setState(() {
          _rcBytes = bytes;
          _rcExtension = ext;
          _rcFileName = picked.name;
        });
      }
    } catch (e) {
      debugPrint('Error picking RC image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not attach RC photo: $e')),
        );
      }
    }
  }

  void _showRcSourceDialog() {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    showModalBottomSheet(
      context: context,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Attach Registration Certificate (RC)',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: p.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.camera_alt_rounded, color: p.primary),
                ),
                title: const Text('Take photo of RC'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickRcImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_rounded,
                      color: Color(0xFF10B981)),
                ),
                title: const Text('Choose from Gallery / Files'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickRcImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      String? photoUrl = _existingRcUrl;
      if (_rcBytes != null && _rcExtension != null) {
        photoUrl = await VehiclesParkingService.instance.uploadRcPhoto(
          bytes: _rcBytes!,
          fileExtension: _rcExtension!,
        );
      }

      if (_isEdit) {
        await VehiclesParkingService.instance.updateVehicle(
          vehicleId: widget.existingVehicle!.id,
          societyId: widget.societyId,
          makeModel: _makeController.text.trim(),
          color: _colorController.text.trim(),
          type: _type,
          rcPhotoUrl: photoUrl,
        );
      } else {
        await VehiclesParkingService.instance.registerVehicle(
          societyId: widget.societyId,
          flatId: widget.flatId,
          residentId: widget.residentId,
          vehicleNumber: _plateController.text.trim(),
          makeModel: _makeController.text.trim(),
          type: _type,
          color: _colorController.text.trim().isNotEmpty
              ? _colorController.text.trim()
              : null,
          rcPhotoUrl: photoUrl,
        );
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(left: 20, right: 20, top: 12, bottom: bottomInset + 20),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 14),
              SheetHeader(
                title: _isEdit ? 'Edit vehicle' : 'Add a vehicle',
                subtitle: _isEdit
                    ? 'Number stays as registered; update the rest.'
                    : 'Registered once — used for gate clearance and bay requests.',
              ),
              const SizedBox(height: 16),
              if (_error != null) FormError(_error!),

              const FieldLabel('Type', required: true),
              Container(
                decoration: BoxDecoration(
                  color: p.cardMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    for (final t in VehicleType.values)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _type = t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: _type == t ? p.card : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                              boxShadow: _type == t
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
                              t == VehicleType.twoWheeler
                                  ? '2-wheeler'
                                  : t == VehicleType.fourWheeler
                                      ? '4-wheeler'
                                      : 'Other',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: _type == t
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: _type == t
                                    ? p.textPrimary
                                    : p.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              const FieldLabel('Registration number', required: true),
              TextFormField(
                controller: _plateController,
                enabled: !_isEdit,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  letterSpacing: 1.2,
                ),
                decoration: const InputDecoration(
                  hintText: 'MH 12 AB 1234',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Enter the number as on the RC';
                  }
                  if (val.replaceAll(RegExp(r'\s+'), '').length < 5) {
                    return 'That number looks too short';
                  }
                  return null;
                },
              ),
              if (_plateController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                VehiclePlate(_plateController.text.trim()),
              ],
              const SizedBox(height: 16),

              const FieldLabel('Make & model', required: true),
              TextFormField(
                controller: _makeController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Hyundai Creta / Honda Activa 6G',
                ),
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'Enter make and model'
                    : null,
              ),
              const SizedBox(height: 16),

              const FieldLabel('Colour'),
              TextFormField(
                controller: _colorController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'White, grey, red…',
                ),
              ),
              const SizedBox(height: 16),

              const FieldLabel('RC Document (Optional)'),
              if (_rcBytes != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.cardMuted,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          _rcBytes!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _rcFileName ?? 'RC Photo Attached',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'Ready to upload',
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          _rcBytes = null;
                          _rcExtension = null;
                          _rcFileName = null;
                        }),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        tooltip: 'Remove',
                      ),
                    ],
                  ),
                )
              else if (_existingRcUrl != null && _existingRcUrl!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.cardMuted,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _existingRcUrl!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 50,
                            height: 50,
                            color: p.card,
                            child: const Icon(Icons.insert_drive_file_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'RC Photo On File',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _showRcSourceDialog,
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: _showRcSourceDialog,
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('Upload RC Photo'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_isEdit ? 'Save changes' : 'Add vehicle'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
