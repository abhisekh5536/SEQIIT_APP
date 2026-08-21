import 'package:flutter/material.dart';

import 'screens/directory_screen.dart';
import 'screens/main_shell.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
          initialRoute: '/',
          routes: {
            '/': (context) => MainShell(
                  themeController: widget.themeController,
                ),
            '/settings': (context) => SettingsScreen(
                  themeController: widget.themeController,
                ),
            '/maintenance': (context) => const _FeatureScreen('Maintenance'),
            '/visitors': (context) => const _FeatureScreen('Visitors'),
            '/complaints': (context) => const _FeatureScreen('Complaints'),
            '/staff': (context) => const _FeatureScreen('Staff'),
            '/facilities': (context) => const _FeatureScreen('Facilities'),
            '/meetings': (context) => const _FeatureScreen('Meetings'),
            '/notices': (context) => const _FeatureScreen('Notices'),
            '/directory': (context) => const DirectoryScreen(showBack: true),
          },
        );
      },
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