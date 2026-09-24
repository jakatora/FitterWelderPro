// Procesy spawania i rodzaje złączy — wspólny słownik rejestru uprawnień
// spawacza (ISO 9606-1 / ASME IX WPQ) i biblioteki WPS.
//
// Czysty Dart, bez Fluttera: z tego korzystają testy tabelaryczne kontroli
// zakresu, planer przypomnień i (przez API) dziennik spoin.
//
// DWA POZIOMY PORÓWNANIA PROCESU
//  • Numer wg EN ISO 4063 (111, 135, 141…) — gdy obie strony podają numer,
//    porównujemy numery. ISO 9606-1 §5.2: każdy proces kwalifikuje się osobno,
//    więc certyfikat na 141 nie obejmuje 142, choć oba to TIG.
//  • Rodzina procesu (TIG = GTAW, MAG = GMAW…) — gdy któraś strona zna tylko
//    nazwę. Dziennik spoin zapisuje dziś „TIG" / „MIG/MAG" / „MMA" / „Tandem",
//    bez numeru, więc na nim da się sprawdzić tylko rodzinę. Tak też liczy
//    ASME IX QW-322.1(a): ciągłość jest „dla procesu" (GTAW, SMAW…).

/// Rodzina procesu — poziom, na którym ASME IX liczy ciągłość (QW-322.1)
/// i na którym da się porównać wpis z dziennika bez numeru ISO 4063.
enum WeldProcessFamily {
  /// 111 — MMA / SMAW (elektroda otulona).
  smaw('SMAW', 'MMA'),

  /// 121–126 — łuk kryty / SAW.
  saw('SAW', 'SAW'),

  /// 131, 135, 138 — MIG/MAG, drut proszkowy metaliczny / GMAW.
  gmaw('GMAW', 'MIG/MAG'),

  /// 114, 136, 137 — drut proszkowy (samoosłonowy i w osłonie gazu) / FCAW.
  fcaw('FCAW', 'FCAW'),

  /// 141–147 — TIG (także orbitalny i tandem) / GTAW.
  gtaw('GTAW', 'TIG'),

  /// 151–155 — plazma / PAW.
  paw('PAW', 'Plazma'),

  /// 311 — spawanie gazowe / OFW.
  ofw('OFW', 'Gaz');

  const WeldProcessFamily(this.asmeCode, this.euName);

  /// Skrót ASME (GTAW, SMAW…).
  final String asmeCode;

  /// Nazwa potoczna w Europie (TIG, MMA…).
  final String euName;
}

/// Rodzaj spoiny objęty uprawnieniem / WPS: czołowa (BW) albo pachwinowa (FW).
enum WeldJointKind {
  bw('BW'),
  fw('FW');

  const WeldJointKind(this.code);

  /// Kod zapisywany w bazie i w JSON-ie WPS.
  final String code;

  static WeldJointKind? fromCode(String? raw) {
    final v = raw?.trim().toUpperCase();
    for (final k in WeldJointKind.values) {
      if (k.code == v) return k;
    }
    return null;
  }
}

/// `{BW, FW}` → `'BW+FW'` (stała kolejność, żeby wiersz w bazie był
/// porównywalny między zapisami).
String encodeJointKinds(Set<WeldJointKind> kinds) => [
      for (final k in WeldJointKind.values)
        if (kinds.contains(k)) k.code,
    ].join('+');

/// Odwrotność [encodeJointKinds]; toleruje przecinki, spacje i małe litery.
Set<WeldJointKind> decodeJointKinds(String? raw) {
  if (raw == null) return <WeldJointKind>{};
  final out = <WeldJointKind>{};
  for (final part in raw.split(RegExp(r'[+,;/\s]+'))) {
    final k = WeldJointKind.fromCode(part);
    if (k != null) out.add(k);
  }
  return out;
}

/// Rodzina dla numeru procesu wg EN ISO 4063, albo `null` dla numeru, którego
/// nie znamy (wtedy nie zgadujemy).
WeldProcessFamily? familyOfIso4063(int number) {
  if (number == 111) return WeldProcessFamily.smaw;
  if (number == 114) return WeldProcessFamily.fcaw;
  if (number >= 121 && number <= 126) return WeldProcessFamily.saw;
  if (number == 131 || number == 135 || number == 138) {
    return WeldProcessFamily.gmaw;
  }
  if (number == 136 || number == 137) return WeldProcessFamily.fcaw;
  if (number >= 141 && number <= 147) return WeldProcessFamily.gtaw;
  if (number >= 151 && number <= 155) return WeldProcessFamily.paw;
  if (number == 311) return WeldProcessFamily.ofw;
  return null;
}

final RegExp _kIsoNumber = RegExp(r'(?<!\d)(\d{3})(?!\d)');

/// Nazwy, którymi spawacz opisuje proces, → rodzina. Dopasowanie po całym
/// słowie (bez polskich znaków i wielkości liter), żeby „SAW" nie złapało
/// „SMAW".
const Map<String, WeldProcessFamily> _kNames = <String, WeldProcessFamily>{
  'TIG': WeldProcessFamily.gtaw,
  'WIG': WeldProcessFamily.gtaw,
  'GTAW': WeldProcessFamily.gtaw,
  'TANDEM': WeldProcessFamily.gtaw,
  'ORBITAL': WeldProcessFamily.gtaw,
  'ORBITALNE': WeldProcessFamily.gtaw,
  'ORBITALNY': WeldProcessFamily.gtaw,
  'MIG': WeldProcessFamily.gmaw,
  'MAG': WeldProcessFamily.gmaw,
  'GMAW': WeldProcessFamily.gmaw,
  'MMA': WeldProcessFamily.smaw,
  'MMAW': WeldProcessFamily.smaw,
  'SMAW': WeldProcessFamily.smaw,
  'STICK': WeldProcessFamily.smaw,
  'ELEKTRODA': WeldProcessFamily.smaw,
  'FCAW': WeldProcessFamily.fcaw,
  'SAW': WeldProcessFamily.saw,
  'PAW': WeldProcessFamily.paw,
  'PLAZMA': WeldProcessFamily.paw,
  'PLASMA': WeldProcessFamily.paw,
  'OFW': WeldProcessFamily.ofw,
};

/// Numery EN ISO 4063 wymienione w [text] („141, 135" → {141, 135}). Tylko
/// numery, które [familyOfIso4063] zna — „2026" z daty albo „316" z gatunku
/// stali nie są procesem.
Set<int> iso4063NumbersIn(String? text) {
  if (text == null || text.isEmpty) return <int>{};
  final out = <int>{};
  for (final m in _kIsoNumber.allMatches(text)) {
    final n = int.parse(m.group(1)!);
    if (familyOfIso4063(n) != null) out.add(n);
  }
  return out;
}

/// Rodziny procesów wymienione w [text] — z numerów ISO 4063 i z nazw.
///
/// „141" → {GTAW}; „TIG" → {GTAW}; „MIG/MAG" → {GMAW}; „141 + 111" → {GTAW,
/// SMAW}. Pusty zbiór, gdy nic nie rozpoznano — wołający traktuje to jako
/// „proces nieznany", a nie jako niezgodność.
Set<WeldProcessFamily> processFamiliesIn(String? text) {
  if (text == null || text.trim().isEmpty) return <WeldProcessFamily>{};
  final out = <WeldProcessFamily>{
    for (final n in iso4063NumbersIn(text)) familyOfIso4063(n)!,
  };
  final words = text.toUpperCase().split(RegExp(r'[^A-Z0-9ĄĆĘŁŃÓŚŹŻ]+'));
  for (final w in words) {
    final f = _kNames[w];
    if (f != null) out.add(f);
  }
  return out;
}

/// Pary procesów, które ISO 9606-1 §5.2 uznaje za wzajemnie kwalifikujące
/// (135 ↔ 138, 121 ↔ 125). Dotyczy WYŁĄCZNIE uprawnień spawacza — WPS
/// (ISO 15614-1) kwalifikuje każdy proces osobno.
const Map<int, Set<int>> kIso9606MutualProcesses = <int, Set<int>>{
  135: <int>{138},
  138: <int>{135},
  121: <int>{125},
  125: <int>{121},
};

/// Wynik porównania procesu spoiny z procesami dopuszczonymi.
enum ProcessMatch {
  /// Proces spoiny mieści się w dopuszczonych.
  covered,

  /// Proces spoiny rozpoznany i NIE mieści się w dopuszczonych.
  notCovered,

  /// Brak danych po którejś stronie — nie da się ocenić.
  unknown,
}

/// Czy proces(y) spoiny [weldProcess] są objęte [allowedProcesses].
///
/// Gdy obie strony podają numery ISO 4063 — porównanie numerów (z parami
/// [mutual], jeśli podane). Gdy którakolwiek zna tylko nazwę — porównanie
/// rodzin. Spoina wykonana dwoma procesami (np. „141 + 111") musi mieć
/// dopuszczony każdy z nich.
ProcessMatch matchProcess(
  String? weldProcess,
  String? allowedProcesses, {
  Map<int, Set<int>> mutual = const <int, Set<int>>{},
}) {
  final weldFamilies = processFamiliesIn(weldProcess);
  final allowedFamilies = processFamiliesIn(allowedProcesses);
  if (weldFamilies.isEmpty || allowedFamilies.isEmpty) {
    return ProcessMatch.unknown;
  }
  final weldNumbers = iso4063NumbersIn(weldProcess);
  final allowedNumbers = iso4063NumbersIn(allowedProcesses);
  if (weldNumbers.isNotEmpty && allowedNumbers.isNotEmpty) {
    final expanded = <int>{
      ...allowedNumbers,
      for (final n in allowedNumbers) ...?mutual[n],
    };
    // Rodzina z samej nazwy po stronie spoiny (np. „141 + MMA") też musi być
    // dopuszczona.
    final namedOnly = weldFamilies.difference(
        {for (final n in weldNumbers) familyOfIso4063(n)!});
    final numbersOk = weldNumbers.every(expanded.contains);
    final namesOk = namedOnly.every(allowedFamilies.contains);
    return numbersOk && namesOk
        ? ProcessMatch.covered
        : ProcessMatch.notCovered;
  }
  return weldFamilies.every(allowedFamilies.contains)
      ? ProcessMatch.covered
      : ProcessMatch.notCovered;
}
