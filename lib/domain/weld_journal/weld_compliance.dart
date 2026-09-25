/// Dziennik spoin ↔ biblioteka WPS i rejestr uprawnień spawacza.
///
/// Spoina z dziennika trzyma wszystko jako tekst (wolny albo z list
/// wyboru), a kontrola zakresu (`lib/domain/wps/weld_range_check.dart`)
/// potrzebuje liczb i słowników. Tu jest przekład jednego na drugie oraz
/// wynik kontroli w postaci, którą pokazuje karta spoiny, lista dziennika
/// i historia zmian.
///
/// Zasady (takie jak w kontroli zakresu):
///  • brak danych ≠ niezgodność — pole spoiny, którego nie da się jednoznacznie
///    przełożyć, nie jest sprawdzane;
///  • brak WPS w bibliotece albo brak certyfikatów w rejestrze to INFORMACJA,
///    nie ostrzeżenie — spawacz, który nie prowadzi biblioteki, nie dostaje
///    alarmu przy każdej spoinie;
///  • ostrzeżenie nie blokuje zapisu — decyduje spawacz, a decyzja trafia do
///    historii spoiny.
///
/// Energia liniowa: kolumna `heat_input` (v20) jest tekstem bez konwencji.
/// Konwencję (EN 1011-1 z k / ASME IX bez k) dopisujemy do tekstu
/// („1,25 EN", „0,8 ASME") — bez zmiany schematu bazy, czytelnie w CSV / PDF
/// i zgodnie wstecz: stara wartość bez dopisku to „konwencja nieznana".
///
/// Czysty Dart: bez Fluttera i bez bazy.
library;

import '../qualification/certificate_status.dart';
import '../qualification/journal_welds.dart';
import '../qualification/qualification_dates.dart';
import '../qualification/weld_process.dart';
import '../qualification/welder_certificate.dart';
import '../welding/heat_input.dart';
import '../wps/weld_range_check.dart';
import '../wps/wps_record.dart';
import 'weld_entry.dart';

// ─── Energia liniowa z konwencją ────────────────────────────────────────────

/// Liczba z pola „kJ/mm" i konwencja, w której ją policzono.
class HeatInputText {
  /// Sama liczba, tak jak ją wpisano („1,25").
  final String number;

  /// `null` = konwencja nieznana (wpis sprzed tej wersji albo nie wybrano).
  final HeatInputStandard? method;

  const HeatInputText(this.number, this.method);
}

final RegExp _kHeatInputSuffix =
    RegExp(r'^(.*?)[\s(]*\b(EN|ASME)\b\)?\s*$', caseSensitive: false);

/// „1,25 EN" → (1,25, EN 1011-1); „0.8 ASME" → (0.8, ASME IX); „1.2" →
/// (1.2, nieznana).
HeatInputText splitHeatInput(String raw) {
  final text = raw.trim();
  final m = _kHeatInputSuffix.firstMatch(text);
  if (m == null) return HeatInputText(text, null);
  return HeatInputText(
      m.group(1)!.trim(), heatInputMethodFromCode(m.group(2)));
}

/// Odwrotność [splitHeatInput]. Pusta liczba → pusty tekst (sama konwencja
/// bez wartości nic inspektorowi nie mówi).
String joinHeatInput(String number, HeatInputStandard? method) {
  final n = number.trim();
  if (n.isEmpty) return '';
  return method == null ? n : '$n ${heatInputMethodCode(method)}';
}

// ─── Przekład pól dziennika ─────────────────────────────────────────────────

/// Typ złącza dziennika → rodzaj spoiny uprawnienia / WPS.
///
/// BW → BW. FW i SW (kielichowe — spoina pachwinowa wg ISO 9606-1 i ASME
/// B31.3 fig. 328.5.2C) → FW. Odgałęzienie bywa czołowe (pełny przetop)
/// albo pachwinowe — bez zgadywania: `null`.
WeldJointKind? jointKindOfWeld(String jointType) =>
    switch (jointType.trim().toUpperCase()) {
      WeldJointType.butt => WeldJointKind.bw,
      WeldJointType.fillet || WeldJointType.socket => WeldJointKind.fw,
      _ => null,
    };

final RegExp _kGroupCode = RegExp(r'^P?\d{1,2}(?:\.\d{1,2})?$');

/// Grupa materiałowa z pola „Materiał", ale TYLKO gdy spawacz wpisał grupę
/// („8.1", „P8", „1 + 8.1"). Gatunek („316L", „P265GH", „1.4404") to nie
/// grupa — tabeli gatunek → ISO/TR 15608 nie odtwarzamy, więc takiego
/// materiału nie porównujemy.
String? materialGroupOfWeld(String material) {
  final text = material.trim();
  if (text.isEmpty) return null;
  final parts = text.split('+').map(normalizeMaterialGroupToken).toList();
  if (parts.any((p) => !_kGroupCode.hasMatch(p))) return null;
  return text;
}

String? _nonEmpty(String s) {
  final t = s.trim();
  return t.isEmpty ? null : t;
}

/// Parametry spoiny z wpisu dziennika — do [checkWeldAgainstWps] i
/// [checkWelderCoverage].
WeldParameters weldParametersOf(WeldEntry e) {
  final hi = splitHeatInput(e.heatInput);
  return WeldParameters(
    thicknessMm: WeldParameters.parseNumber(e.t),
    outsideDiameterMm: WeldParameters.parseNumber(e.od),
    materialGroup: materialGroupOfWeld(e.material),
    process: _nonEmpty(e.method),
    position: _nonEmpty(e.position),
    jointKind: jointKindOfWeld(e.jointType),
    heatInputKjMm: WeldParameters.parseNumber(hi.number),
    heatInputMethod: hi.method,
    preheatC: WeldParameters.parseNumber(e.preheatC),
    interpassC: WeldParameters.parseNumber(e.interpassC),
  );
}

/// Dzień spawania; data nieczytelna → [fallback] (zwykle dziś).
DateTime weldDateOf(WeldEntry e, {required DateTime fallback}) =>
    parseFlexibleDate(e.date) ?? dateOnly(fallback);

/// Tekst, który dziennik zapisuje w `wps_ref` po wyborze WPS z biblioteki.
String wpsRefOf(WpsRecord wps) => wps.displayName;

String _key(String s) => s.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

/// WPS z [library], na którą wskazuje wpis dziennika: najpierw po [wpsId]
/// (wybrana z listy w tej sesji edytora), potem po pełnej nazwie z rewizją
/// („WPS-141-01 rev. B"), na końcu po samym numerze (stary wolny tekst) —
/// przy kilku rewizjach najnowsza zapisana, tak jak `WpsDao.findByNumber`.
WpsRecord? resolveWpsRef(
  String wpsRef,
  Iterable<WpsRecord> library, {
  String? wpsId,
}) {
  if (wpsId != null && wpsId.isNotEmpty) {
    for (final w in library) {
      if (w.id == wpsId) return w;
    }
  }
  final ref = _key(wpsRef);
  if (ref.isEmpty) return null;
  WpsRecord? newest(Iterable<WpsRecord> xs) {
    WpsRecord? best;
    for (final w in xs) {
      if (best == null || w.updatedAt > best.updatedAt) best = w;
    }
    return best;
  }

  return newest(library.where((w) => _key(w.displayName) == ref)) ??
      newest(library.where((w) => _key(w.wpsNo) == ref));
}

// ─── Wynik kontroli ─────────────────────────────────────────────────────────

/// Uprawnienia jednego stempla przy spoinie.
class WelderStampCoverage {
  /// Stempel ze spoiny; pusty, gdy spoina nie ma stempla i sprawdzono
  /// domyślnego spawacza telefonu.
  final String stamp;
  final WelderCoverage coverage;

  const WelderStampCoverage(this.stamp, this.coverage);

  /// Są certyfikaty, ale żaden nie obejmował spoiny w dniu spawania.
  bool get notQualified => !coverage.noCertificates && !coverage.covered;
}

/// Wynik kontroli spoiny z dziennika: WPS + uprawnienia każdego stempla.
class WeldCompliance {
  /// Tekst z pola WPS spoiny (może być pusty).
  final String wpsRef;

  /// WPS z biblioteki, którą sprawdzono; `null` = brak / nie znaleziono.
  final WpsRecord? wps;
  final List<RangeIssue> wpsIssues;
  final List<WelderStampCoverage> welders;
  final DateTime weldDate;

  const WeldCompliance({
    required this.wpsRef,
    required this.wps,
    required this.wpsIssues,
    required this.welders,
    required this.weldDate,
  });

  /// Spoina POZA zakresem WPS (co najmniej jeden parametr poza zakresem).
  bool get outsideWps =>
      wpsIssues.any((i) => i.severity == RangeIssueSeverity.outOfRange);

  /// Coś w WPS do wyjaśnienia (np. energia w innej konwencji) — bez
  /// stwierdzonej niezgodności.
  bool get wpsNeedsReview => !outsideWps && wpsIssues.isNotEmpty;

  /// Któryś spawacz spoiny nie miał w dniu spawania ważnego uprawnienia,
  /// które ją obejmuje.
  bool get welderNotQualified => welders.any((w) => w.notQualified);

  /// Jest o czym ostrzec przed zapisem.
  bool get hasWarnings => wpsIssues.isNotEmpty || welderNotQualified;

  /// Pole WPS wypełnione, ale takiej WPS nie ma w bibliotece.
  bool get wpsNotInLibrary => wps == null && wpsRef.trim().isNotEmpty;

  /// Punkty ostrzeżenia — po jednym na niezgodność.
  List<String> warningLines({required bool en}) {
    final out = <String>[];
    final w = wps;
    if (w != null) {
      for (final i in wpsIssues) {
        out.add('WPS ${w.displayName} — ${en ? i.messageEn : i.messagePl}');
      }
    }
    final day = formatIsoDate(weldDate);
    for (final s in welders.where((s) => s.notQualified)) {
      final who = s.stamp.isEmpty ? (en ? 'welder' : 'spawacz') : s.stamp;
      out.add(en
          ? 'Welder $who: no valid qualification covering this weld on $day.'
          : 'Spawacz $who: brak ważnego uprawnienia obejmującego tę spoinę '
              'w dniu $day.');
      final closest = s.coverage.closestCertificate;
      if (closest != null) {
        final no = closest.certificate.certNo?.trim();
        final label = (no == null || no.isEmpty)
            ? (en ? 'closest certificate' : 'najbliższy certyfikat')
            : (en ? 'certificate $no' : 'certyfikat $no');
        for (final i in closest.issues) {
          out.add('  $label — ${en ? i.messageEn : i.messagePl}');
        }
      }
    }
    return out;
  }

  /// Łagodne informacje: czego NIE sprawdzono i dlaczego.
  List<String> infoLines({required bool en}) {
    final out = <String>[];
    if (wpsRef.trim().isEmpty) {
      out.add(en
          ? 'No WPS chosen — the weld was not checked against a WPS.'
          : 'Nie wybrano WPS — spoiny nie porównano z WPS.');
    } else if (wps == null) {
      out.add(en
          ? 'WPS "${wpsRef.trim()}" is not in the WPS library — range not '
              'checked.'
          : 'WPS „${wpsRef.trim()}" nie ma w Bibliotece WPS — zakresu nie '
              'sprawdzono.');
    }
    for (final s in welders.where((s) => s.coverage.noCertificates)) {
      final who = s.stamp.isEmpty ? '' : ' ${s.stamp}';
      out.add(en
          ? 'No certificates of welder$who in the qualification register — '
              'qualification not checked.'
          : 'Brak certyfikatów spawacza$who w rejestrze uprawnień — '
              'uprawnień nie sprawdzono.');
    }
    return out;
  }

  /// Informacje na karcie spoiny — bez „nie wybrano WPS" i bez „brak
  /// certyfikatów" przy spoinie bez WPS: spawacz, który nie prowadzi
  /// biblioteki ani rejestru, nie ma ich widzieć na każdej karcie.
  List<String> cardInfoLines({required bool en}) {
    if (wpsRef.trim().isEmpty) return const <String>[];
    return infoLines(en: en);
  }

  /// Wpis do historii spoiny, gdy spawacz zapisał mimo ostrzeżenia.
  String historyText({required bool en}) => [
        en ? 'Saved despite warnings:' : 'Zapisano mimo ostrzeżeń:',
        ...warningLines(en: en).map((l) => l.startsWith('  ') ? l : '• $l'),
      ].join('\n');
}

/// Stemple do sprawdzenia: spawacz, grań, lico (bez powtórzeń); spoina bez
/// stempla → jeden wpis pusty (domyślny spawacz telefonu).
List<String> stampsToCheck(WeldEntry e) =>
    e.stamps.isEmpty ? const <String>[''] : e.stamps;

/// Certyfikaty stempla [stamp] — ta sama reguła co
/// `WelderQualificationService.checkWeld`: certyfikat bez stempla należy do
/// spawacza telefonu i liczy się dla każdego stempla.
List<WelderCertificate> certificatesForStamp(
  Iterable<WelderCertificate> certificates,
  String? stamp,
) {
  final key = stamp?.trim().toUpperCase();
  return certificates
      .where((c) =>
          c.welderStamp == null ||
          key == null ||
          key.isEmpty ||
          c.welderStamp!.trim().toUpperCase() == key)
      .toList();
}

/// Kontrola spoiny na danych w pamięci — dla listy dziennika (jedno
/// wczytanie biblioteki i rejestru na całą listę). Wynik taki sam jak
/// z `WelderQualificationService.checkWeld` dla każdego stempla.
///
/// [journalRows] — wiersze `weld_journal` (do ciągłości ASME);
/// [defaultStamp] — stempel telefonu dla spoiny bez stempla.
WeldCompliance assessWeldCompliance({
  required WeldEntry entry,
  required Iterable<WpsRecord> wpsLibrary,
  required Iterable<WelderCertificate> certificates,
  Iterable<Map<String, Object?>> journalRows = const [],
  String? defaultStamp,
  String? wpsId,
  required DateTime today,
  Map<String, List<JournalWeld>>? journalCache,
}) {
  final weld = weldParametersOf(entry);
  final date = weldDateOf(entry, fallback: today);
  final wps = resolveWpsRef(entry.wpsRef, wpsLibrary, wpsId: wpsId);
  final certList = certificates.toList(growable: false);
  final welders = <WelderStampCoverage>[];
  for (final s in stampsToCheck(entry)) {
    final stamp = s.isEmpty ? defaultStamp : s;
    final key = stamp?.trim().toUpperCase() ?? '';
    // Daty po dniu spawania ignoruje evaluateCertificate — jedna lista na
    // stempel wystarcza dla całego dziennika.
    final journal = journalCache == null
        ? journalWeldsFromRows(journalRows, stamp: stamp, today: _kFarFuture)
        : (journalCache[key] ??= journalWeldsFromRows(journalRows,
            stamp: stamp, today: _kFarFuture));
    welders.add(WelderStampCoverage(
      s,
      checkWelderCoverage(
        weld: weld,
        weldDate: date,
        certificates: certificatesForStamp(certList, stamp),
        journal: journal,
      ),
    ));
  }
  return WeldCompliance(
    wpsRef: entry.wpsRef,
    wps: wps,
    wpsIssues:
        wps == null ? const <RangeIssue>[] : checkWeldAgainstWps(weld, wps),
    welders: welders,
    weldDate: date,
  );
}

final DateTime _kFarFuture = DateTime(2100, 12, 31);
