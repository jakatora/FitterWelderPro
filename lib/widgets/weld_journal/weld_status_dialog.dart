/// The only way to change a weld's status from the list: pick the new status
/// explicitly, then confirm.
///
/// The status badge on the list used to cycle PENDING → OK → NOK on a single
/// tap, without a question. A welder in gloves brushing the badge "accepted"
/// a weld nobody had examined — and nothing recorded that it happened. Now a
/// tap opens this dialog; nothing changes until a DIFFERENT status is chosen
/// and "Zmień status" is pressed, and the DAO logs the change with the
/// welder's stamp.
library;

import 'package:flutter/material.dart';

import '../../domain/weld_journal/weld_entry.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import 'wj_ui.dart';

/// Returns the confirmed new status, or null when cancelled or unchanged.
Future<String?> showWeldStatusDialog(
  BuildContext context, {
  required String weldNo,
  required String current,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _WeldStatusDialog(weldNo: weldNo, current: current),
    );

class _WeldStatusDialog extends StatefulWidget {
  final String weldNo;
  final String current;
  const _WeldStatusDialog({required this.weldNo, required this.current});

  @override
  State<_WeldStatusDialog> createState() => _WeldStatusDialogState();
}

class _WeldStatusDialogState extends State<_WeldStatusDialog> {
  late String _picked = widget.current;

  @override
  Widget build(BuildContext context) {
    final changed = _picked != widget.current;
    return AlertDialog(
      title: Text(context.tr(
        pl: 'Status spoiny ${widget.weldNo}',
        en: 'Status of weld ${widget.weldNo}',
      )),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr(
                pl: 'Teraz: ${weldStatusLabel(context, widget.current)}. '
                    'Wybierz nowy status i potwierdź. Zmiana trafi do '
                    'historii spoiny z Twoim stemplem.',
                en: 'Now: ${weldStatusLabel(context, widget.current)}. '
                    'Pick the new status and confirm. The change is '
                    'recorded in the weld history with your stamp.',
              ),
              style: const TextStyle(fontSize: 13, color: kTextSec),
            ),
            const SizedBox(height: 12),
            for (final s in WeldStatus.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _StatusOption(
                  status: s,
                  selected: _picked == s,
                  isCurrent: widget.current == s,
                  onTap: () => setState(() => _picked = s),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(kMinTapTarget, kMinTapTarget),
            backgroundColor: weldStatusColor(_picked),
            foregroundColor: Colors.black,
          ),
          onPressed: changed ? () => Navigator.pop(context, _picked) : null,
          child: Text(context.tr(pl: 'Zmień status', en: 'Change status')),
        ),
      ],
    );
  }
}

class _StatusOption extends StatelessWidget {
  final String status;
  final bool selected;
  final bool isCurrent;
  final VoidCallback onTap;

  const _StatusOption({
    required this.status,
    required this.selected,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = weldStatusColor(status);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? c.withValues(alpha: 0.15) : kCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? c : kBorder, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? c : kTextMut,
              ),
              const SizedBox(width: 10),
              Icon(weldStatusIcon(status), color: c, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  weldStatusLabel(context, status),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: selected ? c : kText),
                ),
              ),
              if (isCurrent)
                Text(context.tr(pl: 'teraz', en: 'now'),
                    style: const TextStyle(fontSize: 11, color: kTextMut)),
            ],
          ),
        ),
      ),
    );
  }
}
