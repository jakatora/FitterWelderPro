// Instrukcja technologiczna spawania (WPS) w bibliotece spawacza — tabela
// `wps_library` (schemat v21) i format wymiany JSON między spawaczami brygady.
//
// WPS ≠ WPQR. WPS mówi JAK spawać (zakresy parametrów); WPQR (EN ISO 15614-1)
// albo PQR (ASME IX) to protokół, który tę technologię zakwalifikował —
// tu tylko numer w polu [WpsRecord.pqrRef]. Uprawnienie spawacza (ISO 9606-1 /
// ASME WPQ) to jeszcze co innego i żyje w rejestrze uprawnień.
//
// Zakres energii liniowej jest zawsze w kJ/mm, a [WpsRecord.heatInputMethod]
// mówi, w której konwencji go liczono: EN 1011-1 (Q = k·U·I·60/v, ze
// sprawnością cieplną k) albo ASME IX QW-409.1 (bez k). Te same parametry
// dają w obu konwencjach różne liczby, więc porównanie spoiny z zakresem WPS
// ma sens tylko w tej samej konwencji — lib/domain/welding/heat_input.dart.

import 'dart:convert';

import '../../utils/decimal_parse.dart';
import '../qualification/weld_process.dart';
import '../welding/heat_input.dart';

/// Norma kwalifikowania procedury.
enum WpsStandard {
  iso15614_1('ISO_15614_1', 'EN ISO 15614-1', 'EN ISO 15614-1'),
  asmeIx('ASME_IX', 'ASME IX (PQR)', 'ASME IX (PQR)'),
  other('OTHER', 'Inna', 'Other');

  const WpsStandard(this.code, this.labelPl, this.labelEn);

  final String code;
  final String labelPl;
  final String labelEn;

  static WpsStandard fromCode(String? raw) {
    for (final s in WpsStandard.values) {
      if (s.code == raw) return s;
    }
    return WpsStandard.other;
  }
}

/// Status dokumentu WPS (v25). Pusty = nie podano (wpis sprzed v25) —
/// traktowany jak zatwierdzona, bez ostrzeżeń.
enum WpsDocStatus {
  unknown('', '—', '—'),

  /// pWPS — wstępna instrukcja, jeszcze bez WPQR/PQR (ISO 15614-1 §3).
  /// Wolno nią spawać tylko złącze próbne kwalifikacji.
  preliminary('PWPS', 'pWPS (niezakwalifikowana)', 'pWPS (not qualified)'),

  /// Zatwierdzona, obowiązująca.
  approved('APPROVED', 'Zatwierdzona', 'Approved'),

  /// Wycofana — nie wolno nią spawać nowych złączy.
  withdrawn('WITHDRAWN', 'Wycofana', 'Withdrawn');

  const WpsDocStatus(this.code, this.labelPl, this.labelEn);
  final String code;
  final String labelPl;
  final String labelEn;

  static WpsDocStatus fromCode(String? raw) {
    final v = raw?.trim().toUpperCase() ?? '';
    for (final s in WpsDocStatus.values) {
      if (s.code == v) return s;
    }
    return WpsDocStatus.unknown;
  }
}

/// Kod konwencji energii liniowej w bazie i w JSON-ie.
String heatInputMethodCode(HeatInputStandard m) => switch (m) {
      HeatInputStandard.en1011 => 'EN',
      HeatInputStandard.asmeIx => 'ASME',
    };

HeatInputStandard? heatInputMethodFromCode(String? raw) =>
    switch (raw?.trim().toUpperCase()) {
      'EN' => HeatInputStandard.en1011,
      'ASME' => HeatInputStandard.asmeIx,
      _ => null,
    };

double? _num(Object? v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String) return parseDecimal(v);
  return null;
}

String _text(Object? v) => v is String ? v : '';

String? _nullableText(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

class WpsRecord {
  final String id;

  /// Numer WPS — wymagany.
  final String wpsNo;
  final String revision;
  final WpsStandard standard;

  /// Numer WPQR (ISO 15614-1) / PQR (ASME IX), który kwalifikuje tę WPS.
  final String pqrRef;

  /// Proces(y): numery EN ISO 4063 albo nazwy.
  final String processes;

  /// Grupa(y) materiałowe: ISO/TR 15608 („8.1") albo P-No („P8"); kilka
  /// oddzielonych przecinkiem, złącze różnoimienne jako „1 + 8.1".
  final String materialGroup;

  final double? thicknessMinMm;
  final double? thicknessMaxMm;
  final double? diameterMinMm;
  final double? diameterMaxMm;

  /// Pozycje dopuszczone przez WPS („PA, PC, PF" albo „wszystkie").
  final String positions;
  final Set<WeldJointKind> jointKinds;

  /// Spoiwo (np. „ER316LSi Ø2,4").
  final String filler;

  /// Gaz osłonowy (np. „I1 — Ar 99,996 %").
  final String shieldingGas;

  /// Gaz formujący (np. „N2 + 10 % H2").
  final String backingGas;

  final double? preheatMinC;
  final double? interpassMaxC;

  /// Zakres energii liniowej w kJ/mm w konwencji [heatInputMethod].
  final double? heatInputMinKjMm;
  final double? heatInputMaxKjMm;
  final HeatInputStandard heatInputMethod;

  /// Obróbka cieplna po spawaniu (tekst z WPS, np. „brak" / „620 °C 1 h").
  final String pwht;
  final String notes;

  /// Status dokumentu (v25): pWPS / zatwierdzona / wycofana.
  final WpsDocStatus docStatus;

  /// Kopia pliku WPS (PDF / zdjęcie) w `<documents>/heat_photos`. Nie
  /// wchodzi do eksportu JSON — to ścieżka na TYM telefonie.
  final String? attachmentPath;

  final int createdAt;
  final int updatedAt;

  const WpsRecord({
    required this.id,
    required this.wpsNo,
    this.revision = '',
    this.standard = WpsStandard.iso15614_1,
    this.pqrRef = '',
    this.processes = '',
    this.materialGroup = '',
    this.thicknessMinMm,
    this.thicknessMaxMm,
    this.diameterMinMm,
    this.diameterMaxMm,
    this.positions = '',
    this.jointKinds = const <WeldJointKind>{},
    this.filler = '',
    this.shieldingGas = '',
    this.backingGas = '',
    this.preheatMinC,
    this.interpassMaxC,
    this.heatInputMinKjMm,
    this.heatInputMaxKjMm,
    this.heatInputMethod = HeatInputStandard.en1011,
    this.pwht = '',
    this.notes = '',
    this.docStatus = WpsDocStatus.unknown,
    this.attachmentPath,
    required this.createdAt,
    required this.updatedAt,
  });

  /// „WPS-141-01 rev. B".
  String get displayName {
    final rev = revision.trim();
    return rev.isEmpty ? wpsNo : '$wpsNo rev. $rev';
  }

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'wps_no': wpsNo,
        'revision': revision,
        'standard': standard.code,
        'pqr_ref': pqrRef,
        'processes': processes,
        'material_group': materialGroup,
        'thickness_min_mm': thicknessMinMm,
        'thickness_max_mm': thicknessMaxMm,
        'diameter_min_mm': diameterMinMm,
        'diameter_max_mm': diameterMaxMm,
        'positions': positions,
        'joint_kinds': encodeJointKinds(jointKinds),
        'filler': filler,
        'shielding_gas': shieldingGas,
        'backing_gas': backingGas,
        'preheat_min_c': preheatMinC,
        'interpass_max_c': interpassMaxC,
        'heat_input_min_kj_mm': heatInputMinKjMm,
        'heat_input_max_kj_mm': heatInputMaxKjMm,
        'heat_input_method': heatInputMethodCode(heatInputMethod),
        'pwht': pwht,
        'notes': notes,
        'attachment_path': attachmentPath,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'doc_status': docStatus.code.isEmpty ? null : docStatus.code,
      };

  /// Treść WPS bez identyfikatora, znaczników czasu i ścieżki pliku — to,
  /// co porównujemy, żeby wiedzieć, czy edycja zmieniła technologię.
  Map<String, Object?> contentRow() => toRow()
    ..remove('id')
    ..remove('attachment_path')
    ..remove('created_at')
    ..remove('updated_at');

  /// Ta sama treść technologiczna co [other].
  bool sameContentAs(WpsRecord other) {
    final a = contentRow();
    final b = other.contentRow();
    return a.keys.every((k) => '${a[k] ?? ''}' == '${b[k] ?? ''}');
  }

  static WpsRecord fromRow(Map<String, Object?> r) => WpsRecord(
        id: r['id'] as String,
        wpsNo: _text(r['wps_no']),
        revision: _text(r['revision']),
        standard: WpsStandard.fromCode(r['standard'] as String?),
        pqrRef: _text(r['pqr_ref']),
        processes: _text(r['processes']),
        materialGroup: _text(r['material_group']),
        thicknessMinMm: _num(r['thickness_min_mm']),
        thicknessMaxMm: _num(r['thickness_max_mm']),
        diameterMinMm: _num(r['diameter_min_mm']),
        diameterMaxMm: _num(r['diameter_max_mm']),
        positions: _text(r['positions']),
        jointKinds: decodeJointKinds(r['joint_kinds'] as String?),
        filler: _text(r['filler']),
        shieldingGas: _text(r['shielding_gas']),
        backingGas: _text(r['backing_gas']),
        preheatMinC: _num(r['preheat_min_c']),
        interpassMaxC: _num(r['interpass_max_c']),
        heatInputMinKjMm: _num(r['heat_input_min_kj_mm']),
        heatInputMaxKjMm: _num(r['heat_input_max_kj_mm']),
        heatInputMethod:
            heatInputMethodFromCode(r['heat_input_method'] as String?) ??
                HeatInputStandard.en1011,
        pwht: _text(r['pwht']),
        notes: _text(r['notes']),
        docStatus: WpsDocStatus.fromCode(r['doc_status'] as String?),
        attachmentPath: _nullableText(r['attachment_path']),
        createdAt: (r['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (r['updated_at'] as num?)?.toInt() ?? 0,
      );

  /// Kopia z nowym [id] i znacznikami czasu — przy imporcie.
  WpsRecord withIdentity({
    required String id,
    required int now,
    String? attachmentPath,
  }) =>
      WpsRecord(
        id: id,
        wpsNo: wpsNo,
        revision: revision,
        standard: standard,
        pqrRef: pqrRef,
        processes: processes,
        materialGroup: materialGroup,
        thicknessMinMm: thicknessMinMm,
        thicknessMaxMm: thicknessMaxMm,
        diameterMinMm: diameterMinMm,
        diameterMaxMm: diameterMaxMm,
        positions: positions,
        jointKinds: jointKinds,
        filler: filler,
        shieldingGas: shieldingGas,
        backingGas: backingGas,
        preheatMinC: preheatMinC,
        interpassMaxC: interpassMaxC,
        heatInputMinKjMm: heatInputMinKjMm,
        heatInputMaxKjMm: heatInputMaxKjMm,
        heatInputMethod: heatInputMethod,
        pwht: pwht,
        notes: notes,
        docStatus: docStatus,
        attachmentPath: attachmentPath,
        createdAt: now,
        updatedAt: now,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Wersje treści WPS (v25, tabela `wps_versions`)
// ═══════════════════════════════════════════════════════════════════════════

/// Jedna wersja treści WPS: snapshot wiersza obowiązujący od [validFrom].
///
/// WPS to dokument nadzorowany. Dawniej edycja (albo „Zastąp” przy
/// imporcie) nadpisywała wiersz, a kontrola spoin liczyła się przy każdym
/// otwarciu listy z BIEŻĄCEJ treści — poprawka zakresu „po cichu” zmieniała
/// werdykt dla spoin wykonanych wcześniej. Teraz każda zmiana treści to nowa
/// wersja, a spoina jest oceniana wg wersji obowiązującej w dniu spawania.
class WpsVersion {
  final String id;
  final String wpsId;
  final int versionNo;

  /// Epoch ms, od kiedy ta treść obowiązuje (0 = „od zawsze” — wersja
  /// sprzed historii albo pierwsza wpisana).
  final int validFrom;
  final WpsRecord snapshot;
  final String byStamp;
  final int createdAt;

  const WpsVersion({
    required this.id,
    required this.wpsId,
    required this.versionNo,
    required this.validFrom,
    required this.snapshot,
    this.byStamp = '',
    required this.createdAt,
  });

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'wps_id': wpsId,
        'version_no': versionNo,
        'valid_from': validFrom,
        'snapshot': jsonEncode(snapshot.toRow()),
        'by_stamp': byStamp.isEmpty ? null : byStamp,
        'created_at': createdAt,
      };

  /// `null` dla nieczytelnego snapshotu — jedna zepsuta wersja nie może
  /// wywrócić kontroli całego dziennika.
  static WpsVersion? fromRow(Map<String, Object?> r) {
    try {
      final decoded = jsonDecode(r['snapshot'] as String);
      if (decoded is! Map) return null;
      final row = <String, Object?>{
        for (final e in decoded.entries) e.key.toString(): e.value,
      };
      row['id'] = r['wps_id'];
      return WpsVersion(
        id: r['id'] as String,
        wpsId: r['wps_id'] as String,
        versionNo: (r['version_no'] as num?)?.toInt() ?? 0,
        validFrom: (r['valid_from'] as num?)?.toInt() ?? 0,
        snapshot: WpsRecord.fromRow(row),
        byStamp: (r['by_stamp'] as String?) ?? '',
        createdAt: (r['created_at'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Treść [current] obowiązująca w dniu [weldDay].
///
/// [versions] — zapisane wersje tej WPS (dowolna kolejność). Gdy bieżący
/// wiersz różni się od ostatniej wersji (np. odtworzony ze starszej kopii
/// zapasowej), bieżąca treść jest traktowana jako najnowsza wersja od
/// [WpsRecord.updatedAt]. Spoina sprzed pierwszej wersji (WPS wpisana do
/// aplikacji później niż spawano) dostaje wersję najstarszą.
WpsRecord wpsAsOf(
  WpsRecord current,
  Iterable<WpsVersion> versions,
  DateTime weldDay,
) {
  final list = [
    for (final v in versions)
      if (v.wpsId == current.id) v,
  ]..sort((a, b) {
      final byTime = a.validFrom.compareTo(b.validFrom);
      return byTime != 0 ? byTime : a.versionNo.compareTo(b.versionNo);
    });
  final timeline = <(int, WpsRecord)>[
    for (final v in list) (v.validFrom, v.snapshot),
  ];
  if (timeline.isEmpty || !timeline.last.$2.sameContentAs(current)) {
    timeline.add((timeline.isEmpty ? 0 : current.updatedAt, current));
  }
  // Koniec dnia spawania: wersja zapisana tego samego dnia już obowiązuje.
  final endOfDay = DateTime(weldDay.year, weldDay.month, weldDay.day + 1)
      .millisecondsSinceEpoch;
  WpsRecord picked = timeline.first.$2;
  for (final (from, record) in timeline) {
    if (from < endOfDay) picked = record;
  }
  // Tożsamość i plik zawsze z bieżącego wiersza.
  return WpsRecord.fromRow({
    ...picked.toRow(),
    'id': current.id,
    'attachment_path': current.attachmentPath,
    'created_at': current.createdAt,
    'updated_at': current.updatedAt,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Wymiana JSON (jedna WPS, udostępniana np. komunikatorem w brygadzie)
// ═══════════════════════════════════════════════════════════════════════════

/// Znacznik formatu — plik bez niego nie jest naszą WPS.
const String kWpsJsonFormat = 'fitter-welder-pro/wps';

/// Wersja formatu. Czytnik odrzuca nowszą, zamiast zgadywać.
const int kWpsJsonVersion = 1;

/// Plik / tekst, który nie jest poprawną WPS. Dwa języki, bo warstwa domeny
/// nie zna kontekstu UI — ekran wybiera komunikat.
class WpsFormatException implements Exception {
  final String messagePl;
  final String messageEn;

  const WpsFormatException(this.messagePl, this.messageEn);

  @override
  String toString() => 'WpsFormatException: $messageEn';
}

/// Nazwa pliku eksportu: `WPS-141-01_rev-B.json` — bez znaków, których nie
/// lubi system plików ani komunikator.
String wpsExportFileName(WpsRecord wps) {
  String clean(String s) =>
      s.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-').replaceAll(
          RegExp(r'-{2,}'), '-');
  final no = clean(wps.wpsNo);
  final rev = clean(wps.revision);
  final base = no.isEmpty ? 'WPS' : no;
  return rev.isEmpty ? '$base.json' : '${base}_rev-$rev.json';
}

/// Eksport jednej WPS. Bez identyfikatora i bez ścieżki załącznika — obie
/// rzeczy należą do telefonu, nie do technologii.
String encodeWpsJson(WpsRecord wps, {DateTime? exportedAt}) {
  final row = wps.toRow()
    ..remove('id')
    ..remove('attachment_path')
    ..remove('created_at')
    ..remove('updated_at');
  return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
    'format': kWpsJsonFormat,
    'version': kWpsJsonVersion,
    if (exportedAt != null) 'exportedAt': exportedAt.toUtc().toIso8601String(),
    'wps': row,
  });
}

/// Import jednej WPS z tekstu JSON. Zwraca rekord z pustym [WpsRecord.id] —
/// identyfikator nadaje wołający ([WpsRecord.withIdentity]).
///
/// Odrzuca (z komunikatem dla spawacza): nie-JSON, cudzy format, nowszą
/// wersję, brak numeru WPS, zakres z minimum większym od maksimum i liczby
/// ujemne.
WpsRecord decodeWpsJson(String text) {
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    throw const WpsFormatException(
      'To nie jest plik WPS (niepoprawny JSON).',
      'This is not a WPS file (invalid JSON).',
    );
  }
  if (decoded is! Map || decoded['format'] != kWpsJsonFormat) {
    throw const WpsFormatException(
      'To nie jest WPS z Fitter Welder Pro.',
      'This is not a Fitter Welder Pro WPS.',
    );
  }
  final version = decoded['version'];
  if (version is! int || version < 1) {
    throw const WpsFormatException(
      'Plik WPS nie ma poprawnej wersji formatu.',
      'The WPS file has no valid format version.',
    );
  }
  if (version > kWpsJsonVersion) {
    throw const WpsFormatException(
      'WPS zapisano w nowszej wersji aplikacji — zaktualizuj aplikację.',
      'The WPS was saved by a newer app version — update the app.',
    );
  }
  final body = decoded['wps'];
  if (body is! Map) {
    throw const WpsFormatException(
      'Plik WPS jest pusty.',
      'The WPS file is empty.',
    );
  }
  final row = <String, Object?>{
    for (final e in body.entries) e.key.toString(): e.value,
    'id': '',
    'attachment_path': null,
    'created_at': 0,
    'updated_at': 0,
  };
  // Liczby zapisane jako tekst („1,2") przyjmujemy; wszystko inne co nie jest
  // liczbą odrzucamy jawnie, zamiast po cichu zgubić granicę zakresu.
  for (final key in const [
    'thickness_min_mm',
    'thickness_max_mm',
    'diameter_min_mm',
    'diameter_max_mm',
    'preheat_min_c',
    'interpass_max_c',
    'heat_input_min_kj_mm',
    'heat_input_max_kj_mm',
  ]) {
    final v = row[key];
    if (v == null || (v is String && v.trim().isEmpty)) {
      row[key] = null;
      continue;
    }
    if (_num(v) == null) {
      throw WpsFormatException(
        'Pole „$key" nie jest liczbą.',
        'Field "$key" is not a number.',
      );
    }
  }
  final wps = WpsRecord.fromRow(row);
  final problem = validateWps(wps);
  if (problem != null) throw problem;
  return wps;
}

/// Sprawdza spójność WPS (edycja i import); `null` = w porządku.
WpsFormatException? validateWps(WpsRecord wps) {
  if (wps.wpsNo.trim().isEmpty) {
    return const WpsFormatException(
      'Brak numeru WPS.',
      'The WPS number is missing.',
    );
  }
  WpsFormatException? range(
      double? min, double? max, String namePl, String nameEn) {
    if ((min != null && min < 0) || (max != null && max < 0)) {
      return WpsFormatException(
        '$namePl: wartości nie mogą być ujemne.',
        '$nameEn: values cannot be negative.',
      );
    }
    if (min != null && max != null && min > max) {
      return WpsFormatException(
        '$namePl: minimum większe od maksimum.',
        '$nameEn: minimum is greater than maximum.',
      );
    }
    return null;
  }

  return range(wps.thicknessMinMm, wps.thicknessMaxMm, 'Grubość', 'Thickness') ??
      range(wps.diameterMinMm, wps.diameterMaxMm, 'Średnica', 'Diameter') ??
      range(wps.heatInputMinKjMm, wps.heatInputMaxKjMm, 'Energia liniowa',
          'Arc energy / heat input') ??
      range(wps.preheatMinC, null, 'Podgrzewanie', 'Preheat') ??
      range(null, wps.interpassMaxC, 'Temperatura międzyściegowa',
          'Interpass temperature');
}
