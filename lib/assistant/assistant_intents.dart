// Wersjonowana lista operacji, które asystent może PRZYGOTOWAĆ (spec §6).
//
// Dwie listy:
//   • [kAssistantIntentsV1] — kontrakt z modelem na serwerze
//     (`POST /api/fitter/ai/intent`, pole `intents_version`). Serwer może
//     zwrócić wyłącznie intencję z tej listy i wyłącznie wymienione pola.
//     Słowniki, zakresy i kolejność pytań są takie same jak w backendzie —
//     pilnuje tego wspólny plik test/assistant/fixtures/
//     assistant_intent_contract_v1.json (ten sam w repo backendu). Nowa
//     operacja serwera = nowa wersja listy (V2), nie dopisek do V1.
//   • [kAssistantIntents] — wszystko, co rozumie aplikacja: V1 plus intencje
//     i pola TYLKO LOKALNE (parser offline; serwer ich nie zna i nie może ich
//     zwrócić). Walidator sprawdza propozycje względem tej listy.

/// Numer wersji wysyłany na serwer jako `intents_version`.
const int kAssistantIntentsVersion = 1;

const String kIntentSaveWeldParameter = 'save_weld_parameter';
const String kIntentOpenTool = 'open_tool';

/// Przygotowanie wpisu do dziennika spoin (tylko lokalnie, zapis po „Zapisz").
const String kIntentAddWeldJournalEntry = 'add_weld_journal_entry';

/// Odczyt „Moich parametrów" (tylko lokalnie, offline, nic nie zapisuje).
const String kIntentQueryMyParams = 'query_my_params';

/// Pytanie wiedzowe („jaki prąd na…", „ile…") — trafia do trybu „Odpowiedz",
/// nigdy do zapisu.
const String kIntentAnswerQuestion = 'answer_question';

/// Nie operacja — parser/model nie rozpoznał polecenia.
const String kIntentUnknown = 'unknown';

class AssistantIntentSpec {
  /// Pola, bez których operacja nie jest kompletna (walidator dopyta).
  final Set<String> required;

  /// Pola dozwolone, ale nieobowiązkowe.
  final Set<String> optional;

  const AssistantIntentSpec({required this.required, this.optional = const {}});

  Set<String> get allFields => {...required, ...optional};
}

/// Kolejność, w jakiej asystent dopytuje o brakujące pola zapisu parametru.
const List<String> kSaveWeldRequiredOrder = [
  'material',
  'process',
  'filler',
  'wall_mm',
  'current_a',
];

/// Kolejność pytań przy wpisie do dziennika spoin.
const List<String> kJournalRequiredOrder = ['weld_no', 'project'];

/// Kontrakt z serwerem (V1) — dokładnie to, co może przyjść z `/ai/intent`.
const Map<String, AssistantIntentSpec> kAssistantIntentsV1 = {
  kIntentSaveWeldParameter: AssistantIntentSpec(
    required: {'material', 'process', 'filler', 'wall_mm', 'current_a'},
    optional: {
      'diameter_mm',
      'position',
      'gas',
      'flow_lpm',
      'electrode_mm',
      'joint',
    },
  ),
  kIntentOpenTool: AssistantIntentSpec(required: {'query'}),
};

/// Wszystkie intencje aplikacji: V1 + pola i intencje tylko lokalne.
const Map<String, AssistantIntentSpec> kAssistantIntents = {
  kIntentSaveWeldParameter: AssistantIntentSpec(
    required: {'material', 'process', 'filler', 'wall_mm', 'current_a'},
    optional: {
      'diameter_mm',
      'position',
      'gas',
      'flow_lpm',
      'electrode_mm',
      'joint',
      // Tylko lokalnie: przepływ gazu formującego („formowanie 5 l").
      'purge_lpm',
    },
  ),
  kIntentOpenTool: AssistantIntentSpec(required: {'query'}),
  kIntentAddWeldJournalEntry: AssistantIntentSpec(
    required: {'weld_no', 'project'},
    optional: {'wps'},
  ),
  kIntentQueryMyParams: AssistantIntentSpec(
    required: {},
    optional: {
      'material',
      'process',
      'filler',
      'wall_mm',
      'diameter_mm',
      'electrode_mm',
    },
  ),
  kIntentAnswerQuestion: AssistantIntentSpec(required: {'text'}),
};

/// Intencje, o które wolno pytać serwer i które serwer może zwrócić.
Set<String> get kAssistantRemoteIntents => kAssistantIntentsV1.keys.toSet();

// ── Słowniki wartości ────────────────────────────────────────────────────────

const Set<String> kAssistantMaterials = {'SS', 'CS', 'DUPLEX', 'AL', 'OTHER'};
const Set<String> kAssistantProcesses = {'TIG', 'MIG_MAG', 'MMA', 'OTHER'};
const Set<String> kAssistantGases = {
  'AR',
  'M21',
  'CO2',
  'AR_HE',
  'AR_H2',
  'N2',
  'OTHER',
};
const Set<String> kAssistantJoints = {
  'BUTT',
  'FILLET',
  'SOCKET',
  'BRANCH',
  'OTHER',
};

/// Pozycje wg ISO 6947 (PA…PJ, H-L045, J-L045) i ASME IX (1G…6G, 6GR, 1F…4F).
const Set<String> kAssistantPositions = {
  'PA', 'PB', 'PC', 'PD', 'PE', 'PF', 'PG', 'PH', 'PJ', //
  'H-L045', 'J-L045', //
  '1G', '2G', '3G', '4G', '5G', '6G', '6GR', //
  '1F', '2F', '3F', '4F',
};

/// Zakres liczby (włącznie z granicami) i jej jednostka.
class AssistantRange {
  final double min;
  final double max;
  final String unit;
  const AssistantRange(this.min, this.max, this.unit);

  bool contains(double v) => v >= min && v <= max;
}

/// Zakresy pól liczbowych. Wartości spoza nich są fizycznie niemożliwe dla
/// spawania rur ręcznego/orbitalnego albo są pomyłką rozpoznawania mowy
/// („sześćset" zamiast „sześćdziesiąt").
const Map<String, AssistantRange> kAssistantRanges = {
  'current_a': AssistantRange(5, 500, 'A'),
  'wall_mm': AssistantRange(0.3, 50, 'mm'),
  'diameter_mm': AssistantRange(3, 2000, 'mm'),
  'flow_lpm': AssistantRange(1, 40, 'l/min'),
  'electrode_mm': AssistantRange(0.5, 6.4, 'mm'),
  // Tylko lokalnie (poza kontraktem V1).
  'purge_lpm': AssistantRange(1, 40, 'l/min'),
};

/// Pola liczbowe kontraktu V1 (bez pól tylko lokalnych).
const Set<String> kAssistantRangesV1 = {
  'current_a',
  'wall_mm',
  'diameter_mm',
  'flow_lpm',
  'electrode_mm',
};

/// Najdłuższe zapytanie `open_tool` (znaki).
const int kAssistantMaxQueryLength = 80;

/// Najdłuższe wartości tekstowe wpisu do dziennika (znaki).
const Map<String, int> kAssistantTextLimits = {
  'weld_no': 20,
  'project': 80,
  'wps': 40,
  'text': 2000,
};

// ── Aliasy (kontrakt V1) ─────────────────────────────────────────────────────
// Serwer zwraca kody ze słowników, ale starszy backend (i model bez enum)
// potrafił oddać „Ar 99.996" albo „BW". Ta sama tabela i ta sama reguła klucza
// jest w backendzie (services/fitterIntent.js: aliasKey / normalizeCode).

const Map<String, String> _plDiacritics = {
  'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n', //
  'ó': 'o', 'ś': 's', 'ź': 'z', 'ż': 'z',
};

/// Klucz porównania aliasu: małe litery, bez polskich znaków, tylko [a-z0-9+].
String assistantAliasKey(String value) {
  final buf = StringBuffer();
  for (final c in value.toLowerCase().split('')) {
    final folded = _plDiacritics[c] ?? c;
    if (RegExp(r'^[a-z0-9+]$').hasMatch(folded)) buf.write(folded);
  }
  return buf.toString();
}

const Map<String, String> _gasAliases = {
  'ar': 'AR', 'argon': 'AR', 'i1': 'AR', 'czystyargon': 'AR', 'pureargon': 'AR', //
  'm21': 'M21', 'ar+18co2': 'M21', 'ar+15co2': 'M21', 'ar+20co2': 'M21',
  'ar+25co2': 'M21', 'arco28218': 'M21', 'mieszanka': 'M21', 'mix': 'M21',
  'corgon18': 'M21', 'arco2': 'M21', 'ar+co2': 'M21', //
  'co2': 'CO2', 'c1': 'CO2', 'dwutlenekwegla': 'CO2', 'carbondioxide': 'CO2', //
  'arhe': 'AR_HE', 'ar+he': 'AR_HE', 'argon+hel': 'AR_HE',
  'argon+helium': 'AR_HE', 'i3': 'AR_HE', //
  'arh2': 'AR_H2', 'ar+h2': 'AR_H2', 'argon+wodor': 'AR_H2',
  'argon+hydrogen': 'AR_H2', 'r1': 'AR_H2', //
  'n2': 'N2', 'azot': 'N2', 'nitrogen': 'N2', //
  'ar+2co2': 'OTHER', 'm12': 'OTHER', 'other': 'OTHER', 'inny': 'OTHER',
  'inne': 'OTHER',
};

const Map<String, String> _jointAliases = {
  'butt': 'BUTT', 'bw': 'BUTT', 'doczolowe': 'BUTT', 'doczolowa': 'BUTT',
  'doczolowy': 'BUTT', 'nastyk': 'BUTT', //
  'fillet': 'FILLET', 'fw': 'FILLET', 'pachwinowe': 'FILLET',
  'pachwinowa': 'FILLET', 'pachwinowy': 'FILLET', //
  'socket': 'SOCKET', 'sw': 'SOCKET', 'kielichowe': 'SOCKET',
  'kielichowa': 'SOCKET', 'mufowe': 'SOCKET', 'mufowa': 'SOCKET', //
  'branch': 'BRANCH', 'br': 'BRANCH', 'odgalezienie': 'BRANCH',
  'seton': 'BRANCH', 'setin': 'BRANCH', 'krociec': 'BRANCH', 'krocca': 'BRANCH', //
  'other': 'OTHER', 'inne': 'OTHER', 'inny': 'OTHER',
};

final RegExp _controlChars = RegExp('[\u0000-\u001f\u007f-\u009f  ]');

/// Kod ze słownika dla `gas` / `joint` / `position` albo null, gdy wartości
/// nie da się jednoznacznie przypisać.
String? normalizeAssistantCode(String field, Object? value) {
  if (value is! String || value.length > 40 || _controlChars.hasMatch(value)) {
    return null;
  }
  final key = assistantAliasKey(value);
  if (key.isEmpty) return null;
  switch (field) {
    case 'gas':
      if (RegExp(r'^(?:ar|argon)99\d*$').hasMatch(key)) return 'AR';
      return _gasAliases[key];
    case 'joint':
      return _jointAliases[key];
    case 'position':
      for (final p in kAssistantPositions) {
        if (assistantAliasKey(p) == key) return p;
      }
      return null;
  }
  return null;
}
