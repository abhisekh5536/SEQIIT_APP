import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/facilities_service.dart';
import '../../theme/app_theme.dart';

/// Admin: switch the Facilities module on or off for the society.
///
/// Backed by `module_flags` (key `facilities`). Off hides the section from
/// residents server-side; admins keep access to prepare the catalog.
class FacilitiesSettingsScreen extends StatefulWidget {
  const FacilitiesSettingsScreen({super.key});

  @override
  State<FacilitiesSettingsScreen> createState() =>
      _FacilitiesSettingsScreenState();
}

class _FacilitiesSettingsScreenState extends State<FacilitiesSettingsScreen> {
  bool? _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    FacilitiesService.instance.isModuleEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  Future<void> _toggle(bool value) async {
    HapticFeedback.selectionClick();
    final previous = _enabled;
    setState(() {
      _enabled = value;
      _saving = true;
    });
    try {
      await FacilitiesService.instance.setModuleEnabled(value);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(value
            ? 'Facilities are now visible to residents'
            : 'Facilities are hidden from residents'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _enabled = previous);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not update: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Facilities Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Surface(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: p.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(Icons.event_seat_outlined,
                      size: 19, color: p.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Show Facilities to residents',
                          style: textTheme.titleSmall),
                      const SizedBox(height: 1),
                      Text(
                        _enabled == null
                            ? 'Loading…'
                            : _enabled!
                                ? 'Residents can browse facilities'
                                : 'Hidden from residents',
                        style: textTheme.bodySmall?.copyWith(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _enabled ?? false,
                  onChanged: _enabled == null || _saving ? null : _toggle,
                  activeThumbColor: p.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'While off, you can still add and edit facilities here, and '
              'residents are not notified of status changes.',
              style: textTheme.bodySmall?.copyWith(color: p.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
