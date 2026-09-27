import 'package:flutter/material.dart';

import '../../services/app_session.dart';
import 'admin/admin_vehicles_parking_dashboard.dart';
import 'guard/vehicle_gate_lookup_screen.dart';
import 'resident/resident_vehicles_parking_screen.dart';

class VehiclesParkingRootScreen extends StatelessWidget {
  final bool showBack;
  final bool initialGateMode;

  const VehiclesParkingRootScreen({
    super.key,
    this.showBack = true,
    this.initialGateMode = false,
  });

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

        // A guard opening "Vehicles" wants the gate check, not a resident's
        // own garage — they have neither a flat nor bays of their own.
        if (initialGateMode || AppSession.instance.isGuard) {
          return VehicleGateLookupScreen(
            societyId: AppSession.instance.societyId,
            showAppBar: true,
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

