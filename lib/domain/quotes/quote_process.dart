/// Procesy spawania w wycenie i ich założenia produkcyjne.
///
/// Wycena liczy z masy stopiwa, a masa → czas i materiał przechodzi przez
/// pięć liczb na proces:
///   • wydajność stapiania [ProcessProfile.depositionKgH] — kg stopiwa na
///     godzinę JARZENIA SIĘ ŁUKU;
///   • uzysk [ProcessProfile.efficiency] — ile z kupionego spoiwa zostaje
///     w spoinie (resztę zjadają ogarki elektrod, żużel, rozprysk, końcówki
///     prętów);
///   • współczynnik jarzenia łuku [ProcessProfile.dutyCycle] — jaka część
///     czasu spawania to łuk (reszta: czyszczenie między ściegami,
///     wymiana elektrody, szlifowanie zakończeń, kontrola interpass);
///   • przepływ gazu osłonowego [ProcessProfile.gasLpm];
///   • moc łuku [ProcessProfile.arcKw] = U·I.
///
/// Wartości domyślne to TYPOWE zakresy z katalogów producentów materiałów
/// spawalniczych i podręczników kosztorysowania (ręczne spawanie rur
/// i blach, pozycje wymuszone uśrednione) — nie pomiar z Twojej brygady.
/// Każdą da się nadpisać w wycenie („Założenia"), a nadpisanie zapisuje się
/// razem z wyceną.
///
/// Czysty Dart: bez Fluttera i bez bazy.
library;

/// Proces spawania (numer wg EN ISO 4063).
enum QuoteProcess {
  tig('TIG', '141'),
  mma('MMA', '111'),
  mag('MAG', '135'),
  fcaw('FCAW', '136'),
  mig('MIG', '131'),
  saw('SAW', '121');

  const QuoteProcess(this.code, this.isoNo);

  /// Trwały kod w zapisanej wycenie.
  final String code;

  /// Numer procesu wg EN ISO 4063.
  final String isoNo;

  /// „TIG 141".
  String get label => '$code $isoNo';

  /// Gaz osłonowy obojętny (argon) — TIG i MIG; aktywny (mieszanka) — MAG
  /// i FCAW; bez gazu — MMA i SAW.
  QuoteGasKind get gasKind => switch (this) {
        QuoteProcess.tig || QuoteProcess.mig => QuoteGasKind.argon,
        QuoteProcess.mag || QuoteProcess.fcaw => QuoteGasKind.mix,
        QuoteProcess.mma || QuoteProcess.saw => QuoteGasKind.none,
      };

  static QuoteProcess? fromCode(String? code) {
    for (final p in values) {
      if (p.code == code) return p;
    }
    return null;
  }
}

/// Rodzaj gazu osłonowego — decyduje, którą cenę za m³ bierze wycena.
enum QuoteGasKind { none, argon, mix }

/// Założenia produkcyjne jednego procesu.
class ProcessProfile {
  /// kg stopiwa na godzinę jarzenia się łuku.
  final double depositionKgH;

  /// Uzysk: stopiwo / zużyte spoiwo (0–1].
  final double efficiency;

  /// Czas łuku / czas spawania (0–1].
  final double dutyCycle;

  /// Gaz osłonowy, L/min (0 dla MMA i SAW).
  final double gasLpm;

  /// Moc łuku U·I, kW.
  final double arcKw;

  /// kg topnika na kg drutu (tylko SAW; inaczej 0).
  final double fluxRatio;

  const ProcessProfile({
    required this.depositionKgH,
    required this.efficiency,
    required this.dutyCycle,
    required this.gasLpm,
    required this.arcKw,
    this.fluxRatio = 0,
  });

  /// Czy profil da się użyć do liczenia (dodatnie mianowniki).
  bool get isValid =>
      depositionKgH > 0 &&
      efficiency > 0 &&
      efficiency <= 1 &&
      dutyCycle > 0 &&
      dutyCycle <= 1 &&
      gasLpm >= 0 &&
      arcKw >= 0 &&
      fluxRatio >= 0;

  ProcessProfile copyWith({
    double? depositionKgH,
    double? efficiency,
    double? dutyCycle,
    double? gasLpm,
    double? arcKw,
    double? fluxRatio,
  }) =>
      ProcessProfile(
        depositionKgH: depositionKgH ?? this.depositionKgH,
        efficiency: efficiency ?? this.efficiency,
        dutyCycle: dutyCycle ?? this.dutyCycle,
        gasLpm: gasLpm ?? this.gasLpm,
        arcKw: arcKw ?? this.arcKw,
        fluxRatio: fluxRatio ?? this.fluxRatio,
      );

  Map<String, Object?> toJson() => {
        'dep': depositionKgH,
        'eff': efficiency,
        'duty': dutyCycle,
        'gas': gasLpm,
        'kw': arcKw,
        'flux': fluxRatio,
      };

  /// Brakujące / zepsute pole bierze wartość z [fallback] — stara wycena
  /// bez nowego pola dalej się liczy.
  static ProcessProfile fromJson(Object? raw, ProcessProfile fallback) {
    if (raw is! Map) return fallback;
    double pick(String k, double d) {
      final v = raw[k];
      return v is num && v.isFinite ? v.toDouble() : d;
    }

    final p = ProcessProfile(
      depositionKgH: pick('dep', fallback.depositionKgH),
      efficiency: pick('eff', fallback.efficiency),
      dutyCycle: pick('duty', fallback.dutyCycle),
      gasLpm: pick('gas', fallback.gasLpm),
      arcKw: pick('kw', fallback.arcKw),
      fluxRatio: pick('flux', fallback.fluxRatio),
    );
    return p.isValid ? p : fallback;
  }

  @override
  bool operator ==(Object other) =>
      other is ProcessProfile &&
      other.depositionKgH == depositionKgH &&
      other.efficiency == efficiency &&
      other.dutyCycle == dutyCycle &&
      other.gasLpm == gasLpm &&
      other.arcKw == arcKw &&
      other.fluxRatio == fluxRatio;

  @override
  int get hashCode => Object.hash(
      depositionKgH, efficiency, dutyCycle, gasLpm, arcKw, fluxRatio);
}

/// Typowe założenia — punkt wyjścia, nie norma.
///
/// • TIG 141 ręczny z drutem: 0,3–0,8 kg/h łuku; pręty tracą końcówki
///   (uzysk ~95 %); argon 8–12 L/min; ~12 V × 130 A.
/// • MMA 111 (Ø2,5–4,0): 0,8–1,6 kg/h; uzysk 55–65 % (ogarek ~50 mm,
///   żużel, rozprysk); łuk jarzy się ~30 % czasu; ~23 V × 120 A.
/// • MAG 135 drut lity Ø1,0–1,2: 2–4 kg/h (pozycje wymuszone niżej);
///   rozprysk ~5–8 %; M21 12–16 L/min; ~22 V × 180 A.
/// • FCAW 136 rutylowy pozycyjny: 2,5–3,5 kg/h; uzysk 80–85 % (żużel);
///   gaz 14–18 L/min; ~25 V × 200 A.
/// • MIG 131 (aluminium): 1,5–2 kg/h; argon 14–18 L/min; ~22 V × 160 A.
/// • SAW 121 (zmechanizowane, PA): 5–10 kg/h; topnik ~1–1,5 kg/kg drutu;
///   ~32 V × 550 A.
const Map<QuoteProcess, ProcessProfile> kDefaultProcessProfiles = {
  QuoteProcess.tig: ProcessProfile(
      depositionKgH: 0.5,
      efficiency: 0.95,
      dutyCycle: 0.35,
      gasLpm: 10,
      arcKw: 1.6),
  QuoteProcess.mma: ProcessProfile(
      depositionKgH: 1.0,
      efficiency: 0.60,
      dutyCycle: 0.30,
      gasLpm: 0,
      arcKw: 2.8),
  QuoteProcess.mag: ProcessProfile(
      depositionKgH: 2.5,
      efficiency: 0.92,
      dutyCycle: 0.40,
      gasLpm: 14,
      arcKw: 4.0),
  QuoteProcess.fcaw: ProcessProfile(
      depositionKgH: 2.8,
      efficiency: 0.83,
      dutyCycle: 0.40,
      gasLpm: 16,
      arcKw: 5.0),
  QuoteProcess.mig: ProcessProfile(
      depositionKgH: 1.6,
      efficiency: 0.90,
      dutyCycle: 0.35,
      gasLpm: 16,
      arcKw: 3.5),
  QuoteProcess.saw: ProcessProfile(
      depositionKgH: 6.0,
      efficiency: 0.99,
      dutyCycle: 0.55,
      gasLpm: 0,
      arcKw: 17.6,
      fluxRatio: 1.2),
};

/// Sprawność źródła prądu (falownik ~0,85): energia z sieci = łuk / η.
const double kWelderPowerEfficiency = 0.85;

/// Gaz osłonowy płynie też przed zajarzeniem i po zgaszeniu łuku (pre-/
/// post-flow) i przy ustawianiu przepływu — +15 % do czasu łuku.
const double kShieldGasAllowance = 1.15;

/// Schemat procesów złącza: grań jednym, wypełnienie i lico drugim
/// („TIG + MMA" na rurach) albo całość jednym procesem ([root] == null).
class WeldScheme {
  final QuoteProcess? root;
  final QuoteProcess fill;

  const WeldScheme({this.root, required this.fill});

  const WeldScheme.single(this.fill) : root = null;

  /// Grań innym procesem niż wypełnienie.
  bool get isCombo => root != null && root != fill;

  /// Procesy w kolejności użycia, bez powtórzeń.
  List<QuoteProcess> get processes => isCombo ? [root!, fill] : [fill];

  /// „TIG + MMA" albo „MAG".
  String get label => isCombo ? '${root!.code} + ${fill.code}' : fill.code;

  /// `TIG+MMA` / `MAG` — trwały zapis.
  String get code => isCombo ? '${root!.code}+${fill.code}' : fill.code;

  static WeldScheme? fromCode(String? code) {
    if (code == null || code.trim().isEmpty) return null;
    final parts = code.split('+').map((s) => s.trim()).toList();
    if (parts.length == 1) {
      final p = QuoteProcess.fromCode(parts.first);
      return p == null ? null : WeldScheme.single(p);
    }
    if (parts.length == 2) {
      final r = QuoteProcess.fromCode(parts[0]);
      final f = QuoteProcess.fromCode(parts[1]);
      if (r == null || f == null) return null;
      return r == f ? WeldScheme.single(f) : WeldScheme(root: r, fill: f);
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is WeldScheme && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// Schematy pokazywane jako szybki wybór. Kolejność = częstość na
/// rurociągach (grań TIG to standard dla rur odpowiedzialnych).
const List<WeldScheme> kCommonSchemes = [
  WeldScheme(root: QuoteProcess.tig, fill: QuoteProcess.mma),
  WeldScheme.single(QuoteProcess.tig),
  WeldScheme(root: QuoteProcess.tig, fill: QuoteProcess.fcaw),
  WeldScheme(root: QuoteProcess.tig, fill: QuoteProcess.mag),
  WeldScheme.single(QuoteProcess.mma),
  WeldScheme.single(QuoteProcess.mag),
  WeldScheme.single(QuoteProcess.fcaw),
  WeldScheme.single(QuoteProcess.mig),
  WeldScheme.single(QuoteProcess.saw),
];
