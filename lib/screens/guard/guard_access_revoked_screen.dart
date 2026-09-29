import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/app_session.dart';
import '../../theme/app_theme.dart';

/// Shown to a guard the society has switched off. Their session still
/// signs in, but every gate policy now refuses them — say so plainly
/// instead of showing an empty resident home.
class GuardAccessRevokedScreen extends StatelessWidget {
  const GuardAccessRevokedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: p.danger.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.no_accounts_rounded,
                    size: 40,
                    color: p.danger,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Gate access turned off',
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your guard account at ${AppSession.instance.societyName.isEmpty ? 'this society' : AppSession.instance.societyName} is no longer active. Contact the society office if this is a mistake.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(color: p.textSecondary),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      await Supabase.instance.client.auth.signOut();
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
