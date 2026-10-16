// Tekst planu PWHT do udostępnienia (komunikator, e-mail) i wiersze do PDF.
// Czysty Dart — testowalny bez Fluttera.

import 'pwht_plan.dart';

/// Jeden wiersz planu: etykieta + wartość.
class PwhtPlanLine {
  const PwhtPlanLine(this.label, this.value);
  final String label;
  final String value;
}

String _num(double v, {int decimals = 1}) {
  final s = v.toStringAsFixed(decimals);
  // „25.0” → „25”, „25.40” zostaje przy podanej liczbie miejsc.
  if (decimals > 0 && s.endsWith('.${'0' * decimals}')) {
    return s.substring(0, s.length - decimals - 1);
  }
  return s;
}

String _tr(bool en, String pl, String eng) => en ? eng : pl;

/// Werdykt słownie.
String pwhtVerdictText(PwhtPlan plan, {required bool english}) {
  final ex = plan.entry.exemption;
  final max = ex?.maxThicknessMm;
  final limit = max == null ? '' : _num(max);
  // „(grubość ≤ 16 mm)” albo nic, gdy zwolnienie obejmuje każdą grubość.
  final within = max == null
      ? ''
      : _tr(english, ' (grubość ≤ $limit mm)', ' (thickness ≤ $limit mm)');
  switch (plan.verdict) {
    case PwhtVerdict.required:
      if (ex == null) {
        return _tr(english, 'PWHT wymagane — tabela nie przewiduje zwolnienia',
            'PWHT required — the table gives no exemption');
      }
      return _tr(english, 'PWHT wymagane — grubość > $limit mm',
          'PWHT required — thickness > $limit mm');
    case PwhtVerdict.exemptIfConditionsMet:
      return _tr(
          english,
          'PWHT niewymagane tylko przy spełnieniu warunków zwolnienia$within',
          'PWHT not required only if the exemption conditions are met$within');
    case PwhtVerdict.exempt:
      return _tr(
          english, 'PWHT niewymagane$within', 'PWHT not required$within');
    case PwhtVerdict.notRequiredByTable:
      return _tr(
          english,
          'Tabela normy nie wymaga PWHT dla tej grupy (chyba że wymaga go '
              'WPS / specyfikacja)',
          'The code table does not require PWHT for this group (unless the '
              'WPS / specification does)');
  }
}

/// Wiersze planu w kolejności druku.
List<PwhtPlanLine> pwhtPlanLines(PwhtPlan plan, {required bool english}) {
  final en = english;
  final info = pwhtMaterialInfo(plan.input.material);
  final entry = plan.entry;
  final lines = <PwhtPlanLine>[
    PwhtPlanLine(_tr(en, 'Norma', 'Code'), entry.source),
    PwhtPlanLine(
      _tr(en, 'Materiał', 'Material'),
      '${info.pNo} (${en ? info.alloyEn : info.alloyPl}) · '
      'ISO 15608 ${_tr(en, 'gr.', 'gr.')} ${info.isoGroup} · '
      '${info.grades}',
    ),
    PwhtPlanLine(
      _tr(en, 'Grubość kontrolna', 'Control thickness'),
      '${_num(plan.input.thicknessMm)} mm',
    ),
    if (plan.input.outsideDiameterMm != null)
      PwhtPlanLine(_tr(en, 'Średnica zewnętrzna', 'Outside diameter'),
          '${_num(plan.input.outsideDiameterMm!)} mm'),
    if (plan.input.weldWidthMm != null)
      PwhtPlanLine(_tr(en, 'Szerokość spoiny', 'Weld width'),
          '${_num(plan.input.weldWidthMm!)} mm'),
    PwhtPlanLine('PWHT', pwhtVerdictText(plan, english: en)),
  ];

  if (plan.verdict == PwhtVerdict.exemptIfConditionsMet) {
    final ex = entry.exemption!;
    for (final c in ex.conditionsFor(plan.input.thicknessMm)) {
      lines.add(PwhtPlanLine(
          _tr(en, 'Warunek zwolnienia', 'Exemption condition'),
          en ? c.text.en : c.text.pl));
    }
    lines.add(PwhtPlanLine(
        _tr(en, 'Źródło zwolnienia', 'Exemption source'), ex.source));
  }

  final range = entry.holdRange;
  if (range != null) {
    lines.add(PwhtPlanLine(
      _tr(en, 'Temperatura wytrzymania', 'Holding temperature'),
      '${range.minC}–${range.maxC} °C (${range.minF}–${range.maxF} °F)'
      '${plan.holdTempC == null ? '' : _tr(en, ' · w planie ${plan.holdTempC} °C', ' · planned ${plan.holdTempC} °C')}',
    ));
  }
  final hold = plan.holdMinutes;
  final rule = entry.holdTime;
  if (hold != null && rule != null) {
    lines.add(PwhtPlanLine(
      _tr(en, 'Min. czas wytrzymania', 'Min. holding time'),
      '${formatPwhtDuration(hold / 60.0)} '
      '(${en ? rule.formula.en : rule.formula.pl})',
    ));
  }
  final rr = plan.rateRule;
  if (rr != null && plan.heatingRateCPerH != null) {
    lines.add(PwhtPlanLine(
      _tr(en, 'Nagrzewanie powyżej ${rr.controlTempC} °C',
          'Heating above ${rr.controlTempC} °C'),
      _tr(en, 'maks. ${_num(plan.heatingRateCPerH!, decimals: 0)} °C/h',
          'max ${_num(plan.heatingRateCPerH!, decimals: 0)} °C/h'),
    ));
  }
  if (rr != null && plan.coolingRateCPerH != null) {
    lines.add(PwhtPlanLine(
      _tr(en, 'Chłodzenie powyżej ${rr.controlTempC} °C',
          'Cooling above ${rr.controlTempC} °C'),
      _tr(
          en,
          'maks. ${_num(plan.coolingRateCPerH!, decimals: 0)} °C/h; '
              'poniżej ${rr.controlTempC} °C — ${rr.belowControlPl}',
          'max ${_num(plan.coolingRateCPerH!, decimals: 0)} °C/h; '
              'below ${rr.controlTempC} °C — ${rr.belowControlEn}'),
    ));
  }
  if (rr != null) {
    lines.add(PwhtPlanLine(
      _tr(en, 'Źródło szybkości', 'Rate source'),
      '${rr.source} — ${en ? rr.noteEn : rr.notePl}',
    ));
  }
  final cycle = plan.cycle;
  if (cycle != null) {
    lines.add(PwhtPlanLine(
      _tr(en, 'Czas cyklu (część kontrolowana)',
          'Cycle time (controlled part)'),
      _tr(
          en,
          '${formatPwhtDuration(cycle.totalHours)} = nagrzewanie '
              '${formatPwhtDuration(cycle.rampUpHours)} + wytrzymanie '
              '${formatPwhtDuration(cycle.holdHours)} + chłodzenie '
              '${formatPwhtDuration(cycle.rampDownHours)}',
          '${formatPwhtDuration(cycle.totalHours)} = heating '
              '${formatPwhtDuration(cycle.rampUpHours)} + hold '
              '${formatPwhtDuration(cycle.holdHours)} + cooling '
              '${formatPwhtDuration(cycle.rampDownHours)}'),
    ));
  }
  final soak = plan.soakBandMm;
  if (soak != null) {
    final rule = soakBandRuleFor(plan.input.code);
    lines.add(PwhtPlanLine(
      _tr(en, 'Min. szerokość pasma wytrzymania (grzanie miejscowe)',
          'Min. soak band width (local heating)'),
      '${_num(soak)} mm = ${_num(soak / 2)} mm '
      '${_tr(en, 'w każdą stronę od osi spoiny', 'each side of the weld centreline')}'
      '${rule == null ? '' : ' — ${en ? rule.formula.en : rule.formula.pl} (${rule.source})'}',
    ));
  }
  final zones = plan.controlZones;
  if (zones != null) {
    lines.add(PwhtPlanLine(
      _tr(en, 'Strefy regulacji (rura pozioma)',
          'Control zones (horizontal pipe)'),
      zones.zones == null
          ? _tr(
              en,
              '${zones.npsRange}: norma nie podaje jednej liczby — wg '
                  'rozstawu grzałek i procedury (${zones.source})',
              '${zones.npsRange}: no single number given — per heater '
                  'layout and the procedure (${zones.source})')
          : _tr(
              en,
              '${zones.zones} — ${zones.npsRange}; liczba i miejsca termopar '
                  'wg rysunku normy (${zones.source}), zalecenie',
              '${zones.zones} — ${zones.npsRange}; thermocouple number and '
                  'locations per the figure (${zones.source}), recommended'),
    ));
  }
  for (final n in entry.notes) {
    lines.add(PwhtPlanLine(_tr(en, 'Uwaga', 'Note'), en ? n.en : n.pl));
  }
  return lines;
}

/// Zastrzeżenie — drukowane w każdym planie.
String pwhtDisclaimer({required bool english}) => _tr(
    english,
    'Wiążące parametry PWHT podaje WPS / procedura PWHT i specyfikacja '
        'projektu. Aplikacja pokazuje wartości z tabeli normy — sprawdź '
        'wydanie normy wskazane w specyfikacji.',
    'Binding PWHT parameters are set by the WPS / PWHT procedure and the '
        'project specification. The app shows values from the code table — '
        'check the code edition named in the specification.');

/// Pełny tekst planu do `Share.share`.
String pwhtPlanText(PwhtPlan plan, {required bool english}) {
  final b = StringBuffer()
    ..writeln(_tr(english, 'Plan PWHT — Fitter Welder Pro',
        'PWHT plan — Fitter Welder Pro'));
  for (final l in pwhtPlanLines(plan, english: english)) {
    b.writeln('${l.label}: ${l.value}');
  }
  b
    ..writeln()
    ..write(pwhtDisclaimer(english: english));
  return b.toString();
}
