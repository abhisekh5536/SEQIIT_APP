import 'package:flutter/material.dart';

import '../../services/app_session.dart';
import 'admin_facilities_screen.dart';
import 'resident_facilities_screen.dart';

/// Entry point for `/facilities`: admins manage, everyone else browses.
class FacilitiesRootScreen extends StatelessWidget {
  final bool showBack;

  const FacilitiesRootScreen({super.key, this.showBack = true});

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
        return AppSession.instance.isAdmin
            ? AdminFacilitiesScreen(showBack: showBack)
            : ResidentFacilitiesScreen(showBack: showBack);
      },
    );
  }
}
