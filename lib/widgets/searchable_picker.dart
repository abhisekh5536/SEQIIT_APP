import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One choice in a [showSearchablePicker] sheet.
class PickerOption<T> {
  final T value;
  final String label;
  final String? subtitle;

  /// Small pill on the right, e.g. 'Vacant'.
  final String? tag;

  const PickerOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.tag,
  });
}

/// Lowercased with punctuation/whitespace stripped, so "a3" / "a 003" /
/// "A-003" all line up when matching flat numbers.
String _normalise(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

bool _matches(PickerOption option, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final haystack = [option.label, option.subtitle, option.tag]
      .whereType<String>()
      .join(' ');
  if (haystack.toLowerCase().contains(q)) return true;
  final nq = _normalise(q);
  return nq.isNotEmpty && _normalise(haystack).contains(nq);
}

/// Bottom sheet with a search box over a long list of options (flats,
/// societies, …). Resolves to the chosen option, or null if dismissed.
Future<PickerOption<T>?> showSearchablePicker<T>({
  required BuildContext context,
  required String title,
  required List<PickerOption<T>> options,
  T? selected,
  String searchHint = 'Search…',
  String emptyText = 'No matches found',
  IconData icon = Icons.apartment_rounded,
}) {
  return showModalBottomSheet<PickerOption<T>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SearchablePickerSheet<T>(
      title: title,
      options: options,
      selected: selected,
      searchHint: searchHint,
      emptyText: emptyText,
      icon: icon,
    ),
  );
}

class _SearchablePickerSheet<T> extends StatefulWidget {
  final String title;
  final List<PickerOption<T>> options;
  final T? selected;
  final String searchHint;
  final String emptyText;
  final IconData icon;

  const _SearchablePickerSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.searchHint,
    required this.emptyText,
    required this.icon,
  });

  @override
  State<_SearchablePickerSheet<T>> createState() =>
      _SearchablePickerSheetState<T>();
}

class _SearchablePickerSheetState<T> extends State<_SearchablePickerSheet<T>> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final textTheme = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    final filtered =
        widget.options.where((o) => _matches(o, _query)).toList();

    // Shrinks with the keyboard so the search box and results stay visible.
    final height = math.min(
      media.size.height * 0.75,
      media.size.height - media.viewInsets.bottom - media.padding.top - 24,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: p.canvas,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: p.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 6),
              child: Row(
                children: [
                  Icon(widget.icon, size: 22, color: p.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '${filtered.length}/${widget.options.length}',
                    style: textTheme.labelSmall
                        ?.copyWith(color: p.textTertiary),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                onChanged: (q) => setState(() => _query = q),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 20, color: p.textTertiary),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                          icon: Icon(Icons.close_rounded,
                              size: 18, color: p.textTertiary),
                        ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        widget.emptyText,
                        style: TextStyle(color: p.textTertiary),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                          20, 4, 20, 20 + media.padding.bottom),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          Divider(color: p.hairline, height: 1),
                      itemBuilder: (ctx, i) {
                        final option = filtered[i];
                        final isSelected = widget.selected != null &&
                            option.value == widget.selected;
                        return ListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          title: Text(
                            option.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: isSelected ? p.primary : p.textPrimary,
                            ),
                          ),
                          subtitle: option.subtitle == null ||
                                  option.subtitle!.isEmpty
                              ? null
                              : Text(
                                  option.subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12, color: p.textTertiary),
                                ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (option.tag != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: p.warning.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    option.tag!,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: p.warning,
                                    ),
                                  ),
                                ),
                              if (isSelected) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.check_circle_rounded,
                                    color: p.primary, size: 20),
                              ],
                            ],
                          ),
                          onTap: () => Navigator.pop(context, option),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Form-field lookalike that opens [showSearchablePicker] on tap. Drop-in
/// replacement for a DropdownButtonFormField whose list can get long.
class SearchablePickerField<T> extends StatelessWidget {
  final List<PickerOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String sheetTitle;
  final String hintText;
  final String searchHint;
  final String emptyText;
  final IconData icon;
  final InputDecoration? decoration;

  const SearchablePickerField({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.sheetTitle,
    this.hintText = 'Choose',
    this.searchHint = 'Search…',
    this.emptyText = 'No matches found',
    this.icon = Icons.apartment_rounded,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    PickerOption<T>? selected;
    for (final o in options) {
      if (o.value == value) {
        selected = o;
        break;
      }
    }
    final enabled = options.isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: !enabled
          ? null
          : () async {
              FocusScope.of(context).unfocus();
              final picked = await showSearchablePicker<T>(
                context: context,
                title: sheetTitle,
                options: options,
                selected: value,
                searchHint: searchHint,
                emptyText: emptyText,
                icon: icon,
              );
              if (picked != null) onChanged(picked.value);
            },
      child: InputDecorator(
        isEmpty: selected == null,
        decoration: (decoration ?? const InputDecoration()).copyWith(
          hintText: hintText,
          enabled: enabled,
          suffixIcon: Icon(Icons.unfold_more_rounded,
              size: 20, color: p.textTertiary),
        ),
        child: selected == null
            ? null
            : Text(
                selected.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
      ),
    );
  }
}
