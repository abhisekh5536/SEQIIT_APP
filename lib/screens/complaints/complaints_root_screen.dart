import 'package:flutter/material.dart';

import '../../services/app_session.dart';
import 'admin_helpdesk_screen.dart';
import 'resident_complaints_screen.dart';

class ComplaintsRootScreen extends StatelessWidget {
  final bool showBack;

  const ComplaintsRootScreen({super.key, this.showBack = true});

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

        if (AppSession.instance.isAdmin) {
          return AdminHelpdeskScreen(showBack: showBack);
        } else {
          return ResidentComplaintsScreen(showBack: showBack);
        }
      },
    );
  }
}
