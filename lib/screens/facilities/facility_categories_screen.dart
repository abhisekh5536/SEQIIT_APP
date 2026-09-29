import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/facility_models.dart';
import '../../services/facilities_service.dart';
import '../../theme/app_theme.dart';

/// Admin: the society's facility categories.
///
/// Shared defaults are listed read-only; the society adds, renames and
/// removes its own.
class FacilityCategoriesScreen extends StatefulWidget {
  const FacilityCategoriesScreen({super.key});

  @override
  State<FacilityCategoriesScreen> createState() =>
      _FacilityCategoriesScreenState();
}

class _FacilityCategoriesScreenState extends State<FacilityCategoriesScreen> {
  List<FacilityCategory> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await FacilitiesService.instance.fetchCategories();
      if (mounted) {
        setState(() {
          _categories = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('Could not load categories: $e');
      }
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// Returns the entered name, or null if cancelled.
  Future<String?> _askName({String? initial, required String title}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Indoor Games'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  bool _isDuplicate(String name, {String? exceptId}) => _categories.any(
      (c) => c.id != exceptId && c.name.toLowerCase() == name.toLowerCase());

  Future<void> _add() async {
    final name = (await _askName(title: 'New category'))?.trim();
    if (name == null || name.isEmpty) return;
    if (_isDuplicate(name)) {
      _snack('"$name" already exists.');
      return;
    }
    try {
      await FacilitiesService.instance.addCategory(name);
      HapticFeedback.lightImpact();
      _load();
    } catch (e) {
      _snack('Could not add: $e');
    }
  }

  Future<void> _rename(FacilityCategory c) async {
    final name =
        (await _askName(initial: c.name, title: 'Rename category'))?.trim();
    if (name == null || name.isEmpty || name == c.name) return;
    if (_isDuplicate(name, exceptId: c.id)) {
      _snack('"$name" already exists.');
      return;
    }
    try {
      await FacilitiesService.instance.renameCategory(c.id, name);
      _load();
    } catch (e) {
      _snack('Could not rename: $e');
    }
  }

  Future<void> _delete(FacilityCategory c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${c.name}"?'),
        content: const Text(
            'Facilities in this category stay listed as Uncategorised.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FacilitiesService.instance.deleteCategory(c.id);
      _load();
    } catch (e) {
      _snack('Could not delete: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final defaults = _categories.where((c) => c.isDefault).toList();
    final custom = _categories.where((c) => !c.isDefault).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Facility Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add category'),
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                children: [
                  _groupTitle(context, 'Your society'),
                  const SizedBox(height: 8),
                  if (custom.isEmpty)
                    Surface(
                      child: Text(
                        'No custom categories yet. Add one for anything the '
                        'defaults below do not cover.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: p.textSecondary),
                      ),
                    )
                  else
                    Surface(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < custom.length; i++) ...[
                            if (i > 0)
                              Divider(height: 1, color: p.hairline, indent: 16),
                            _tile(p, custom[i], editable: true),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  _groupTitle(context, 'Default · shared by all societies'),
                  const SizedBox(height: 8),
                  Surface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < defaults.length; i++) ...[
                          if (i > 0)
                            Divider(height: 1, color: p.hairline, indent: 16),
                          _tile(p, defaults[i], editable: false),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _groupTitle(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          title.toUpperCase(),
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.8),
        ),
      );

  Widget _tile(AppPaletteData p, FacilityCategory c, {required bool editable}) {
    return ListTile(
      leading: Icon(c.icon, color: p.primary),
      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: editable
          ? PopupMenuButton<String>(
              onSelected: (v) => v == 'rename' ? _rename(c) : _delete(c),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            )
          : Icon(Icons.lock_outline_rounded, size: 18, color: p.textTertiary),
    );
  }
}
