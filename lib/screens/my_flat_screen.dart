import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/db_models.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';

class MyFlatScreen extends StatefulWidget {
  const MyFlatScreen({super.key});

  @override
  State<MyFlatScreen> createState() => _MyFlatScreenState();
}

class _MyFlatScreenState extends State<MyFlatScreen> {
  Map<String, String> _blockNames = const {};
  bool _loadingBlocks = true;

  @override
  void initState() {
    super.initState();
    _loadBlockNames();
  }

  Future<void> _loadBlockNames() async {
    final session = AppSession.instance;
    final blockIds = session.myResidences
        .map((r) => session.flatOf(r)?.blockId)
        .whereType<String>()
        .toSet()
        .toList();
    if (blockIds.isEmpty) {
      if (mounted) setState(() => _loadingBlocks = false);
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('blocks')
          .select('id, name')
          .inFilter('id', blockIds);
      final map = <String, String>{};
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        map[row['id'] as String] = (row['name'] ?? '') as String;
      }
      if (mounted) {
        setState(() {
          _blockNames = map;
          _loadingBlocks = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingBlocks = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: AppSession.instance,
          builder: (context, _) {
            final residences = AppSession.instance.myResidences;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: p.card,
                        side: BorderSide(color: p.hairline),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'My Flat',
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    'Details registered by your society office',
                    style: textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 20),
                if (AppSession.instance.isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (residences.isEmpty)
                  _emptyState(context, p, textTheme)
                else
                  ...residences.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _residenceCard(context, p, textTheme, r),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _emptyState(
    BuildContext context,
    AppPaletteData p,
    TextTheme textTheme,
  ) {
    return Surface(
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: p.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.home_work_outlined,
                size: 34, color: p.primary),
          ),
          const SizedBox(height: 16),
          Text('No flat allotted yet',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 6),
          Text(
            'Your society office has not linked a flat to this account.\n'
            'Sign up with the email you gave to the office and your\n'
            'details will appear here automatically.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _residenceCard(
    BuildContext context,
    AppPaletteData p,
    TextTheme textTheme,
    ResidentRecord r,
  ) {
    final flat = AppSession.instance.flatOf(r);
    final blockName = flat == null
        ? null
        : (_loadingBlocks ? null : (_blockNames[flat.blockId] ?? '—'));
    final locationParts = [
      if (blockName != null && blockName != '—') blockName,
      if (flat != null) 'Floor ${flat.floorNumber}',
      if (flat != null && flat.type.isNotEmpty) flat.type,
    ];

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [p.heroStart, p.heroEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.apartment_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      flat?.flatNumber ?? 'Flat pending',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      locationParts.join(' · '),
                      style: textTheme.bodySmall?.copyWith(
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _badge(
                context,
                p,
                label: r.isOwner
                    ? 'Owner'
                    : r.isFamily
                        ? 'Family'
                        : 'Tenant',
                bg: r.isOwner
                    ? p.success.withValues(alpha: 0.14)
                    : r.isFamily
                        ? p.warning.withValues(alpha: 0.14)
                        : p.secondary.withValues(alpha: 0.22),
                fg: r.isOwner
                    ? p.success
                    : r.isFamily
                        ? p.warning
                        : p.onSecondary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: p.hairline),
          const SizedBox(height: 14),
          if (r.isPrimary) ...[
            _badge(
              context,
              p,
              label: 'Primary contact',
              bg: p.mint,
              fg: p.mintOn,
            ),
            const SizedBox(height: 14),
          ],
          _detailRow(context, p, Icons.person_outline_rounded, 'Name',
              r.fullName),
          _detailRow(context, p, Icons.mail_outline_rounded, 'Email', r.email),
          if ((r.phone ?? '').isNotEmpty)
            _detailRow(
                context, p, Icons.call_outlined, 'Phone', r.phone!),
          if ((r.agreementHolderName ?? '').isNotEmpty)
            _detailRow(context, p, Icons.history_edu_outlined,
                'Agreement holder', r.agreementHolderName!),
          if (r.agreementDate != null)
            _detailRow(
              context,
              p,
              Icons.event_available_outlined,
              'Agreement date',
              '${r.agreementDate!.day}/${r.agreementDate!.month}/${r.agreementDate!.year}',
            ),
          if ((r.aadharLast4 ?? '').isNotEmpty)
            _detailRow(
              context,
              p,
              Icons.badge_outlined,
              'Aadhar',
              '•••• ${r.aadharLast4}',
            ),
        ],
      ),
    );
  }

  Widget _badge(
    BuildContext context,
    AppPaletteData p, {
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  Widget _detailRow(
    BuildContext context,
    AppPaletteData p,
    IconData icon,
    String label,
    String value,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: p.textTertiary),
          const SizedBox(width: 10),
          SizedBox(
            width: 118,
            child: Text(label, style: textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
