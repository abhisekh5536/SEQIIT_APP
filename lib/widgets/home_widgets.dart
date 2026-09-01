import 'package:flutter/material.dart';

import '../models/society_models.dart';
import '../theme/app_theme.dart';

/// Section heading with an optional trailing action.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

/// The hero card carrying the single most important number.
///
/// Renders one of two states from the same gradient shell:
///  * pending — outstanding [amount] with a primary pay action;
///  * cleared ([duesCleared]) — a calm "all clear" summary with the last
///    payment, next invoice date and receipt actions.
class HeroBalanceCard extends StatelessWidget {
  final String societyName;
  final String period;

  /// Outstanding amount, shown while dues are pending.
  final String amount;

  /// Caption under [amount], shown while dues are pending.
  final String dueCaption;
  final VoidCallback onPay;

  /// Switches the card to its "no dues pending" presentation.
  final bool duesCleared;

  /// One-line settlement summary for the cleared state,
  /// e.g. '₹4,850 paid on 5 Aug · Receipt #SH-2408'.
  final String? paidSummary;

  /// When the next invoice lands, e.g. 'Next invoice · 1 Sep 2026'.
  final String? nextInvoiceCaption;
  final VoidCallback? onReceipts;
  final VoidCallback? onLedger;

  const HeroBalanceCard({
    super.key,
    required this.societyName,
    required this.period,
    required this.amount,
    required this.dueCaption,
    required this.onPay,
    this.duesCleared = false,
    this.paidSummary,
    this.nextInvoiceCaption,
    this.onReceipts,
    this.onLedger,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.heroStart, p.heroEnd],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          _decorationCircle(context, p, Alignment.topRight, radius: 120),
          _decorationCircle(context, p, Alignment.bottomLeft, radius: 90),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: duesCleared
                ? _buildClearedState(context, p)
                : _buildPendingState(context, p),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingState(BuildContext context, AppPaletteData p) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _periodPill(textTheme),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'Maintenance due',
          style: textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          amount,
          style: textTheme.headlineLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          dueCaption,
          style: textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: onPay,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: p.heroStart,
                  ),
                  child: const Text('Pay now'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            _ledgerButton(context),
          ],
        ),
      ],
    );
  }

  Widget _buildClearedState(BuildContext context, AppPaletteData p) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _periodPill(textTheme),
            const Spacer(),
            _paidChip(textTheme),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.task_alt_rounded,
              size: 26, color: Colors.white),
        ),
        const SizedBox(height: 12),
        Text(
          'All clear!',
          style: textTheme.headlineLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          nextInvoiceCaption ??
              'Your maintenance account has no pending dues.',
          style: textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        if (paidSummary != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.receipt_long_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    paidSummary!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: onReceipts,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: p.heroStart,
                  ),
                  icon: const Icon(Icons.receipt_outlined, size: 18),
                  label: const Text('View receipts'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            _ledgerButton(context),
          ],
        ),
      ],
    );
  }

  Widget _periodPill(TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        period,
        style: textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _paidChip(TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            'Paid',
            style: textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ledgerButton(BuildContext context) {
    return TextButton(
      onPressed: onLedger,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 46),
      ),
      child: const Text('Ledger'),
    );
  }

  Widget _decorationCircle(
    BuildContext context,
    AppPaletteData p,
    Alignment alignment, {
    required double radius,
  }) {
    return Align(
      alignment: alignment,
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.mint.withValues(alpha: 0.12),
        ),
      ),
    );
  }
}

/// Compact labelled quick actions (Revolut-style action bar).
class QuickActionRail extends StatelessWidget {
  final List<QuickAction> actions;
  final void Function(QuickAction action) onSelected;

  const QuickActionRail({
    super.key,
    required this.actions,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) Container(width: 1, height: 40, color: p.hairline),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelected(actions[i]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: p.primary.withValues(alpha: 0.12),
                        child: Icon(
                          actions[i].icon,
                          size: 20,
                          color: p.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        actions[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: p.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small single-metric stat card.
class StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color accent;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = Surface(
      padding: const EdgeInsets.all(14),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: card,
      );
    }
    return card;
  }
}

/// Service entry tile in the services grid.
class ServiceTile extends StatelessWidget {
  final SocietyService service;
  final Color accent;

  const ServiceTile({super.key, required this.service, required this.accent});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);

    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.pushNamed(context, service.route),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: p.hairline),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(service.icon, size: 22, color: accent),
              ),
              const SizedBox(height: 12),
              Text(
                service.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                service.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Notice / announcement card with a semantic accent dot.
class NoticeCard extends StatelessWidget {
  final Announcement announcement;

  const NoticeCard({super.key, required this.announcement});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final accent = _tagColor(p, announcement.tagId);

    return Surface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      radius: 16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.campaign_rounded, size: 20, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        announcement.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        announcement.tag,
                        style: textTheme.labelSmall?.copyWith(
                          color: accent,
                          fontSize: 10,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  announcement.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: p.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _relativeTime(announcement.date),
                  style: textTheme.labelMedium?.copyWith(
                    color: p.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _tagColor(AppPaletteData p, String tagId) {
    return switch (tagId) {
      'important' => p.warning,
      'safety' => p.success,
      'event' => p.primary,
      _ => p.secondary,
    };
  }

  String _relativeTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}

/// Friendly empty state that explains what will appear here.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: p.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: p.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}