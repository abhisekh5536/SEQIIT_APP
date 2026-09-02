import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../models/visitor_models.dart';
import '../../../theme/app_theme.dart';

/// Compact visitor list card used in both resident and admin screens.
class VisitorCard extends StatelessWidget {
  final VisitorRecord visitor;
  final VoidCallback? onTap;

  const VisitorCard({super.key, required this.visitor, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: visitor.isPending
                ? p.warning.withValues(alpha: 0.5)
                : p.hairline,
            width: visitor.isPending ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: p.shadow.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Photo / Avatar
            _buildAvatar(p),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          visitor.visitorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      VisitorStatusBadge(status: visitor.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        visitor.category.icon,
                        size: 13,
                        color: visitor.category.color,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (visitor.isPreApproved &&
                          visitor.approvalCode != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: p.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '#${visitor.approvalCode}',
                            style: TextStyle(
                              color: p.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        visitor.timeAgo,
                        style: TextStyle(
                          color: p.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      if (visitor.flatNumber != null)
                        Text(
                          visitor.flatDisplay,
                          style: TextStyle(
                            color: p.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _subtitle {
    final parts = <String>[visitor.category.label];
    if (visitor.companyOrContext != null &&
        visitor.companyOrContext!.isNotEmpty) {
      parts.add(visitor.companyOrContext!);
    }
    if (visitor.isGateRequest) {
      parts.add('Gate Entry');
    }
    return parts.join(' · ');
  }

  Widget _buildAvatar(AppPaletteData p) {
    if (visitor.visitorPhotoUrl != null &&
        visitor.visitorPhotoUrl!.isNotEmpty) {
      final url = visitor.visitorPhotoUrl!;
      if (url.startsWith('data:image')) {
        try {
          final comma = url.indexOf(',');
          final b64 = comma != -1 ? url.substring(comma + 1) : url;
          final bytes = base64Decode(b64);
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(
              bytes,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _defaultAvatar(p),
            ),
          );
        } catch (_) {}
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          url,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultAvatar(p),
        ),
      );
    }
    return _defaultAvatar(p);
  }

  Widget _defaultAvatar(AppPaletteData p) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: visitor.category.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        visitor.category.icon,
        color: visitor.category.color,
        size: 24,
      ),
    );
  }
}

/// Colored status chip widget.
class VisitorStatusBadge extends StatelessWidget {
  final VisitorStatus status;
  final bool compact;

  const VisitorStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) ...[
            Icon(status.icon, size: 11, color: status.foreground),
            const SizedBox(width: 3),
          ],
          Text(
            status.label,
            style: TextStyle(
              color: status.foreground,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
