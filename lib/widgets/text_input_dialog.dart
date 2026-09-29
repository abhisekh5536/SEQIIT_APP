import 'package:flutter/material.dart';

/// Asks for one line (or a few lines) of text in a dialog.
///
/// Returns the trimmed text, or null if the user cancelled.
///
/// Why this exists: callers used to create a [TextEditingController],
/// `await showDialog(...)`, then dispose the controller. That future
/// completes when the dialog is *popped* — at the start of its closing
/// animation — while the TextField is still on screen and rebuilding as the
/// keyboard goes down and focus moves. It then touched the disposed
/// controller, and the half torn-down tree failed with
/// `'_dependents.isEmpty': is not true` (a red screen in debug, grey in
/// release). Here the controller belongs to the dialog's own State, whose
/// dispose() runs only after the route has finished closing.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? label,
  String? hint,
  String initialText = '',
  String confirmLabel = 'Save',
  Color? confirmColor,
  int maxLines = 1,
  TextCapitalization textCapitalization = TextCapitalization.sentences,

  /// When set, an empty answer is refused with this message instead of
  /// being returned.
  String? requiredMessage,

  /// Extra check on the trimmed answer; return a message to refuse it.
  String? Function(String value)? validator,

  /// Off for values the keyboard must not learn (PAN, ID numbers).
  bool enableSuggestions = true,
  bool autocorrect = true,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextInputDialog(
      title: title,
      message: message,
      label: label,
      hint: hint,
      initialText: initialText,
      confirmLabel: confirmLabel,
      confirmColor: confirmColor,
      maxLines: maxLines,
      textCapitalization: textCapitalization,
      requiredMessage: requiredMessage,
      validator: validator,
      enableSuggestions: enableSuggestions,
      autocorrect: autocorrect,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  final String title;
  final String? message;
  final String? label;
  final String? hint;
  final String initialText;
  final String confirmLabel;
  final Color? confirmColor;
  final int maxLines;
  final TextCapitalization textCapitalization;
  final String? requiredMessage;
  final String? Function(String value)? validator;
  final bool enableSuggestions;
  final bool autocorrect;

  const _TextInputDialog({
    required this.title,
    this.message,
    this.label,
    this.hint,
    required this.initialText,
    required this.confirmLabel,
    this.confirmColor,
    required this.maxLines,
    required this.textCapitalization,
    this.requiredMessage,
    this.validator,
    this.enableSuggestions = true,
    this.autocorrect = true,
  });

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) ...[
              Text(widget.message!, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _controller,
              autofocus: true,
              maxLines: widget.maxLines,
              textCapitalization: widget.textCapitalization,
              textInputAction: widget.maxLines == 1
                  ? TextInputAction.done
                  : TextInputAction.newline,
              onFieldSubmitted: widget.maxLines == 1 ? (_) => _submit() : null,
              enableSuggestions: widget.enableSuggestions,
              autocorrect: widget.autocorrect,
              validator: (v) {
                final text = (v ?? '').trim();
                if (widget.requiredMessage != null && text.isEmpty) {
                  return widget.requiredMessage;
                }
                return widget.validator?.call(text);
              },
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hint,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: widget.confirmColor == null
              ? null
              : FilledButton.styleFrom(backgroundColor: widget.confirmColor),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
