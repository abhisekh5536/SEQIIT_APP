import 'package:flutter/material.dart';

import '../../services/app_session.dart';
import 'admin/admin_marketplace_screen.dart';
import 'resident/marketplace_feed_screen.dart';

class MarketplaceRootScreen extends StatelessWidget {
  final bool showBack;

  const MarketplaceRootScreen({super.key, this.showBack = true});

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
          return AdminMarketplaceScreen(showBack: showBack);
        } else {
          return MarketplaceFeedScreen(showBack: showBack);
        }
      },
    );
  }
}
