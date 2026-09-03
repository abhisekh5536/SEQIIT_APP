import 'package:flutter/material.dart';

import '../../../models/security_models.dart';
import '../../../services/app_session.dart';
import '../../../services/security_service.dart';

class ContactFormDialog extends StatefulWidget {
  final EmergencyContact? contact;
  final List<EmergencyCategory> categories;
  final VoidCallback onSaved;

  const ContactFormDialog({
    super.key,
    this.contact,
    required this.categories,
    required this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    EmergencyContact? contact,
    required List<EmergencyCategory> categories,
    required VoidCallback onSaved,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => ContactFormDialog(
        contact: contact,
        categories: categories,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<ContactFormDialog> createState() => _ContactFormDialogState();
}

class _ContactFormDialogState extends State<ContactFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _designationController;
  late final TextEditingController _phoneController;
  late final TextEditingController _altPhoneController;
  late final TextEditingController _availabilityController;
  late final TextEditingController _sortOrderController;

  String? _selectedCategoryId;
  late bool _isActive;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    _nameController = TextEditingController(text: c?.name ?? '');
    _designationController = TextEditingController(text: c?.designation ?? '');
    _phoneController = TextEditingController(text: c?.phoneNumber ?? '');
    _altPhoneController =
        TextEditingController(text: c?.alternatePhoneNumber ?? '');
    _availabilityController =
        TextEditingController(text: c?.availability ?? '24/7');
    _sortOrderController =
        TextEditingController(text: (c?.sortOrder ?? 0).toString());

    _selectedCategoryId = c?.categoryId;
    if (_selectedCategoryId == null && widget.categories.isNotEmpty) {
      // Default to first non-global or first category
      final custom = widget.categories.where((cat) => !cat.isGlobal).toList();
      _selectedCategoryId =
          custom.isNotEmpty ? custom.first.id : widget.categories.first.id;
    }

    _isActive = c?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _designationController.dispose();
    _phoneController.dispose();
    _altPhoneController.dispose();
    _availabilityController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

    final societyId = AppSession.instance.societyId;
    if (societyId == null) return;

    setState(() => _isSaving = true);
    final sortOrder = int.tryParse(_sortOrderController.text.trim()) ?? 0;

    try {
      if (widget.contact == null) {
        await SecurityService.instance.createContact(
          societyId: societyId,
          categoryId: _selectedCategoryId!,
          name: _nameController.text.trim(),
          designation: _designationController.text.trim().isNotEmpty
              ? _designationController.text.trim()
              : null,
          phoneNumber: _phoneController.text.trim(),
          alternatePhoneNumber: _altPhoneController.text.trim().isNotEmpty
              ? _altPhoneController.text.trim()
              : null,
          availability: _availabilityController.text.trim().isNotEmpty
              ? _availabilityController.text.trim()
              : '24/7',
          sortOrder: sortOrder,
        );
      } else {
        await SecurityService.instance.updateContact(
          contactId: widget.contact!.id,
          categoryId: _selectedCategoryId!,
          name: _nameController.text.trim(),
          designation: _designationController.text.trim().isNotEmpty
              ? _designationController.text.trim()
              : null,
          phoneNumber: _phoneController.text.trim(),
          alternatePhoneNumber: _altPhoneController.text.trim().isNotEmpty
              ? _altPhoneController.text.trim()
              : null,
          availability: _availabilityController.text.trim().isNotEmpty
              ? _availabilityController.text.trim()
              : '24/7',
          sortOrder: sortOrder,
          isActive: _isActive,
        );
      }

      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving contact: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.contact != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Contact' : 'New Emergency Contact'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Category *',
                  ),
                  items: widget.categories.map((cat) {
                    return DropdownMenuItem(
                      value: cat.id,
                      child: Row(
                        children: [
                          Icon(cat.icon, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              cat.name + (cat.isGlobal ? ' (Global)' : ''),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCategoryId = val);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Contact Name / Provider *',
                    hintText: 'e.g. Ramesh Kumar, Gate 1 Security',
                  ),
                  validator: (val) => (val == null || val.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _designationController,
                  decoration: const InputDecoration(
                    labelText: 'Designation / Role',
                    hintText: 'e.g. Senior Electrician, Gate Supervisor',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Primary Phone Number *',
                    hintText: 'e.g. +91 9876543210 or 100',
                  ),
                  validator: (val) => (val == null || val.trim().isEmpty)
                      ? 'Phone number is required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _altPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Alternate Phone Number (Optional)',
                    hintText: 'e.g. Landline or backup mobile',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _availabilityController,
                  decoration: const InputDecoration(
                    labelText: 'Availability',
                    hintText: 'e.g. 24/7, Mon–Sat 9 AM – 6 PM',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _sortOrderController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Display Priority (Sort Order)',
                    hintText: '0, 1, 2... lower numbers appear first',
                  ),
                ),
                if (isEditing) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Active Contact'),
                    subtitle: const Text('Inactive contacts remain in call log history'),
                    value: _isActive,
                    onChanged: (val) => setState(() => _isActive = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? 'Update' : 'Save Contact'),
        ),
      ],
    );
  }
}
