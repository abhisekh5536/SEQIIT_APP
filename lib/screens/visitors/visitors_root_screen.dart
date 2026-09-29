import 'package:flutter/material.dart';

import '../../services/app_session.dart';
import '../guard/guard_register_screen.dart';
import 'admin_visitors_dashboard.dart';
import 'resident_visitors_screen.dart';

class VisitorsRootScreen extends StatelessWidget {
  final bool showBack;

  const VisitorsRootScreen({super.key, this.showBack = true});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSession.instance,
      builder: (context, _) {
        if (!AppSession.instance.isLoaded && AppSession.instance.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // A guard works the gate register, not a personal visitor list —
        // they have no flat, so the resident screen would be empty for them.
        if (AppSession.instance.isGuard) {
          return GuardRegisterScreen(showBack: showBack);
        }
        if (AppSession.instance.isAdmin) {
          return AdminVisitorsDashboard(showBack: showBack);
        } else {
          return ResidentVisitorsScreen(showBack: showBack);
        }
      },
    );
  }
}
