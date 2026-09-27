import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/visitor_models.dart';
import 'app_session.dart';
import 'push_messaging_service.dart';
import 'visitors_service.dart';

/// Shows system (tray / heads-up) notifications for live events.
///
/// The in-app bell only updates while the user is looking at the app. This
/// posts an OS notification from the same realtime event, so a resident with
/// the app in the background still hears that someone is at the gate.
///
/// When FCM push is registered the server sends these alerts and this class
/// only draws the ones that arrive in the foreground ([showRemote]). Without
/// FCM it falls back to posting from realtime events, which works only while
/// the app process is alive.
class LocalPushService {
  LocalPushService._();
  static final LocalPushService instance = LocalPushService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Set by the app so a tapped notification can open the right screen.
  GlobalKey<NavigatorState>? navigatorKey;

  bool _initialized = false;

  static const _visitorChannel = AndroidNotificationChannel(
    'visitor_gate',
    'Visitors at gate',
    description: 'Alerts when a visitor is waiting for your approval.',
    importance: Importance.max,
  );

  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) => openRoute(r.payload),
      );

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_visitorChannel);
      _initialized = true;

      // App cold-started by tapping a notification.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        openRoute(launch!.notificationResponse?.payload);
      }
    } catch (e) {
      debugPrint('LocalPushService.init error: $e');
    }
  }

  /// Asks for the Android 13+ / iOS notification permission. Safe to call
  /// repeatedly; the OS only prompts once.
  Future<void> requestPermission() async {
    if (!_initialized) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('LocalPushService.requestPermission error: $e');
    }
  }

  /// Posts a system notification for visitor events meant for this user:
  /// a new gate request at one of their flats, or a decision on a visitor
  /// they logged at the gate.
  Future<void> handleVisitorEvent(VisitorLiveEvent event) async {
    if (!_initialized) return;
    // The server already pushes these; posting here too would double up.
    if (PushMessagingService.instance.isActive) return;
    final v = event.visitor;
    final session = AppSession.instance;

    String? title;
    String? body;

    if (event.isNewGateRequest) {
      final myFlatIds = session.myResidences.map((r) => r.flatId).toSet();
      if (!myFlatIds.contains(v.flatId)) return;
      title = '🚪 Visitor at Gate: ${v.visitorName}';
      body = '${v.category.label} · Tap to approve or deny';
    } else if (event.isApprovalDecision) {
      final myId = _currentUserId;
      if (myId == null || v.createdBy != myId) return;
      final flat = v.flatNumber != null ? ' · Flat ${v.flatNumber}' : '';
      title = v.status == VisitorStatus.approved
          ? '✅ Visitor Approved: ${v.visitorName}'
          : '❌ Visitor Denied: ${v.visitorName}';
      body = v.status == VisitorStatus.denied &&
              (v.deniedReason?.isNotEmpty ?? false)
          ? '${v.deniedReason}$flat'
          : 'Resident responded$flat';
    } else {
      return;
    }

    await _show(tag: 'visitor_${v.id}', title: title, body: body);
  }

  /// Draws an FCM message received while the app is in the foreground,
  /// where Android leaves display to the app.
  Future<void> showRemote(RemoteMessage message) async {
    if (!_initialized) return;
    final n = message.notification;
    if (n == null) return;
    await _show(
      tag: message.data['tag'] ?? message.messageId ?? '',
      title: n.title ?? '',
      body: n.body ?? '',
      route: message.data['route'],
    );
  }

  /// [tag] matches the tag the Edge Function sets on the FCM message. FCM
  /// posts with notification id 0, so the same (tag, 0) pair here replaces
  /// rather than duplicates a server alert for the same visitor.
  Future<void> _show({
    required String tag,
    required String title,
    required String body,
    String? route,
  }) async {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    try {
      await _plugin.show(
        id: isAndroid ? 0 : tag.hashCode & 0x7fffffff,
        title: title,
        body: body,
        payload: route ?? '/visitors',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _visitorChannel.id,
            _visitorChannel.name,
            channelDescription: _visitorChannel.description,
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            ticker: title,
            tag: tag,
            onlyAlertOnce: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('LocalPushService.show error: $e');
    }
  }

  String? get _currentUserId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  String? _pendingRoute;

  void openRoute(String? route) {
    if (route == null || route.isEmpty) return;
    final nav = navigatorKey?.currentState;
    if (nav == null) {
      // Cold start: the navigator is not built yet.
      _pendingRoute = route;
      return;
    }
    nav.pushNamed(route);
  }

  /// Opens the route of the notification that launched the app, once the
  /// navigator exists.
  void flushPendingRoute() {
    final route = _pendingRoute;
    _pendingRoute = null;
    openRoute(route);
  }
}
