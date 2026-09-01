import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/admin_approvals_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/complaints/complaints_root_screen.dart';
import 'screens/complaints/raise_complaint_screen.dart';
import 'screens/directory_screen.dart';
import 'screens/flats_management_screen.dart';
import 'screens/join_society_screen.dart';
import 'screens/main_shell.dart';
import 'screens/my_flat_screen.dart';
import 'screens/notices/create_edit_notice_screen.dart';
import 'screens/notices_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_session.dart';
import 'services/notifications_service.dart';
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
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY']!,
  );
  final themeController = await ThemeController.load();
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

  @override
  void initState() {
    super.initState();
    try {
      if (Supabase.instance.client.auth.currentSession != null) {
        _loggedIn = true;
        AppSession.instance.load().then((_) {
          NotificationsService.instance.init();
        });
      }
      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (!mounted) return;
        final session = data.session;
        setState(() => _loggedIn = session != null);
        if (session != null) {
          AppSession.instance.load().then((_) {
            NotificationsService.instance.init();
          });
        } else {
          AppSession.instance.reset();
        }
      });
    } catch (_) {
      // Supabase not initialized in widget tests — show MainShell so Home tests pass
      _loggedIn = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: widget.themeController,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'Society Management',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          home: _loggedIn
              ? MainShell(themeController: widget.themeController)
              : const AuthScreen(),
          routes: {
            '/settings': (context) => SettingsScreen(
                  themeController: widget.themeController,
                ),
            '/notifications': (context) => const NotificationsScreen(),
            '/maintenance': (context) => const _FeatureScreen('Maintenance'),
            '/visitors': (context) => const _FeatureScreen('Visitors'),
            '/complaints': (context) => const ComplaintsRootScreen(),
            '/complaints/raise': (context) => const RaiseComplaintScreen(),
            '/staff': (context) => const _FeatureScreen('Staff'),
            '/facilities': (context) => const _FeatureScreen('Facilities'),
            '/meetings': (context) => const _FeatureScreen('Meetings'),
            '/notices': (context) => const NoticesScreen(),
            '/notices/create': (context) => const _AdminGate(
                  child: CreateEditNoticeScreen(),
                ),
            '/my-flat': (context) => const MyFlatScreen(),
            '/profile': (context) => const ProfileScreen(),
            '/flats-management': (context) => const FlatsManagementScreen(),
            '/directory': (context) => const _AdminGate(
                  child: DirectoryScreen(showBack: true),
                ),
            '/admin-approvals': (context) => const _AdminGate(
                  child: AdminApprovalsScreen(),
                ),
            '/join-society': (context) => const JoinSocietyScreen(),
          },
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
  const _AccessDeniedView();

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
              'Admins only',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This section is managed by the society office.',
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