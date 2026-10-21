import 'filler_catalog.dart';
import 'filler_selector.dart';

/// Uses the same recommendation and process variants as the selection screen.
String fillerReference(BaseMaterial a, BaseMaterial b, FillerProcess process,
    {required bool en}) {
  final r = selectFiller(a, b);
  final f = r.forProcess(process);
  final lines = <String>[
    '${a.label.of(english: en)} + ${b.label.of(english: en)} · ${process.label}',
    en
        ? 'Typical selection; the WPS and project specification govern.'
        : 'Typowy dobór; wiążące są WPS i specyfikacja projektu.',
    r.summary.of(english: en),
    if (r.verdict == FillerVerdict.typical && f == null)
      en
          ? 'No typical process-specific consumable in the app; consult the WPS.'
          : 'Brak typowego spoiwa dla tego procesu w aplikacji; dobór wg WPS.',
    if (f != null) ...[
      r.family!.name.of(english: en),
      for (final c in f.consumables)
        '${c.isoStandard}: ${c.isoDesignation}; ${c.awsStandard}: ${c.awsDesignation}${c.use == null ? "" : " — ${c.use!.of(english: en)}"}',
      if (f.shielding.isNotEmpty)
        '${en ? "Shielding gas" : "Gaz osłonowy"} (EN ISO 14175): ${f.shielding.map((g) => '${g.code} ${g.description.of(english: en)}').join('; ')}',
      if (f.note != null) f.note!.of(english: en),
      for (final n in r.family!.notes) n.of(english: en),
    ],
    if (r.verdict != FillerVerdict.notArcWeldable) ...[
      '${en ? "Root backing" : "Formowanie grani"}: ${switch (r.backing) {
        BackingNeed.notNeeded =>
          en ? 'not normally needed' : 'zwykle niepotrzebne',
        BackingNeed.recommended => en ? 'recommended' : 'zalecane',
        BackingNeed.required => en ? 'required' : 'wymagane',
      }}',
      if (r.backingGases.isNotEmpty)
        '${en ? "Backing gases" : "Gazy formujące"}: ${r.backingGases.map((g) => '${g.code} ${g.description.of(english: en)}').join('; ')}',
      for (final w in r.warnings) w.of(english: en),
    ],
  ];
  return lines.join('\n');
}
