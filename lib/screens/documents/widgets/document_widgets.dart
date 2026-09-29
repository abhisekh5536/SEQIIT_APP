import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/resident_document_models.dart';
import '../../../theme/app_theme.dart';

final _day = DateFormat('d MMM yyyy');

String formatDocDate(DateTime d) => _day.format(d);

IconData iconForDocType(ResidentDocType t) => switch (t.category) {
  DocumentCategory.identity => Icons.badge_outlined,
  DocumentCategory.tenancy =>
    t == ResidentDocType.policeVerification
        ? Icons.local_police_outlined
        : Icons.description_outlined,
  DocumentCategory.ownership => Icons.home_work_outlined,
};

Color statusColor(AppPaletteData p, ResidentDocStatus s) => switch (s) {
  ResidentDocStatus.verified => p.success,
  ResidentDocStatus.pending => p.warning,
  ResidentDocStatus.rejected => p.danger,
  _ => p.textTertiary,
};

/// "Valid till 12 Aug 2027 · 45 days left", or null when there is no date.
String? validityText(ResidentDocument d, [DateTime? now]) {
  final until = d.validUntil;
  if (until == null) return null;
  final days = d.daysLeft(now) ?? 0;
  return switch (d.expiryState(now)) {
    DocumentExpiry.expired => 'Ended on ${formatDocDate(until)}',
    DocumentExpiry.expiringSoon =>
      'Ends ${formatDocDate(until)} · ${days == 0 ? 'today' : '$days days left'}',
    _ => 'Valid till ${formatDocDate(until)}',
  };
}

class DocChip extends StatelessWidget {
  final String label;
  final Color color;

  const DocChip(this.label, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

class DocNote extends StatelessWidget {
  final String text;
  final IconData icon;

  const DocNote(this.text, {super.key, this.icon = Icons.lock_outline_rounded});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: p.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: p.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// One document in a person's list.
class DocumentTile extends StatelessWidget {
  final ResidentDocument document;
  final VoidCallback? onOpen;
  final VoidCallback? onWithdraw;

  const DocumentTile({
    super.key,
    required this.document,
    this.onOpen,
    this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final d = document;
    final expiry = d.expiryState();
    final dim = !d.isCurrent && d.status != ResidentDocStatus.rejected;

    final lines = <String>[
      ?validityText(d),
      if (d.status == ResidentDocStatus.rejected && d.reviewNote != null)
        'Reason: ${d.reviewNote}',
      if (d.status == ResidentDocStatus.pending && d.submittedAt != null)
        'Sent ${formatDocDate(d.submittedAt!)}',
      if (d.status == ResidentDocStatus.verified &&
          d.reviewedAt != null &&
          d.validUntil == null)
        'Verified ${formatDocDate(d.reviewedAt!)}',
      if (!d.hasFiles) 'Files deleted',
    ];

    return Opacity(
      opacity: dim ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: p.cardMuted,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(iconForDocType(d.type), size: 22, color: p.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              d.type.label,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: p.textPrimary,
                              ),
                            ),
                            DocChip(d.status.label, statusColor(p, d.status)),
                            if (expiry == DocumentExpiry.expired)
                              DocChip('Expired', p.danger)
                            else if (expiry == DocumentExpiry.expiringSoon)
                              DocChip('Ending soon', p.warning),
                          ],
                        ),
                        for (final l in lines)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              l,
                              style: TextStyle(
                                fontSize: 12,
                                color: p.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (onWithdraw != null)
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      onSelected: (_) => onWithdraw!(),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'withdraw',
                          child: Text('Withdraw'),
                        ),
                      ],
                    )
                  else if (onOpen != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 2),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: p.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
