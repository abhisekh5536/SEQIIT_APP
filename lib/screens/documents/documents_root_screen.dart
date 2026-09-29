import 'package:flutter/material.dart';

import '../../services/app_session.dart';
import 'admin_documents_dashboard.dart';
import 'resident_documents_screen.dart';

class DocumentsRootScreen extends StatelessWidget {
  final bool showBack;

  const DocumentsRootScreen({super.key, this.showBack = true});

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
          return AdminDocumentsDashboard(showBack: showBack);
        } else {
          return ResidentDocumentsScreen(showBack: showBack);
        }
      },
    );
  }
}
