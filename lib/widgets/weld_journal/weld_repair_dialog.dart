/// Recording a repair (R1, R2, …) of a weld.
library;

import 'package:flutter/material.dart';

import '../../domain/weld_journal/weld_dates.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';

/// Result of [showWeldRepairDialog].
class WeldRepairInput {
  final String date;
  final String reason;
  const WeldRepairInput(this.date, this.reason);
}

/// Asks for the repair date and cause. [nextLabel] is `R1`, `R2`, …
/// Returns null when cancelled.
Future<WeldRepairInput?> showWeldRepairDialog(
  BuildContext context, {
  required String weldNo,
  required String nextLabel,
  required int repairsSoFar,
}) =>
    showDialog<WeldRepairInput>(
      context: context,
      builder: (_) => _WeldRepairDialog(
        weldNo: weldNo,
        nextLabel: nextLabel,
        repairsSoFar: repairsSoFar,
      ),
    );

class _WeldRepairDialog extends StatefulWidget {
  final String weldNo;
  final String nextLabel;
  final int repairsSoFar;
  const _WeldRepairDialog({
    required this.weldNo,
    required this.nextLabel,
    required this.repairsSoFar,
  });

  @override
  State<_WeldRepairDialog> createState() => _WeldRepairDialogState();
}

class _WeldRepairDialogState extends State<_WeldRepairDialog> {
  final _date = TextEditingController(text: isoDate(DateTime.now()));
  final _reason = TextEditingController();
  String? _dateError;

  @override
  void dispose() {
    _date.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final d = normalizeWeldDate(_date.text);
    if (d == null) {
      setState(() => _dateError = context.tr(
          pl: 'Data RRRR-MM-DD lub DD.MM.RRRR',
          en: 'Date YYYY-MM-DD or DD.MM.YYYY'));
      return;
    }
    Navigator.pop(context, WeldRepairInput(d, _reason.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr(
        pl: 'Naprawa ${widget.nextLabel} — spoina ${widget.weldNo}',
        en: 'Repair ${widget.nextLabel} — weld ${widget.weldNo}',
      )),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr(
                pl: 'Poprzedni status i wyniki NDT zostaną zapisane w '
                    'naprawie ${widget.nextLabel}. Spoina wróci do statusu '
                    '„Oczekuje” i do ponownego badania tymi samymi metodami. '
                    'Odbiór inspektora, nr wykresu PWHT i twardość zostaną '
                    'wyczyszczone (stare wartości zostają w naprawie i w '
                    'historii spoiny).',
                en: 'The previous status and NDT results are kept in repair '
                    '${widget.nextLabel}. The weld goes back to "Pending" and '
                    'to re-examination by the same methods. The inspector '
                    'acceptance, PWHT chart no. and hardness are cleared (the '
                    'old values stay in the repair and the weld history).',
              ),
              style: const TextStyle(fontSize: 13, color: kTextSec),
            ),
            if (widget.repairsSoFar >= 2) ...[
              const SizedBox(height: 8),
              Text(
                context.tr(
                  pl: 'Uwaga: to już ${widget.repairsSoFar + 1}. naprawa. '
                      'Większość specyfikacji dopuszcza najwyżej dwie naprawy '
                      'w tym samym miejscu — sprawdź wymagania projektu.',
                  en: 'Note: this is repair no. ${widget.repairsSoFar + 1}. '
                      'Most specifications allow at most two repairs in the '
                      'same location — check the project requirements.',
                ),
                style: const TextStyle(fontSize: 12, color: kWarn),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _date,
              decoration: InputDecoration(
                labelText: context.tr(pl: 'Data naprawy', en: 'Repair date'),
                errorText: _dateError,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reason,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.tr(
                    pl: 'Przyczyna / wada', en: 'Cause / defect'),
                hintText: context.tr(
                    pl: 'np. porowatość w graniu, brak przetopu',
                    en: 'e.g. root porosity, lack of penetration'),
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
              minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
          onPressed: _submit,
          child: Text(context.tr(
              pl: 'Zapisz ${widget.nextLabel}',
              en: 'Save ${widget.nextLabel}')),
        ),
      ],
    );
  }
}
