import 'package:flutter/material.dart';

import '../data/sample_data.dart';
import '../theme/app_theme.dart';
import '../widgets/home_widgets.dart';

class NoticesScreen extends StatelessWidget {
  const NoticesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              'Notices',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text('Board updates and community alerts', style: textTheme.bodySmall),
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: p.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.primary.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: p.primary.withValues(alpha: 0.15),
                    child: Icon(Icons.notifications_none_rounded,
                        color: p.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${sampleAnnouncements.length} active notices',
                      style: textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            for (final announcement in sampleAnnouncements) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: NoticeCard(announcement: announcement),
              ),
            ],
          ],
        ),
      ),
    );
  }
}