import 'package:flutter/material.dart';
import '../i18n/app_language.dart';

/// Optional explanation: the quick calculation remains the primary action.
class CalculationGuide extends StatelessWidget {
  const CalculationGuide(
      {super.key,
      required this.inputs,
      required this.steps,
      required this.caution,
      required this.hasResult});

  final String inputs;
  final List<String> steps;
  final String caution;
  final bool hasResult;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(Icons.school_outlined, color: theme.colorScheme.primary),
        title: Text(context.tr(pl: 'Pokaż jak', en: 'Show how')),
        subtitle: Text(context.tr(
            pl: 'Dane, wzór i znaczenie wyniku',
            en: 'Inputs, formula and what the result means')),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(inputs, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          Text(
              hasResult
                  ? context.tr(pl: 'Twoje obliczenie', en: 'Your calculation')
                  : context.tr(pl: 'Przykład obliczenia', en: 'Worked example'),
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i + 1}.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary)),
                const SizedBox(width: 8),
                Expanded(
                    child: SelectableText(steps[i],
                        style: theme.textTheme.bodyMedium)),
              ]),
            ),
          const Divider(),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline,
                size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(caution, style: theme.textTheme.bodyMedium)),
          ]),
        ],
      ),
    );
  }
}

String guideNumber(double value) => value == value.truncateToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();
