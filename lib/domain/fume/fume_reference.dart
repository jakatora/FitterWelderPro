import 'fume_hazards.dart';
import 'fume_sources.dart';

String _number(double n, bool en) {
  final v = n
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  return en ? v : v.replaceAll('.', ',');
}

String fumeNdsText(FumeAgent a, {required bool en}) {
  final list = a.nds;
  if (list == null) {
    return en
        ? 'Polish OEL (NDS): check the current NDS list.'
        : 'NDS: sprawdź aktualny wykaz NDS.';
  }
  final parts = <String>[];
  for (final v in list) {
    final inside = [
      if (v.fraction(en: en) != null) v.fraction(en: en)!,
      if (v.ndsch != null)
        '${en ? "STEL" : "NDSCh"} ${_number(v.ndsch!, en)} mg/m³',
    ];
    parts.add(
        '${_number(v.nds, en)} mg/m³${inside.isEmpty ? "" : " (${inside.join("; ")})"}');
  }
  final note = a.ndsNote(en: en);
  return '${en ? "Polish OEL (NDS)" : "NDS"}: ${parts.join(" · ")}${note == null ? "" : "; $note"}.';
}

String fumeOelReference(FumeAgent a, {required bool en}) => [
      a.title(en: en),
      en ? kFumeNdsLegalEn : kFumeNdsLegalPl,
      fumeNdsText(a, en: en),
      if (a.nds != null && a.nds!.every((v) => v.ndsch == null))
        en
            ? 'The app table does not provide an NDSCh/STEL value for this entry; this does not mean zero.'
            : 'Tabela aplikacji nie podaje NDSCh dla tego wpisu; to nie oznacza wartości zero.',
      if (a == FumeAgent.crVI) en ? kFumeCrViNoteEn : kFumeCrViNotePl,
      if (a == FumeAgent.cd) en ? kFumeCdNoteEn : kFumeCdNotePl,
      if (a == FumeAgent.pb) en ? kFumePbNoteEn : kFumePbNotePl,
      en
          ? 'This is a Polish reference limit, not an exposure measurement or a workplace safety assessment. Use the correct substance, fraction and averaging period.'
          : 'To polska wartość odniesienia, nie pomiar narażenia ani ocena bezpieczeństwa stanowiska. Dopasuj substancję, frakcję i okres uśredniania.',
    ].join('\n');
