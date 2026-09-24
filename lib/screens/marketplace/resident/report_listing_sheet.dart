import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/marketplace_models.dart';
import '../../../services/marketplace_service.dart';
import '../../../theme/app_theme.dart';
import '../widgets/marketplace_widgets.dart';

/// Reason picker for reporting a listing. Resolves to true once filed.
class ReportListingSheet extends StatefulWidget {
  final String listingId;
  final String listingTitle;

  const ReportListingSheet({
    super.key,
    required this.listingId,
    required this.listingTitle,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String listingId,
    required String listingTitle,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ReportListingSheet(
        listingId: listingId,
        listingTitle: listingTitle,
      ),
    );
  }

  @override
  State<ReportListingSheet> createState() => _ReportListingSheetState();
}

class _ReportListingSheetState extends State<ReportListingSheet> {
  final _detailsController = TextEditingController();
  ReportReason? _reason;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null) {
      setState(() => _error = 'Pick a reason');
      return;
    }
    if (_reason == ReportReason.other &&
        _detailsController.text.trim().isEmpty) {
      setState(() => _error = 'Add a line so the office knows what is wrong');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    HapticFeedback.mediumImpact();
    try {
      final hidden = await MarketplaceService.instance.reportListing(
        listingId: widget.listingId,
        reason: _reason!,
        details: _detailsController.text,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(SnackBar(
        content: Text(
          hidden
              ? 'Thanks — the listing is hidden until the office reviews it'
              : 'Thanks — the society office will review this listing',
        ),
      ));
    } on MarketplaceException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetHeader(
              title: 'Report listing',
              subtitle:
                  '"${widget.listingTitle}" · the seller will not see who reported it',
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioGroup<ReportReason>(
                    groupValue: _reason,
                    onChanged: (v) => setState(() {
                      _reason = v;
                      _error = null;
                    }),
                    child: Column(
                      children: [
                        for (final r in ReportReason.values)
                          RadioListTile<ReportReason>(
                            value: r,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(
                              r.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              r.hint,
                              style: TextStyle(
                                color: p.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _detailsController,
                    maxLength: 500,
                    maxLines: 3,
                    minLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'Anything the office should know (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_error != null) FormError(_error!),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.danger,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Submit report'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
