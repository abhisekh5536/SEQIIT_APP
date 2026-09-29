import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/admin/security_staff_screen.dart';
import 'screens/admin_approvals_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/complaints/complaints_root_screen.dart';
import 'screens/complaints/raise_complaint_screen.dart';
import 'screens/directory_screen.dart';
import 'screens/facilities/facilities_root_screen.dart';
import 'screens/flats_management_screen.dart';
import 'screens/guard/guard_access_revoked_screen.dart';
import 'screens/guard/guard_alerts_screen.dart';
import 'screens/guard/guard_profile_screen.dart';
import 'screens/guard/guard_shell.dart';
import 'screens/join_society_screen.dart';
import 'screens/main_shell.dart';
import 'screens/my_flat_screen.dart';
import 'screens/notices/create_edit_notice_screen.dart';
import 'screens/notices_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/security/security_root_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/vehicles/guard/vehicle_gate_lookup_screen.dart';
import 'screens/vehicles/vehicles_parking_root_screen.dart';
import 'screens/visitors/visitors_root_screen.dart';
import 'services/app_session.dart';
import 'services/guard_service.dart';
import 'services/local_push_service.dart';
import 'services/notification_preferences_service.dart';
import 'services/notifications_service.dart';
import 'services/push_messaging_service.dart';
import 'services/security_service.dart';
import 'services/visitors_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!.trim(),
    publishableKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY']!.trim(),
  );
  final themeController = await ThemeController.load();
  await LocalPushService.instance.init();
  await PushMessagingService.instance.init();
  runApp(SocietyApp(themeController: themeController));
}

class SocietyApp extends StatefulWidget {
  final ThemeController themeController;

  const SocietyApp({super.key, required this.themeController});

  @override
  State<SocietyApp> createState() => _SocietyAppState();
}

class _SocietyAppState extends State<SocietyApp> {
  bool _loggedIn = false;
  StreamSubscription<VisitorLiveEvent>? _visitorLiveSub;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    LocalPushService.instance.navigatorKey = _navigatorKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_loggedIn) LocalPushService.instance.flushPendingRoute();
    });
    try {
      if (Supabase.instance.client.auth.currentSession != null) {
        _loggedIn = true;
        AppSession.instance.load().then((_) {
          NotificationsService.instance.init();
          _startVisitorRealtime();
        });
      }
      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (!mounted) return;
        final session = data.session;
        setState(() => _loggedIn = session != null);
        if (session != null) {
          AppSession.instance.load().then((_) {
            NotificationsService.instance.init();
            _startVisitorRealtime();
          });
        } else {
          _stopVisitorRealtime();
          AppSession.instance.reset();
        }
      });
    } catch (_) {
      // Supabase not initialized in widget tests — show MainShell so Home tests pass
      _loggedIn = true;
    }
  }

  /// Subscribing at the app level, not per screen, means a gate approval
  /// also refreshes the notification bell and the home badge while the user
  /// is somewhere else in the app.
  void _startVisitorRealtime() {
    final societyId = AppSession.instance.societyId;
    if (societyId == null || societyId.isEmpty) return;

    VisitorsService.instance.initRealtime(societyId);
    LocalPushService.instance.requestPermission();
    PushMessagingService.instance.register();
    NotificationPreferencesService.instance.load();
    _visitorLiveSub?.cancel();
    _visitorLiveSub = VisitorsService.instance.onVisitorEvent.listen((event) {
      if (event.isApprovalDecision || event.isNewGateRequest) {
        // Debounced: a busy gate produces a burst of events, and each
        // fetch costs several queries.
        NotificationsService.instance.refreshSoon();
        LocalPushService.instance.handleVisitorEvent(event);
      }
    });
  }

  void _stopVisitorRealtime() {
    _visitorLiveSub?.cancel();
    _visitorLiveSub = null;
    VisitorsService.instance.disposeRealtime();
    // Otherwise the next account to sign in on this phone keeps listening
    // to the previous society's SOS channel.
    SecurityService.instance.disposeRealtime();
    GuardService.instance.reset();
  }

  @override
  void dispose() {
    _visitorLiveSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: widget.themeController,
      builder: (context, themeMode, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'Society Management',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          home: _loggedIn
              ? _RoleHome(themeController: widget.themeController)
              : const AuthScreen(),
          routes: {
            '/settings': (context) => SettingsScreen(
                  themeController: widget.themeController,
                ),
            '/notifications': (context) => const NotificationsScreen(),
            '/maintenance': (context) =>
                const _NotForGuards(child: _FeatureScreen('Maintenance')),
            '/visitors': (context) => const VisitorsRootScreen(),
            '/complaints': (context) =>
                const _NotForGuards(child: ComplaintsRootScreen()),
            '/complaints/raise': (context) =>
                const _NotForGuards(child: RaiseComplaintScreen()),
            '/staff': (context) =>
                const _NotForGuards(child: _FeatureScreen('Staff')),
            '/facilities': (context) =>
                const _NotForGuards(child: FacilitiesRootScreen()),
            '/meetings': (context) =>
                const _NotForGuards(child: _FeatureScreen('Meetings')),
            '/notices': (context) => const NoticesScreen(),
            '/notices/create': (context) => const _AdminGate(
                  child: CreateEditNoticeScreen(),
                ),
            '/my-flat': (context) =>
                const _NotForGuards(child: MyFlatScreen()),
            // A guard has no flat or household; their page is the gate one.
            '/profile': (context) => AppSession.instance.isGuard
                ? GuardProfileScreen(
                    themeController: widget.themeController,
                    showBack: true,
                  )
                : const ProfileScreen(),
            '/flats-management': (context) =>
                const _NotForGuards(child: FlatsManagementScreen()),
            '/admin-vehicles': (context) => const _AdminGate(
                  child: VehiclesParkingRootScreen(),
                ),
            '/vehicles': (context) => const VehiclesParkingRootScreen(),
            '/gate-vehicles': (context) => const VehicleGateLookupScreen(),
            '/directory': (context) => const _AdminGate(
                  child: DirectoryScreen(showBack: true),
                ),
            '/admin-approvals': (context) => const _AdminGate(
                  child: AdminApprovalsScreen(),
                ),
            '/join-society': (context) =>
                const _NotForGuards(child: JoinSocietyScreen()),
            // Notification taps for SOS land here. A guard responds from
            // the gate view, not the resident "raise an SOS" screen.
            '/security': (context) => AppSession.instance.isGuard
                ? const GuardAlertsScreen(showBack: true)
                : const SecurityRootScreen(),
            '/security-staff': (context) => const _AdminGate(
                  child: SecurityStaffScreen(),
                ),
          },
        );
      },
    );
  }
}

/// Picks the shell for the signed-in role once the session knows it.
///
/// Residents and admins get [MainShell] straight away (it shows its own
/// skeleton while loading). A guard switches to [GuardShell] as soon as the
/// session confirms the `society_guards` row.
class _RoleHome extends StatelessWidget {
  final ThemeController themeController;

  const _RoleHome({required this.themeController});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSession.instance,
      builder: (context, _) {
        final session = AppSession.instance;
        if (session.isGuard) {
          return GuardShell(themeController: themeController);
        }
        if (session.isGuardDeactivated) {
          return const GuardAccessRevokedScreen();
        }
        return MainShell(themeController: themeController);
      },
    );
  }
}

/// Keeps a guard out of resident and office screens. RLS already returns
/// nothing to them there; this makes the refusal visible instead of an
/// empty page.
class _NotForGuards extends StatelessWidget {
  final Widget child;

  const _NotForGuards({required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSession.instance,
      builder: (context, _) {
        if (!AppSession.instance.isGuard) return child;
        return const Scaffold(
          body: _AccessDeniedView(
            title: 'Not on the gate app',
            message: 'This section is for residents and the society office.',
          ),
        );
      },
    );
  }
}

class _AdminGate extends StatelessWidget {
  final Widget child;

  const _AdminGate({required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSession.instance,
      builder: (context, _) {
        if (!AppSession.instance.isLoaded || AppSession.instance.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!AppSession.instance.isAdmin) {
          return const Scaffold(body: _AccessDeniedView());
        }
        return child;
      },
    );
  }
}

class _AccessDeniedView extends StatelessWidget {
  final String title;
  final String message;

  const _AccessDeniedView({
    this.title = 'Admins only',
    this.message = 'This section is managed by the society office.',
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: p.danger.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.lock_outline_rounded, size: 38, color: p.danger),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: p.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(backgroundColor: p.primary),
              child: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureScreen extends StatelessWidget {
  final String feature;

  const _FeatureScreen(this.feature);

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
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
                  const SizedBox(width: 4),
                  Text(
                    feature,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: p.primary.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.construction_rounded,
                        size: 42,
                        color: p.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '$feature is being set up',
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Text(
                        'This space will be live soon. You will be able to manage it right from your home screen.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: p.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}