import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A group of alerts the user can switch push on or off for.
///
/// [key] must match `notification_preferences.module` and
/// `notification_module()` in migrations 18–19; [channelId] must match
/// `channelFor()` in the push-notify Edge Function.
enum PushModule {
  visitors(
    key: 'visitors',
    label: 'Visitors',
    subtitle: 'Gate requests, approvals and entries',
    icon: Icons.sensor_door_outlined,
    channelId: 'visitor_gate',
    channelName: 'Visitors at gate',
  ),
  security(
    key: 'security',
    label: 'Security & SOS',
    subtitle: 'Emergency alerts and their status',
    icon: Icons.emergency_outlined,
    channelId: 'security',
    channelName: 'Security & SOS',
  ),
  helpdesk(
    key: 'helpdesk',
    label: 'Helpdesk',
    subtitle: 'Complaint updates and resolutions',
    icon: Icons.support_agent_outlined,
    channelId: 'helpdesk',
    channelName: 'Helpdesk',
  ),
  notices(
    key: 'notices',
    label: 'Notices',
    subtitle: 'Society announcements and circulars',
    icon: Icons.campaign_outlined,
    channelId: 'notices',
    channelName: 'Notices',
  ),
  approvals(
    key: 'approvals',
    label: 'Approvals',
    subtitle: 'Resident join requests and decisions',
    icon: Icons.how_to_reg_outlined,
    channelId: 'approvals',
    channelName: 'Approvals',
  ),
  parking(
    key: 'parking',
    label: 'Vehicles & Parking',
    subtitle: 'Parking bay requests and decisions',
    icon: Icons.local_parking_outlined,
    channelId: 'parking',
    channelName: 'Vehicles & Parking',
  ),
  facilities(
    key: 'facilities',
    label: 'Facilities',
    subtitle: 'When a facility closes or reopens (off by default)',
    icon: Icons.pool_outlined,
    channelId: 'facilities',
    channelName: 'Facilities',
    defaultEnabled: false,
  ),
  general(
    key: 'general',
    label: 'General',
    subtitle: 'Everything else from the society',
    icon: Icons.notifications_none_rounded,
    channelId: 'general',
    channelName: 'General',
  );

  const PushModule({
    required this.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.channelId,
    required this.channelName,
    this.defaultEnabled = true,
  });

  final String key;
  final String label;
  final String subtitle;
  final IconData icon;
  final String channelId;
  final String channelName;

  /// Must match push_module_default() in migration 19. Facility status
  /// changes are opt-in so a routine pool cleaning is not a phone alert.
  final bool defaultEnabled;
}

/// Per-module push on/off, stored server-side so the push-notify function
/// skips opted-out users before anything is sent.
///
/// Missing rows mean the module's [PushModule.defaultEnabled]. A local copy keeps the switches correct
/// offline and before the first fetch completes.
class NotificationPreferencesService extends ChangeNotifier {
  NotificationPreferencesService._();
  static final NotificationPreferencesService instance =
      NotificationPreferencesService._();

  static const _cacheKey = 'seqiit_push_module_prefs';

  final Map<PushModule, bool> _enabled = {
    for (final m in PushModule.values) m: m.defaultEnabled,
  };

  bool isEnabled(PushModule module) =>
      _enabled[module] ?? module.defaultEnabled;

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    await _loadCache();

    final client = _client;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return;

    try {
      final rows = await client
          .from('notification_preferences')
          .select('module, push_enabled')
          .eq('user_id', userId);
      for (final m in PushModule.values) {
        _enabled[m] = m.defaultEnabled;
      }
      for (final row in (rows as List)) {
        final module = _byKey(row['module']?.toString());
        if (module != null) _enabled[module] = row['push_enabled'] == true;
      }
      notifyListeners();
      await _saveCache();
    } catch (e) {
      // Pre-migration-18 databases have no such table.
      debugPrint('NotificationPreferencesService.load error: $e');
    }
  }

  Future<void> setEnabled(PushModule module, bool enabled) async {
    final previous = isEnabled(module);
    _enabled[module] = enabled;
    notifyListeners();

    final client = _client;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return;

    try {
      await client.from('notification_preferences').upsert({
        'user_id': userId,
        'module': module.key,
        'push_enabled': enabled,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _saveCache();
    } catch (e) {
      // The server still holds the old value and would keep sending, so
      // the switch must not claim otherwise.
      debugPrint('NotificationPreferencesService.setEnabled error: $e');
      _enabled[module] = previous;
      notifyListeners();
      rethrow;
    }
  }

  PushModule? _byKey(String? key) {
    for (final m in PushModule.values) {
      if (m.key == key) return m;
    }
    return null;
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return;
      final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
      map.forEach((key, value) {
        final module = _byKey(key);
        if (module != null) _enabled[module] = value == true;
      });
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode({for (final e in _enabled.entries) e.key.key: e.value}),
      );
    } catch (_) {}
  }
}
