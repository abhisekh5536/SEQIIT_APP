import 'package:flutter/material.dart';

import '../../services/app_session.dart';
import 'admin/admin_vehicles_parking_dashboard.dart';
import 'resident/resident_vehicles_parking_screen.dart';

class VehiclesParkingRootScreen extends StatelessWidget {
  final bool showBack;

  const VehiclesParkingRootScreen({super.key, this.showBack = true});

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
          return AdminVehiclesParkingDashboard(showBack: showBack);
        } else {
          return ResidentVehiclesParkingScreen(showBack: showBack);
        }
      },
    );
  }
}
