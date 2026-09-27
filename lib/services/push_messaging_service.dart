import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_session.dart';
import 'local_push_service.dart';

/// Server push via Firebase Cloud Messaging.
///
/// Supabase stays the backend: this only hands the device's FCM token to
/// `register_device_token`, and the `push-visitor` Edge Function sends
/// through FCM when a visitor row changes. FCM is what lets Android show the
/// alert when the app is closed — a Supabase socket dies with the process.
class PushMessagingService {
  PushMessagingService._();
  static final PushMessagingService instance = PushMessagingService._();

  bool _firebaseReady = false;
  String? _registeredToken;
  StreamSubscription<String>? _tokenRefreshSub;

  /// True once this device's token is stored server-side, meaning the
  /// server will deliver visitor alerts and the app need not post its own.
  bool get isActive => _registeredToken != null;

  Future<void> init() async {
    if (kIsWeb || _firebaseReady) return;
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (e) {
      // Missing platform config (e.g. iOS without GoogleService-Info.plist):
      // fall back to realtime-only local notifications.
      debugPrint('Firebase unavailable, push disabled: $e');
      return;
    }

    // In the foreground Android does not draw FCM notifications itself.
    FirebaseMessaging.onMessage.listen(LocalPushService.instance.showRemote);

    // Tapped while the app was in the background.
    FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => LocalPushService.instance.openRoute(m.data['route']));

    // Tapped while the app was closed.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      LocalPushService.instance.openRoute(initial.data['route']);
    }
  }

  /// Stores this device's token against the signed-in user. Call after
  /// login; safe to call repeatedly.
  Future<void> register() async {
    if (!_firebaseReady) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveToken(token);

      _tokenRefreshSub ??=
          FirebaseMessaging.instance.onTokenRefresh.listen(_saveToken);
    } catch (e) {
      debugPrint('PushMessagingService.register error: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    try {
      await Supabase.instance.client.rpc('register_device_token', params: {
        'p_token': token,
        'p_platform': defaultTargetPlatform.name,
        'p_society_id': AppSession.instance.societyId,
      });
      _registeredToken = token;
    } catch (e) {
      // Pre-migration-17 databases have no such RPC; realtime local
      // notifications keep working while the app is alive.
      debugPrint('register_device_token failed: $e');
    }
  }

  /// Detaches this device from the user. Must run BEFORE signOut — after it
  /// the RPC is unauthenticated and the next user of the phone would get
  /// the previous user's visitor alerts.
  Future<void> unregister() async {
    final token = _registeredToken;
    _registeredToken = null;
    if (token == null) return;
    try {
      await Supabase.instance.client
          .rpc('unregister_device_token', params: {'p_token': token});
    } catch (e) {
      debugPrint('unregister_device_token failed: $e');
    }
  }
}
