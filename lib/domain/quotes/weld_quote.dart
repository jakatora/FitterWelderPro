/// Wycena spawalnicza — model zapisywany w tabeli `weld_quotes` (v26).
///
/// Zasada pieniędzy: wycena przechowuje WŁASNĄ kopię stawek i cen
/// ([QuoteRates]) z chwili utworzenia. Zmiana „moich stawek" w ustawieniach
/// dotyczy tylko NOWYCH wycen — wysłana klientowi oferta nie może się sama
/// przeliczyć po podwyżce prądu.
///
/// Kwoty wpisywane przez użytkownika (stawki, ceny) trzymamy jako zł
/// (double), a wynik liczy kalkulator w groszach (int) — patrz
/// quote_calculator.dart.
///
/// Czysty Dart.
library;

import 'dart:convert';

import 'quote_process.dart';
import 'weld_geometry.dart';

/// Materiał podstawowy — gęstość stopiwa i typowe ceny spoiw.
enum QuoteMaterial {
  carbon('CS', 7.85, 'Stal węglowa', 'Carbon steel'),
  stainless('SS', 7.95, 'Stal nierdzewna', 'Stainless steel'),
  duplex('DUPLEX', 7.80, 'Duplex', 'Duplex'),
  crMo('CRMO', 7.85, 'Stal Cr-Mo (P11–P91)', 'Cr-Mo steel (P11–P91)'),
  aluminium('AL', 2.70, 'Aluminium', 'Aluminium');

  const QuoteMaterial(this.code, this.densityGcm3, this.labelPl, this.labelEn);

  final String code;

  /// Gęstość stopiwa, g/cm³.
  final double densityGcm3;
  final String labelPl;
  final String labelEn;

  /// Nierdzewka i duplex potrzebują formowania grani — domyślnie włączone.
  bool get purgeByDefault => this == stainless || this == duplex;

  static QuoteMaterial fromCode(String? code) {
    for (final m in values) {
      if (m.code == code) return m;
    }
    return carbon;
  }
}

/// Orientacyjne ceny spoiw netto, zł/kg (rynek PL, 2026) — tylko punkt
/// startowy nowej wyceny; użytkownik wpisuje swoje i może je zapamiętać.
const Map<QuoteMaterial, Map<QuoteProcess, double>> kDefaultFillerPrices = {
  QuoteMaterial.carbon: {
    QuoteProcess.tig: 32,
    QuoteProcess.mma: 22,
    QuoteProcess.mag: 10,
    QuoteProcess.fcaw: 24,
    QuoteProcess.mig: 10,
    QuoteProcess.saw: 11,
  },
  QuoteMaterial.stainless: {
    QuoteProcess.tig: 115,
    QuoteProcess.mma: 95,
    QuoteProcess.mag: 75,
    QuoteProcess.fcaw: 90,
    QuoteProcess.mig: 75,
    QuoteProcess.saw: 70,
  },
  QuoteMaterial.duplex: {
    QuoteProcess.tig: 170,
    QuoteProcess.mma: 150,
    QuoteProcess.mag: 130,
    QuoteProcess.fcaw: 140,
    QuoteProcess.mig: 130,
    QuoteProcess.saw: 125,
  },
  QuoteMaterial.crMo: {
    QuoteProcess.tig: 120,
    QuoteProcess.mma: 65,
    QuoteProcess.mag: 60,
    QuoteProcess.fcaw: 85,
    QuoteProcess.mig: 60,
    QuoteProcess.saw: 55,
  },
  QuoteMaterial.aluminium: {
    QuoteProcess.tig: 90,
    QuoteProcess.mma: 120,
    QuoteProcess.mag: 60,
    QuoteProcess.fcaw: 60,
    QuoteProcess.mig: 60,
    QuoteProcess.saw: 60,
  },
};

/// Pozycja spawania — mnożnik czasu spawania (reguła kosztorysowa: pozycje
/// wymuszone wolniej niż podolna; rura obracana = PA).
enum WeldPosition {
  pa('PA', 1.0, 'PA / 1G — podolna, rura obracana',
      'PA / 1G — flat, rolled pipe'),
  pc('PC', 1.2, 'PC / 2G — naścienna', 'PC / 2G — horizontal'),
  pf('PF', 1.35, 'PF·PH / 5G — rura stała pozioma',
      'PF·PH / 5G — fixed horizontal'),
  hl045('H-L045', 1.5, 'H-L045 / 6G — rura pochylona 45°',
      'H-L045 / 6G — inclined 45°'),
  pe('PE', 1.6, 'PE / 4G — pułapowa', 'PE / 4G — overhead');

  const WeldPosition(this.code, this.factor, this.labelPl, this.labelEn);
  final String code;
  final double factor;
  final String labelPl;
  final String labelEn;

  static WeldPosition fromCode(String? code) {
    for (final p in values) {
      if (p.code == code) return p;
    }
    return pa;
  }
}

/// Warunki pracy — mnożnik całej robocizny.
enum QuoteSite {
  shop('SHOP', 1.0, 'Warsztat / prefabrykacja', 'Shop / prefabrication'),
  field('FIELD', 1.3, 'Montaż na obiekcie', 'Field erection'),
  difficult('HARD', 1.6, 'Trudny dostęp, wysokość, ciasno',
      'Difficult access, height, tight space');

  const QuoteSite(this.code, this.factor, this.labelPl, this.labelEn);
  final String code;
  final double factor;
  final String labelPl;
  final String labelEn;

  static QuoteSite fromCode(String? code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return shop;
  }
}

/// Typowe opakowania spoiwa, kg: pręty TIG w tubie 5 kg, elektrody w paczce
/// ~5 kg, drut MAG/FCAW na szpuli 15 kg, aluminium 7 kg, SAW 25 kg. Do
/// zmiany w liście zakupów.
const Map<QuoteProcess, double> kDefaultPackKg = {
  QuoteProcess.tig: 5,
  QuoteProcess.mma: 5,
  QuoteProcess.mag: 15,
  QuoteProcess.fcaw: 15,
  QuoteProcess.mig: 7,
  QuoteProcess.saw: 25,
};

/// Stawka VAT oferty.
enum QuoteVat {
  vat23('23', 0.23, '23%'),
  vat8('8', 0.08, '8%'),
  vat0('0', 0, '0%'),

  /// „Nie podlega" — usługa opodatkowana poza Polską, np. dla firmy
  /// z innego kraju UE (art. 28b ustawy o VAT, odwrotne obciążenie
  /// u nabywcy) — typowe przy pracy na delegacji. Krajowe odwrotne
  /// obciążenie robót budowlanych zniesiono 1.11.2019. Bez kwoty VAT.
  notApplicable('NP', 0, 'np.'),

  /// Zwolnienie podmiotowe (art. 113) — „zw.".
  exempt('ZW', 0, 'zw.');

  const QuoteVat(this.code, this.rate, this.label);
  final String code;
  final double rate;
  final String label;

  static QuoteVat fromCode(String? code) {
    for (final v in values) {
      if (v.code == code) return v;
    }
    return vat23;
  }
}

double _num(Object? v, double fallback) =>
    v is num && v.isFinite ? v.toDouble() : fallback;

double? _numOrNull(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

String _str(Object? v) => v is String ? v : '';

/// Bez rzutowania `as String?`: poprawny JSON ze złym typem pola (np. po
/// ręcznej edycji kopii) nie może wywrócić odczytu całej listy wycen.
String? _strOrNull(Object? v) => v is String ? v : null;

/// Jedna pozycja złącza w wycenie: „12 × spoina doczołowa DN100 Sch40".
class QuoteJoint {
  final String id;
  final JointKind kind;

  /// Opis od użytkownika, np. „Kolektor parowy, prefabrykacja".
  final String label;

  /// Etykieta rozmiaru do oferty, np. „DN100 Sch 40" (pusta, gdy wpisano
  /// wymiary ręcznie).
  final String sizeLabel;

  /// Średnica zewnętrzna (rura / króciec), mm.
  final double odMm;

  /// Grubość ścianki / blachy, mm.
  final double wallMm;

  /// Grubość obliczeniowa pachwiny a, mm.
  final double throatMm;

  /// Długość JEDNEJ spoiny blach, m.
  final double lengthM;

  /// Liczba takich spoin.
  final int count;

  final GrooveType groove;

  /// Kąt rowka CAŁKOWITY (V/X) albo kąt fazy króćca (½V), °.
  final double angleDeg;
  final double rootFaceMm;
  final double gapMm;

  /// Średnica rury głównej przy króćcu, mm (0 = nieznana).
  final double headerOdMm;

  final WeldPosition position;

  /// Schemat procesów tylko dla tej pozycji; `null` = schemat wyceny.
  final WeldScheme? scheme;

  /// Ręczny czas przygotowania (fazowanie, ustawienie, sczepianie) na
  /// jedną spoinę, min; `null` = automatyczny (patrz kalkulator).
  final double? prepMinutes;

  const QuoteJoint({
    required this.id,
    required this.kind,
    this.label = '',
    this.sizeLabel = '',
    this.odMm = 0,
    this.wallMm = 0,
    this.throatMm = 0,
    this.lengthM = 0,
    this.count = 1,
    this.groove = GrooveType.v,
    this.angleDeg = 60,
    this.rootFaceMm = 1.5,
    this.gapMm = 2.5,
    this.headerOdMm = 0,
    this.position = WeldPosition.pa,
    this.scheme,
    this.prepMinutes,
  });

  QuoteJoint copyWith({
    String? id,
    JointKind? kind,
    String? label,
    String? sizeLabel,
    double? odMm,
    double? wallMm,
    double? throatMm,
    double? lengthM,
    int? count,
    GrooveType? groove,
    double? angleDeg,
    double? rootFaceMm,
    double? gapMm,
    double? headerOdMm,
    WeldPosition? position,
    WeldScheme? Function()? scheme,
    double? Function()? prepMinutes,
  }) =>
      QuoteJoint(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        label: label ?? this.label,
        sizeLabel: sizeLabel ?? this.sizeLabel,
        odMm: odMm ?? this.odMm,
        wallMm: wallMm ?? this.wallMm,
        throatMm: throatMm ?? this.throatMm,
        lengthM: lengthM ?? this.lengthM,
        count: count ?? this.count,
        groove: groove ?? this.groove,
        angleDeg: angleDeg ?? this.angleDeg,
        rootFaceMm: rootFaceMm ?? this.rootFaceMm,
        gapMm: gapMm ?? this.gapMm,
        headerOdMm: headerOdMm ?? this.headerOdMm,
        position: position ?? this.position,
        scheme: scheme != null ? scheme() : this.scheme,
        prepMinutes: prepMinutes != null ? prepMinutes() : this.prepMinutes,
      );

  /// Pusta lista = pozycja da się policzyć. Klucze zrozumiałe dla UI.
  List<JointProblem> get problems {
    final out = <JointProblem>[];
    if (count < 1) out.add(JointProblem.count);
    if (kind.onPipe && !(odMm > 0)) out.add(JointProblem.od);
    if (kind.isFillet) {
      if (!(throatMm > 0)) out.add(JointProblem.throat);
    } else {
      if (!(wallMm > 0)) {
        out.add(JointProblem.wall);
      } else if (kind.onPipe && odMm > 0 && 2 * wallMm >= odMm) {
        out.add(JointProblem.wallVsOd);
      }
      // Rowek I nie ma progu (pole jest ukryte) — nie wolno blokować zapisu
      // wartością, której spawacz nie widzi.
      final usesRootFace =
          kind == JointKind.branch || groove != GrooveType.square;
      if (usesRootFace &&
          (rootFaceMm < 0 || (wallMm > 0 && rootFaceMm > wallMm))) {
        out.add(JointProblem.rootFace);
      }
      if (gapMm < 0) out.add(JointProblem.gap);
      // Króciec: kąt JEDNEJ fazy (tg β → ∞ przy 90°); rowek V/X: kąt
      // całkowity rowka.
      final maxAngle = kind == JointKind.branch ? 80.0 : 120.0;
      if (angleDeg < 0 || angleDeg > maxAngle) out.add(JointProblem.angle);
    }
    if (kind.hasLength && !(lengthM > 0)) out.add(JointProblem.length);
    if (prepMinutes != null && prepMinutes! < 0) out.add(JointProblem.prep);
    // Górne granice — literówka „114300” zamiast „114,3” nie może dać
    // absurdalnej ceny bez ostrzeżenia.
    if (count > 100000 ||
        odMm > 5000 ||
        headerOdMm > 5000 ||
        wallMm > 300 ||
        throatMm > 100 ||
        gapMm > 50 ||
        rootFaceMm > 100 ||
        lengthM > 10000 ||
        (prepMinutes ?? 0) > 6000) {
      out.add(JointProblem.outOfRange);
    }
    return out;
  }

  bool get isValid => problems.isEmpty;

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.code,
        'label': label,
        'size': sizeLabel,
        'od': odMm,
        't': wallMm,
        'a': throatMm,
        'len': lengthM,
        'n': count,
        'groove': groove.code,
        'angle': angleDeg,
        'c': rootFaceMm,
        'b': gapMm,
        'header': headerOdMm,
        'pos': position.code,
        'scheme': scheme?.code,
        'prep': prepMinutes,
      };

  static QuoteJoint fromJson(Map<String, Object?> j) => QuoteJoint(
        id: _str(j['id']),
        kind: JointKind.fromCode(_strOrNull(j['kind'])),
        label: _str(j['label']),
        sizeLabel: _str(j['size']),
        odMm: _num(j['od'], 0),
        wallMm: _num(j['t'], 0),
        throatMm: _num(j['a'], 0),
        lengthM: _num(j['len'], 0),
        count: (j['n'] is num) ? (j['n'] as num).toInt() : 1,
        groove: GrooveType.fromCode(_strOrNull(j['groove'])),
        angleDeg: _num(j['angle'], 60),
        rootFaceMm: _num(j['c'], 1.5),
        gapMm: _num(j['b'], 2.5),
        headerOdMm: _num(j['header'], 0),
        position: WeldPosition.fromCode(_strOrNull(j['pos'])),
        scheme: WeldScheme.fromCode(_strOrNull(j['scheme'])),
        prepMinutes: _numOrNull(j['prep']),
      );
}

enum JointProblem {
  count,
  od,
  wall,
  wallVsOd,
  throat,
  length,
  rootFace,
  gap,
  angle,
  prep,

  /// Wymiar albo liczba poza rozsądnym zakresem (literówka?).
  outOfRange,
}

/// Dodatkowa pozycja kosztorysu: dojazd, wynajem agregatu, materiał rur,
/// PWHT u podwykonawcy… Netto, bez narzutu? — patrz [withMarkup].
class QuoteExtra {
  final String id;
  final String description;
  final double quantity;

  /// „szt.", „km", „dzień", „m"…
  final String unit;

  /// Cena jednostkowa netto, zł.
  final double unitPrice;

  /// Czy pozycja dostaje narzut i marżę jak koszty własne (np. materiał
  /// kupowany przez Ciebie) — `false` dla kosztów przenoszonych 1:1.
  final bool withMarkup;

  const QuoteExtra({
    required this.id,
    this.description = '',
    this.quantity = 1,
    this.unit = 'szt.',
    this.unitPrice = 0,
    this.withMarkup = true,
  });

  QuoteExtra copyWith({
    String? description,
    double? quantity,
    String? unit,
    double? unitPrice,
    bool? withMarkup,
  }) =>
      QuoteExtra(
        id: id,
        description: description ?? this.description,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        unitPrice: unitPrice ?? this.unitPrice,
        withMarkup: withMarkup ?? this.withMarkup,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'desc': description,
        'qty': quantity,
        'unit': unit,
        'price': unitPrice,
        'markup': withMarkup,
      };

  static QuoteExtra fromJson(Map<String, Object?> j) => QuoteExtra(
        id: _str(j['id']),
        description: _str(j['desc']),
        quantity: _num(j['qty'], 1),
        unit: _str(j['unit']).isEmpty ? 'szt.' : _str(j['unit']),
        unitPrice: _num(j['price'], 0),
        withMarkup: j['markup'] is bool ? j['markup'] as bool : true,
      );
}

/// Badanie nieniszczące: jaki procent złączy i za ile jedno.
class NdtRate {
  final double percent;

  /// Cena netto za jedno badane złącze, zł.
  final double pricePerJoint;

  const NdtRate({this.percent = 0, this.pricePerJoint = 0});

  NdtRate copyWith({double? percent, double? pricePerJoint}) => NdtRate(
        percent: percent ?? this.percent,
        pricePerJoint: pricePerJoint ?? this.pricePerJoint,
      );

  Map<String, Object?> toJson() => {'pct': percent, 'price': pricePerJoint};

  static NdtRate fromJson(Object? raw) {
    if (raw is! Map) return const NdtRate();
    return NdtRate(
      percent: _num(raw['pct'], 0).clamp(0, 100).toDouble(),
      pricePerJoint: _num(raw['price'], 0),
    );
  }
}

/// Metody NDT w wycenie.
enum NdtMethod {
  rt('RT', 'Radiografia', 'Radiography'),
  ut('UT', 'Ultradźwięki', 'Ultrasonic'),
  pt('PT', 'Penetranty', 'Dye penetrant'),
  mt('MT', 'Magnetyczno-proszkowe', 'Magnetic particle');

  const NdtMethod(this.code, this.labelPl, this.labelEn);
  final String code;
  final String labelPl;
  final String labelEn;
}

/// Stawki i ceny — kopia w każdej wycenie.
class QuoteRates {
  /// Stawka spawacza, zł/h netto.
  final double welderRate;

  /// Stawka montera (przygotowanie, ustawienie, sczepianie), zł/h netto.
  final double fitterRate;

  /// Cena spoiwa per proces, zł/kg netto.
  final Map<QuoteProcess, double> fillerPrices;

  /// Argon (TIG, MIG), zł/m³.
  final double argonPrice;

  /// Mieszanka M21 / CO₂ (MAG, FCAW), zł/m³.
  final double mixPrice;

  /// Gaz formujący (argon, azot, formier), zł/m³.
  final double purgeGasPrice;

  /// Topnik SAW, zł/kg.
  final double fluxPrice;

  /// Energia elektryczna, zł/kWh.
  final double electricityPrice;

  /// m³ gazu w jednej butli (50 L × 200 bar ≈ 10 m³) — tylko do podania
  /// liczby butli.
  final double cylinderM3;

  /// Koszty ogólne (narzut na koszty bezpośrednie), %.
  final double overheadPct;

  /// Zysk (od kosztów z narzutem), %.
  final double marginPct;

  final QuoteVat vat;

  final Map<NdtMethod, NdtRate> ndt;

  /// Nadpisane założenia procesów (brak klucza = domyślne).
  final Map<QuoteProcess, ProcessProfile> profiles;

  /// Formowanie: odległość między przegrodami (długość formowanej części),
  /// mm, i docelowe O₂ (ppm) — liczba wymian objętości N = ln(C₀/cel).
  final double purgeLengthMm;
  final double purgeTargetPpm;

  /// Rynkowa stawka za cal-średnicę (zł/DI) do porównania — 0 = brak.
  final double marketDiRate;

  /// Lista zakupów: kg spoiwa w opakowaniu per proces (brak klucza =
  /// [kDefaultPackKg]) i zapas ponad wyliczone zużycie, %.
  final Map<QuoteProcess, double> packKg;
  final double stockReservePct;

  const QuoteRates({
    this.welderRate = 90,
    this.fitterRate = 75,
    this.fillerPrices = const {},
    this.argonPrice = 30,
    this.mixPrice = 25,
    this.purgeGasPrice = 30,
    this.fluxPrice = 12,
    this.electricityPrice = 1.1,
    this.cylinderM3 = 10,
    this.overheadPct = 15,
    this.marginPct = 10,
    this.vat = QuoteVat.vat23,
    this.ndt = const {},
    this.profiles = const {},
    this.purgeLengthMm = 400,
    this.purgeTargetPpm = 100,
    this.marketDiRate = 0,
    this.packKg = const {},
    this.stockReservePct = 10,
  });

  /// Stawki startowe dla materiału: ceny spoiw z [kDefaultFillerPrices],
  /// potem nadpisane cenami zapamiętanymi przez użytkownika.
  factory QuoteRates.defaultsFor(QuoteMaterial material,
      {QuoteRates? base, Map<QuoteProcess, double>? savedFillerPrices}) {
    final b = base ?? const QuoteRates();
    return b.copyWith(fillerPrices: {
      ...kDefaultFillerPrices[material]!,
      ...?savedFillerPrices,
    });
  }

  ProcessProfile profileOf(QuoteProcess p) =>
      profiles[p] ?? kDefaultProcessProfiles[p]!;

  double fillerPriceOf(QuoteProcess p) => fillerPrices[p] ?? 0;

  double packKgOf(QuoteProcess p) => packKg[p] ?? kDefaultPackKg[p]!;

  NdtRate ndtOf(NdtMethod m) => ndt[m] ?? const NdtRate();

  /// Cena gazu osłonowego danego rodzaju, zł/m³.
  double shieldGasPrice(QuoteGasKind kind) => switch (kind) {
        QuoteGasKind.argon => argonPrice,
        QuoteGasKind.mix => mixPrice,
        QuoteGasKind.none => 0,
      };

  QuoteRates copyWith({
    double? welderRate,
    double? fitterRate,
    Map<QuoteProcess, double>? fillerPrices,
    double? argonPrice,
    double? mixPrice,
    double? purgeGasPrice,
    double? fluxPrice,
    double? electricityPrice,
    double? cylinderM3,
    double? overheadPct,
    double? marginPct,
    QuoteVat? vat,
    Map<NdtMethod, NdtRate>? ndt,
    Map<QuoteProcess, ProcessProfile>? profiles,
    double? purgeLengthMm,
    double? purgeTargetPpm,
    double? marketDiRate,
    Map<QuoteProcess, double>? packKg,
    double? stockReservePct,
  }) =>
      QuoteRates(
        welderRate: welderRate ?? this.welderRate,
        fitterRate: fitterRate ?? this.fitterRate,
        fillerPrices: fillerPrices ?? this.fillerPrices,
        argonPrice: argonPrice ?? this.argonPrice,
        mixPrice: mixPrice ?? this.mixPrice,
        purgeGasPrice: purgeGasPrice ?? this.purgeGasPrice,
        fluxPrice: fluxPrice ?? this.fluxPrice,
        electricityPrice: electricityPrice ?? this.electricityPrice,
        cylinderM3: cylinderM3 ?? this.cylinderM3,
        overheadPct: overheadPct ?? this.overheadPct,
        marginPct: marginPct ?? this.marginPct,
        vat: vat ?? this.vat,
        ndt: ndt ?? this.ndt,
        profiles: profiles ?? this.profiles,
        purgeLengthMm: purgeLengthMm ?? this.purgeLengthMm,
        purgeTargetPpm: purgeTargetPpm ?? this.purgeTargetPpm,
        marketDiRate: marketDiRate ?? this.marketDiRate,
        packKg: packKg ?? this.packKg,
        stockReservePct: stockReservePct ?? this.stockReservePct,
      );

  Map<String, Object?> toJson() => {
        'welder': welderRate,
        'fitter': fitterRate,
        'filler': {
          for (final e in fillerPrices.entries) e.key.code: e.value,
        },
        'argon': argonPrice,
        'mix': mixPrice,
        'purge': purgeGasPrice,
        'flux': fluxPrice,
        'kwh': electricityPrice,
        'cyl': cylinderM3,
        'overhead': overheadPct,
        'margin': marginPct,
        'vat': vat.code,
        'ndt': {for (final e in ndt.entries) e.key.code: e.value.toJson()},
        'profiles': {
          for (final e in profiles.entries) e.key.code: e.value.toJson(),
        },
        'purgeLen': purgeLengthMm,
        'purgePpm': purgeTargetPpm,
        'diRate': marketDiRate,
        'packs': {for (final e in packKg.entries) e.key.code: e.value},
        'stock': stockReservePct,
      };

  static QuoteRates fromJson(Object? raw) {
    if (raw is! Map) return const QuoteRates();
    const d = QuoteRates();
    final filler = <QuoteProcess, double>{};
    final fr = raw['filler'];
    if (fr is Map) {
      for (final e in fr.entries) {
        final p = QuoteProcess.fromCode(_strOrNull(e.key));
        if (p != null && e.value is num && (e.value as num).isFinite) {
          filler[p] = (e.value as num).toDouble();
        }
      }
    }
    final ndt = <NdtMethod, NdtRate>{};
    final nr = raw['ndt'];
    if (nr is Map) {
      for (final m in NdtMethod.values) {
        if (nr.containsKey(m.code)) ndt[m] = NdtRate.fromJson(nr[m.code]);
      }
    }
    final profiles = <QuoteProcess, ProcessProfile>{};
    final pr = raw['profiles'];
    if (pr is Map) {
      for (final e in pr.entries) {
        final p = QuoteProcess.fromCode(_strOrNull(e.key));
        if (p == null) continue;
        profiles[p] =
            ProcessProfile.fromJson(e.value, kDefaultProcessProfiles[p]!);
      }
    }
    final packs = <QuoteProcess, double>{};
    final pk = raw['packs'];
    if (pk is Map) {
      for (final e in pk.entries) {
        final p = QuoteProcess.fromCode(_strOrNull(e.key));
        final v = e.value;
        if (p != null && v is num && v.isFinite && v > 0) {
          packs[p] = v.toDouble();
        }
      }
    }
    return QuoteRates(
      welderRate: _num(raw['welder'], d.welderRate),
      fitterRate: _num(raw['fitter'], d.fitterRate),
      fillerPrices: filler,
      argonPrice: _num(raw['argon'], d.argonPrice),
      mixPrice: _num(raw['mix'], d.mixPrice),
      purgeGasPrice: _num(raw['purge'], d.purgeGasPrice),
      fluxPrice: _num(raw['flux'], d.fluxPrice),
      electricityPrice: _num(raw['kwh'], d.electricityPrice),
      cylinderM3: _num(raw['cyl'], d.cylinderM3),
      overheadPct: _num(raw['overhead'], d.overheadPct),
      marginPct: _num(raw['margin'], d.marginPct),
      vat: QuoteVat.fromCode(_strOrNull(raw['vat'])),
      ndt: ndt,
      profiles: profiles,
      purgeLengthMm: _num(raw['purgeLen'], d.purgeLengthMm),
      purgeTargetPpm: _num(raw['purgePpm'], d.purgeTargetPpm),
      marketDiRate: _num(raw['diRate'], d.marketDiRate),
      packKg: packs,
      stockReservePct: _num(raw['stock'], d.stockReservePct),
    );
  }
}

/// Status oferty — do listy i filtrowania.
enum QuoteStatus {
  draft('DRAFT', 'Szkic', 'Draft'),
  sent('SENT', 'Wysłana', 'Sent'),
  accepted('ACCEPTED', 'Przyjęta', 'Accepted'),
  rejected('REJECTED', 'Odrzucona', 'Rejected');

  const QuoteStatus(this.code, this.labelPl, this.labelEn);
  final String code;
  final String labelPl;
  final String labelEn;

  static QuoteStatus fromCode(String? code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return draft;
  }
}

class WeldQuote {
  final String id;

  /// Numer oferty, np. „WYC/2026/007".
  final String number;

  /// Przedmiot wyceny, np. „Prefabrykacja kolektora DN200".
  final String title;
  final String client;
  final String notes;

  /// Ważność oferty w dniach.
  final int validityDays;

  final QuoteMaterial material;
  final WeldScheme scheme;
  final QuoteSite site;

  /// Formowanie grani gazem (złącza na rurach).
  final bool purge;

  /// Liczba spawaczy w brygadzie — tylko do czasu realizacji w dniach.
  final int crew;

  final QuoteStatus status;
  final QuoteRates rates;
  final List<QuoteJoint> joints;
  final List<QuoteExtra> extras;

  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  const WeldQuote({
    required this.id,
    this.number = '',
    this.title = '',
    this.client = '',
    this.notes = '',
    this.validityDays = 30,
    this.material = QuoteMaterial.carbon,
    this.scheme =
        const WeldScheme(root: QuoteProcess.tig, fill: QuoteProcess.mma),
    this.site = QuoteSite.shop,
    this.purge = false,
    this.crew = 1,
    this.status = QuoteStatus.draft,
    this.rates = const QuoteRates(),
    this.joints = const [],
    this.extras = const [],
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  WeldQuote copyWith({
    String? number,
    String? title,
    String? client,
    String? notes,
    int? validityDays,
    QuoteMaterial? material,
    WeldScheme? scheme,
    QuoteSite? site,
    bool? purge,
    int? crew,
    QuoteStatus? status,
    QuoteRates? rates,
    List<QuoteJoint>? joints,
    List<QuoteExtra>? extras,
    int? createdAt,
    int? updatedAt,
    int? Function()? deletedAt,
    String? id,
  }) =>
      WeldQuote(
        id: id ?? this.id,
        number: number ?? this.number,
        title: title ?? this.title,
        client: client ?? this.client,
        notes: notes ?? this.notes,
        validityDays: validityDays ?? this.validityDays,
        material: material ?? this.material,
        scheme: scheme ?? this.scheme,
        site: site ?? this.site,
        purge: purge ?? this.purge,
        crew: crew ?? this.crew,
        status: status ?? this.status,
        rates: rates ?? this.rates,
        joints: joints ?? this.joints,
        extras: extras ?? this.extras,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );

  /// Treść wyceny (bez kolumn indeksowych) — kolumna `data_json`.
  Map<String, Object?> toJson() => {
        'v': 1,
        'notes': notes,
        'validity': validityDays,
        'material': material.code,
        'scheme': scheme.code,
        'site': site.code,
        'purge': purge,
        'crew': crew,
        'rates': rates.toJson(),
        'joints': [for (final j in joints) j.toJson()],
        'extras': [for (final e in extras) e.toJson()],
      };

  /// Wiersz tabeli `weld_quotes`. Sumy netto/brutto (grosze) podaje
  /// wywołujący z kalkulatora — lista ofert pokazuje je bez przeliczania.
  Map<String, Object?> toRow(
          {required int netGrosze, required int grossGrosze}) =>
      {
        'id': id,
        'number': number,
        'title': title,
        'client': client,
        'status': status.code,
        'data_json': jsonEncode(toJson()),
        'net_grosze': netGrosze,
        'gross_grosze': grossGrosze,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  static WeldQuote fromRow(Map<String, Object?> r) {
    Map<String, Object?> data = const {};
    final raw = r['data_json'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, Object?>) data = decoded;
      } on FormatException {
        // Uszkodzony JSON: wycena otworzy się pusta, a nagłówek zostaje.
      }
    }
    final joints = <QuoteJoint>[];
    final jr = data['joints'];
    if (jr is List) {
      for (final j in jr) {
        if (j is Map<String, Object?>) joints.add(QuoteJoint.fromJson(j));
      }
    }
    final extras = <QuoteExtra>[];
    final er = data['extras'];
    if (er is List) {
      for (final e in er) {
        if (e is Map<String, Object?>) extras.add(QuoteExtra.fromJson(e));
      }
    }
    return WeldQuote(
      id: r['id'] as String,
      number: _str(r['number']),
      title: _str(r['title']),
      client: _str(r['client']),
      status: QuoteStatus.fromCode(_strOrNull(r['status'])),
      notes: _str(data['notes']),
      validityDays:
          (data['validity'] is num) ? (data['validity'] as num).toInt() : 30,
      material: QuoteMaterial.fromCode(_strOrNull(data['material'])),
      scheme: WeldScheme.fromCode(_strOrNull(data['scheme'])) ??
          const WeldScheme(root: QuoteProcess.tig, fill: QuoteProcess.mma),
      site: QuoteSite.fromCode(_strOrNull(data['site'])),
      purge: data['purge'] == true,
      crew: (data['crew'] is num)
          ? (data['crew'] as num).toInt().clamp(1, 99)
          : 1,
      rates: QuoteRates.fromJson(data['rates']),
      joints: joints,
      extras: extras,
      createdAt: (r['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (r['updated_at'] as num?)?.toInt() ?? 0,
      deletedAt: (r['deleted_at'] as num?)?.toInt(),
    );
  }
}

/// Następny numer oferty w roku: „WYC/2026/001", „WYC/2026/002"… —
/// największy istniejący numer tego roku + 1 (dziury po usuniętych nie są
/// zapełniane, żeby numer nie wrócił na inną ofertę).
String nextQuoteNumber(Iterable<String> existing, int year,
    {String prefix = 'WYC'}) {
  final re = RegExp('^${RegExp.escape(prefix)}/$year/(\\d+)\$');
  var max = 0;
  for (final n in existing) {
    final m = re.firstMatch(n.trim());
    if (m == null) continue;
    final v = int.parse(m.group(1)!);
    if (v > max) max = v;
  }
  return '$prefix/$year/${(max + 1).toString().padLeft(3, '0')}';
}
