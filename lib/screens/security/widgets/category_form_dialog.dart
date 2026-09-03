import 'package:flutter/material.dart';

import '../../../models/security_models.dart';
import '../../../services/app_session.dart';
import '../../../services/security_service.dart';

class CategoryFormDialog extends StatefulWidget {
  final EmergencyCategory? category;
  final VoidCallback onSaved;

  const CategoryFormDialog({
    super.key,
    this.category,
    required this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    EmergencyCategory? category,
    required VoidCallback onSaved,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => CategoryFormDialog(
        category: category,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _sortOrderController;
  late String _selectedIconKey;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _sortOrderController =
        TextEditingController(text: (widget.category?.sortOrder ?? 0).toString());
    _selectedIconKey = widget.category?.iconKey ?? 'shield';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final societyId = AppSession.instance.societyId;
    if (societyId == null) return;

    setState(() => _isSaving = true);
    final sortOrder = int.tryParse(_sortOrderController.text.trim()) ?? 0;

    try {
      if (widget.category == null) {
        await SecurityService.instance.createCategory(
          societyId: societyId,
          name: _nameController.text.trim(),
          iconKey: _selectedIconKey,
          sortOrder: sortOrder,
        );
      } else {
        await SecurityService.instance.updateCategory(
          categoryId: widget.category!.id,
          name: _nameController.text.trim(),
          iconKey: _selectedIconKey,
          sortOrder: sortOrder,
        );
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving category: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.category != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Category' : 'New Contact Category'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Category Name *',
                  hintText: 'e.g. Electrician, Plumbing, Gate Security',
                ),
                validator: (val) => (val == null || val.trim().isEmpty)
                    ? 'Name is required'
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                'Select Icon',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: SecurityIconHelper.availableKeys.map((key) {
                  final isSelected = _selectedIconKey == key;
                  return InkWell(
                    onTap: () => setState(() => _selectedIconKey = key),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context).primaryColor.withAlpha(40)
                            : (isDark ? Colors.grey[800] : Colors.grey[200]),
                        border: Border.all(
                          color: isSelected
                              ? Theme.of(context).primaryColor
                              : Colors.transparent,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        SecurityIconHelper.getIconData(key),
                        size: 20,
                        color: isSelected
                            ? Theme.of(context).primaryColor
                            : (isDark ? Colors.grey[300] : Colors.grey[700]),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _sortOrderController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Display Priority (Sort Order)',
                  hintText: '0, 1, 2... lower numbers appear first',
                ),
              ),
            ],
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
              : Text(isEditing ? 'Update' : 'Create'),
        ),
      ],
    );
  }
}
