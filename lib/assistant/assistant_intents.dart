// Wersjonowana lista operacji, które asystent może PRZYGOTOWAĆ (spec §6).
//
// To jest kontrakt między modelem na serwerze (`POST /api/fitter/ai/intent`,
// pole `intents_version`), parserem lokalnym i walidatorem. Model może zwrócić
// wyłącznie intencję z tej listy i wyłącznie wymienione pola — wszystko inne
// walidator odrzuca. Nowa operacja = nowa wersja listy (V2), nie dopisek do V1,
// bo stary backend nie może dostać pola, którego nie zna.

/// Numer wersji wysyłany na serwer jako `intents_version`.
const int kAssistantIntentsVersion = 1;

const String kIntentSaveWeldParameter = 'save_weld_parameter';
const String kIntentOpenTool = 'open_tool';

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
};

/// Najdłuższe zapytanie `open_tool` (znaki).
const int kAssistantMaxQueryLength = 80;
