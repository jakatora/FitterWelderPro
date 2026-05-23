import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'haptic.dart';

/// Copies [value] to the clipboard, vibrates and shows a brief snackbar.
/// Used on calculator result cards so a fitter can paste a number straight
/// into a chat/SMS to a foreman without re-typing.
Future<void> copyToClipboard(
  BuildContext context,
  String value, {
  String? label,
}) async {
  await Clipboard.setData(ClipboardData(text: value));
  await Haptic.copied();
  if (!context.mounted) return;
  final msg = label == null ? 'Skopiowano: $value' : '$label: $value';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 900),
      ),
    );
}

/// Wraps any child in an InkWell that copies [value] on long-press.
/// Adds a subtle ripple so the fitter sees the touch landed even in sunlight.
class CopyOnLongPress extends StatelessWidget {
  final String value;
  final String? label;
  final Widget child;

  const CopyOnLongPress({
    super.key,
    required this.value,
    required this.child,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onLongPress: () => copyToClipboard(context, value, label: label),
      borderRadius: BorderRadius.circular(10),
      child: child,
    );
  }
}
