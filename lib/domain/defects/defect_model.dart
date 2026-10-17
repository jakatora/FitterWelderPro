// Wady spoin: przyczyny i naprawa — model danych (czysty Dart, bez Fluttera).
//
// Dane (const) są w lib/data/weld_defects.dart, wybór przyczyn dla procesu /
// materiału / pozycji i wyszukiwarka w lib/domain/defects/defect_advice.dart.
//
// Wada ([WeldDefect]) to praktyczna pozycja („Podtopienie”), która zbiera
// jeden lub kilka numerów PN-EN ISO 6520-1 z oficjalnymi nazwami
// ([Iso6520Ref]). Każda przyczyna ([DefectCause]) dotyczy wybranych procesów
// (ISO 4063), opcjonalnie materiałów i pozycji (ISO 6947), ma konkretne
// sprawdzenie i środek zaradczy oraz klucze źródeł ([kDefectSources]).

/// Tekst w dwóch językach. Liczby w obu wersjach muszą być te same
/// (pilnuje tego test danych).
class Tx {
  final String pl;
  final String en;
  const Tx(this.pl, this.en);

  String of({required bool en}) => en ? this.en : pl;
}

/// Proces spawania wg ISO 4063 — tak, jak spawacz go wybiera na budowie.
enum DefectProcess {
  mma111(
    codes: ['111'],
    short: 'MMA',
    pl: 'Elektroda otulona',
    en: 'Covered electrode',
    materials: {DefectMaterial.carbon, DefectMaterial.stainless},
  ),
  mag135(
    codes: ['135', '138'],
    short: 'MAG',
    pl: 'Drut lity / proszkowy metaliczny',
    en: 'Solid / metal-cored wire',
    materials: {DefectMaterial.carbon, DefectMaterial.stainless},
  ),
  fcaw136(
    codes: ['136'],
    short: 'FCAW',
    pl: 'Drut proszkowy w osłonie gazu',
    en: 'Gas-shielded flux-cored wire',
    materials: {DefectMaterial.carbon, DefectMaterial.stainless},
  ),
  fcaw114(
    codes: ['114'],
    short: 'FCAW-S',
    pl: 'Drut proszkowy samoosłonowy',
    en: 'Self-shielded flux-cored wire',
    materials: {DefectMaterial.carbon},
  ),
  tig141(
    codes: ['141'],
    short: 'TIG',
    pl: 'Elektroda wolframowa',
    en: 'Tungsten electrode',
    materials: {
      DefectMaterial.carbon,
      DefectMaterial.stainless,
      DefectMaterial.aluminium,
    },
  ),
  saw121(
    codes: ['121'],
    short: 'SAW',
    pl: 'Łuk kryty',
    en: 'Submerged arc',
    materials: {DefectMaterial.carbon, DefectMaterial.stainless},
  ),
  mig131(
    codes: ['131'],
    short: 'MIG Al',
    pl: 'MIG aluminium',
    en: 'MIG aluminium',
    materials: {DefectMaterial.aluminium},
  );

  const DefectProcess({
    required this.codes,
    required this.short,
    required this.pl,
    required this.en,
    required this.materials,
  });

  /// Numery ISO 4063 (MAG: 135 i 138 razem).
  final List<String> codes;

  /// Skrót warsztatowy (MMA, MAG, TIG…).
  final String short;
  final String pl;
  final String en;

  /// Materiały, które tym procesem spawa się w praktyce (wybór materiału na
  /// ekranie pokazuje tylko te).
  final Set<DefectMaterial> materials;

  /// „135/138 MAG”.
  String get label => '${codes.join('/')} $short';

  /// Proces w osłonie gazu z butli (przepływ, przeciąg, nieszczelności).
  bool get usesShieldingGas =>
      this == mag135 || this == fcaw136 || this == tig141 || this == mig131;
}

/// Materiał (opcjonalny filtr przyczyn).
enum DefectMaterial {
  carbon('Stal węglowa', 'Carbon steel'),
  stainless('Stal nierdzewna', 'Stainless steel'),
  aluminium('Aluminium', 'Aluminium');

  const DefectMaterial(this.pl, this.en);
  final String pl;
  final String en;
}

/// Pozycja spawania wg ISO 6947 (opcjonalny filtr przyczyn). Rury
/// nachylone 45° (H-L045 / J-L045) zachowują się jak PH / PJ.
enum DefectPosition {
  pa('PA', 'podolna', 'flat'),
  pb('PB', 'naboczna', 'horizontal vertical'),
  pc('PC', 'naścienna', 'horizontal'),
  pd('PD', 'okapowa', 'horizontal overhead'),
  pe('PE', 'pułapowa', 'overhead'),
  pf('PF', 'pionowa z dołu do góry', 'vertical up'),
  pg('PG', 'pionowa z góry na dół', 'vertical down'),
  pipeUp('PH / H-L045', 'rura stała, w górę', 'fixed pipe, upwards'),
  pipeDown('PJ / J-L045', 'rura stała, w dół', 'fixed pipe, downwards');

  const DefectPosition(this.code, this.pl, this.en);
  final String code;
  final String pl;
  final String en;
}

/// Grupy niezgodności PN-EN ISO 6520-1 (pierwsza cyfra numeru). Nazwy jak
/// numery 100 / 200 / 300 / 400 / 600 w tabeli PL/EN wikiweld.pl; grupa 5 —
/// nagłówek grupy („…dotyczące kształtu i wymiarów”).
enum DefectGroup {
  cracks(1, 'Pęknięcia', 'Cracks'),
  cavities(2, 'Pustki', 'Cavities'),
  inclusions(3, 'Wtrącenia stałe', 'Solid inclusions'),
  fusion(4, 'Przyklejenie i brak przetopu', 'Lack of fusion and penetration'),
  shape(5, 'Niezgodności kształtu i wymiarów',
      'Imperfect shape and dimensions'),
  misc(6, 'Niezgodności spawalnicze różne', 'Miscellaneous imperfections');

  const DefectGroup(this.digit, this.pl, this.en);

  /// Pierwsza cyfra numerów ISO 6520-1 tej grupy.
  final int digit;
  final String pl;
  final String en;
}

/// Numer PN-EN ISO 6520-1 z oficjalną nazwą PL / EN.
class Iso6520Ref {
  final int code;
  final String pl;
  final String en;
  const Iso6520Ref(this.code, this.pl, this.en);

  /// Grupa = pierwsza cyfra numeru (100 → 1, 5011 → 5).
  int get groupDigit => int.parse(code.toString()[0]);
}

/// Jedna przyczyna wady: co jest nie tak, jak to sprawdzić i co zmienić.
class DefectCause {
  /// Unikalny w obrębie wady.
  final String id;

  /// Procesy, których przyczyna dotyczy.
  final Set<DefectProcess> processes;

  /// Pusty = każdy materiał.
  final Set<DefectMaterial> materials;

  /// Pusty = każda pozycja. Niepusty = przyczyna typowa dla tych pozycji —
  /// przy wybranej pasującej pozycji idzie na początek listy.
  final Set<DefectPosition> positions;

  /// Kolejność sprawdzania: 1 = najczęstsza / najszybsza do sprawdzenia.
  final int rank;

  final Tx cause;
  final Tx check;
  final Tx fix;

  /// Klucze [kDefectSources] (lib/data/weld_defects.dart).
  final List<String> sources;

  const DefectCause({
    required this.id,
    required this.processes,
    required this.rank,
    required this.cause,
    required this.check,
    required this.fix,
    required this.sources,
    this.materials = const {},
    this.positions = const {},
  });

  bool appliesTo(DefectProcess p) => processes.contains(p);
}

/// Krok naprawy lub punkt listy „przed następnym ściegiem”, opcjonalnie
/// tylko dla wybranych procesów / materiałów.
class DefectStep {
  final String id;
  final Tx text;

  /// Pusty = każdy proces.
  final Set<DefectProcess> processes;

  /// Pusty = każdy materiał.
  final Set<DefectMaterial> materials;

  const DefectStep(
    this.id,
    this.text, {
    this.processes = const {},
    this.materials = const {},
  });
}

/// Źródło (poradnik producenta, TWI Job Knowledge, norma w cytacie wtórnym).
class DefectSource {
  /// Krótka etykieta przy przyczynie („TWI”, „Lincoln”).
  final String short;
  final String title;
  final String url;
  const DefectSource(this.short, this.title, this.url);
}

/// Wada spoiny (praktyczna pozycja z numerami ISO 6520-1).
class WeldDefect {
  final String id;
  final DefectGroup group;
  final List<Iso6520Ref> refs;

  /// Nazwa na liście (zwykle oficjalna nazwa pierwszego numeru albo nazwa
  /// zbiorcza, np. „Porowatość”).
  final Tx title;

  /// Jak wada wygląda / gdzie ją widać.
  final Tx looks;

  /// Procesy, w których wada występuje i dla których są przyczyny.
  final Set<DefectProcess> processes;

  /// Materiały, których wada dotyczy (pusty = każdy materiał procesu),
  /// np. pęknięcia wodorowe — stal węglowa i niskostopowa.
  final Set<DefectMaterial> materials;

  /// Dodatkowe słowa do wyszukiwania (potoczne, PL i EN).
  final List<String> keywords;

  final List<DefectCause> causes;

  /// Jak naprawić — kroki w kolejności.
  final List<DefectStep> repair;

  /// Kiedy spoina idzie do wycięcia zamiast miejscowej naprawy.
  final Tx cutOut;

  /// BHP przy naprawie.
  final List<Tx> safety;

  /// „Przed następnym ściegiem” — 3–6 punktów po filtrze procesu.
  final List<DefectStep> checklist;

  /// Źródła części „Naprawa”.
  final List<String> repairSources;

  const WeldDefect({
    required this.id,
    required this.group,
    required this.refs,
    required this.title,
    required this.looks,
    required this.processes,
    required this.causes,
    required this.repair,
    required this.cutOut,
    required this.safety,
    required this.checklist,
    required this.repairSources,
    this.materials = const {},
    this.keywords = const [],
  });

  List<int> get codes => [for (final r in refs) r.code];

  /// Materiały do wyboru dla procesu [p]: część wspólna materiałów procesu
  /// i wady, w kolejności [DefectMaterial.values].
  List<DefectMaterial> materialsFor(DefectProcess p) => [
        for (final m in DefectMaterial.values)
          if (p.materials.contains(m) &&
              (materials.isEmpty || materials.contains(m)))
            m
      ];

  /// „5011, 5012, 5013”.
  String get codesLabel => codes.join(', ');
}
