// Uprawnienie spawacza — jeden certyfikat w rejestrze (tabela
// `welder_certificates`, schemat v21).
//
// TERMINOLOGIA (to był błąd starej wersji):
//  • uprawnienie SPAWACZA = certyfikat wg EN ISO 9606-1 albo WPQ (Welder
//    Performance Qualification) wg ASME IX — dotyczy człowieka;
//  • WPQR (ISO 15614-1) / PQR (ASME IX) = protokół kwalifikowania PROCEDURY —
//    dotyczy technologii (WPS), nie spawacza.
// Pole „Nr WPQR / WPS" w tożsamości spawacza mieszało jedno z drugim. Tu jest
// tylko uprawnienie spawacza; WPS i jej WPQR/PQR żyją w bibliotece WPS
// (lib/domain/wps/wps_record.dart).
//
// Wszystkie pola poza identyfikatorem i normą są opcjonalne: spawacz często
// przepisuje certyfikat na budowie w dwóch podejściach, a niepełny wpis nadal
// jest lepszy niż brak wpisu. Czego brakuje, tego kontrola zakresu po prostu
// nie sprawdza (i mówi o tym), zamiast zgadywać.

import '../../utils/decimal_parse.dart';
import 'qualification_dates.dart';
import 'weld_process.dart';

/// Norma, wg której wydano uprawnienie.
enum QualificationStandard {
  /// EN ISO 9606-1 (stal). Ciągłość: potwierdzenie co 6 miesięcy przez
  /// koordynatora spawania / egzaminatora (§9.2).
  iso9606_1('ISO_9606_1', 'EN ISO 9606-1', 'EN ISO 9606-1'),

  /// ASME Section IX, WPQ. Ciągłość: uprawnienie do procesu wygasa, gdy
  /// spawacz nie spawał tym procesem 6 miesięcy (QW-322.1(a)).
  asmeIx('ASME_IX', 'ASME IX (WPQ)', 'ASME IX (WPQ)'),

  /// Inna norma (AWS D1.1, EN ISO 9606-2, dawna EN 287-1…). Aplikacja pilnuje
  /// wtedy tylko daty ważności — reguł ciągłości innych norm nie zgadujemy.
  other('OTHER', 'Inna norma', 'Other standard');

  const QualificationStandard(this.code, this.labelPl, this.labelEn);

  /// Kod w bazie i w eksporcie.
  final String code;
  final String labelPl;
  final String labelEn;

  static QualificationStandard fromCode(String? raw) {
    for (final s in QualificationStandard.values) {
      if (s.code == raw) return s;
    }
    return QualificationStandard.other;
  }
}

/// Sposób przedłużania wg EN ISO 9606-1 §9.3 — pole INFORMACYJNE, przepisane
/// z certyfikatu (norma każe je tam wpisać przy wydaniu).
enum IsoProlongation {
  /// a) ponowny egzamin co 3 lata.
  a('A'),

  /// b) co 2 lata: dwie spoiny produkcyjne z ostatnich 6 miesięcy zbadane
  /// RT/UT albo niszcząco, wyniki wg rozdz. 7.
  b('B'),

  /// c) ważność bezterminowa, dopóki są potwierdzenia co 6 miesięcy — tylko u
  /// tego samego producenta z systemem jakości wg ISO 3834-2 lub -3
  /// i udokumentowanymi spoinami o akceptowalnej jakości. Wg załącznika ZA
  /// normy EN nie dla urządzeń ciśnieniowych PED kat. II–IV.
  c('C');

  const IsoProlongation(this.code);

  final String code;

  static IsoProlongation? fromCode(String? raw) {
    final v = raw?.trim().toUpperCase();
    for (final p in IsoProlongation.values) {
      if (p.code == v) return p;
    }
    return null;
  }
}

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

DateTime? _date(Object? v) => v is String ? parseFlexibleDate(v) : null;

/// Jedno potwierdzenie 6-miesięczne EN ISO 9606-1 §9.2 (podpis koordynatora
/// spawania / egzaminatora) albo wpis ciągłości WPQ prowadzony przez
/// pracodawcę (ASME) — wiersz tabeli `welder_cert_confirmations` (v25).
///
/// Do v25 rejestr trzymał tylko OSTATNIE potwierdzenie (nadpisywane), więc
/// nowe potwierdzenie „unieważniało" wstecz stare okresy, a spóźnione
/// wskrzeszało wygasły certyfikat. Historia pozwala liczyć status na dowolny
/// dzień z łańcucha potwierdzeń — patrz `evaluateCertificate`.
class CertificateConfirmation {
  final String id;
  final String certificateId;

  /// Dzień podpisu (bez godziny).
  final DateTime date;

  /// Kto potwierdził (koordynator / egzaminator); pusty, gdy nie podano.
  final String confirmedBy;
  final String notes;

  /// Epoch ms wpisu do aplikacji.
  final int createdAt;

  const CertificateConfirmation({
    required this.id,
    required this.certificateId,
    required this.date,
    this.confirmedBy = '',
    this.notes = '',
    required this.createdAt,
  });

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'certificate_id': certificateId,
        'date': formatIsoDate(date),
        'confirmed_by': confirmedBy.trim().isEmpty ? null : confirmedBy.trim(),
        'notes': notes.trim().isEmpty ? null : notes.trim(),
        'created_at': createdAt,
      };

  /// `null`, gdy data jest nieczytelna — jeden zepsuty wiersz nie może
  /// ukryć całej historii.
  static CertificateConfirmation? fromRow(Map<String, Object?> r) {
    final date = _date(r['date']);
    final id = r['id'];
    if (date == null || id is! String) return null;
    return CertificateConfirmation(
      id: id,
      certificateId: _text(r['certificate_id']),
      date: date,
      confirmedBy: _text(r['confirmed_by']),
      notes: _text(r['notes']),
      createdAt: (r['created_at'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Jeden certyfikat uprawnień spawacza.
class WelderCertificate {
  final String id;

  /// Stempel spawacza, którego dotyczy certyfikat (z tożsamości spawacza).
  /// Dziś jeden spawacz na urządzenie; pole jest po to, żeby dziennik mógł
  /// kiedyś sprawdzać uprawnienia całej brygady.
  final String? welderStamp;

  final QualificationStandard standard;

  /// Nazwa normy, gdy [standard] to [QualificationStandard.other].
  final String? standardLabel;

  /// Numer certyfikatu / WPQ.
  final String? certNo;

  /// Jednostka / egzaminator (np. „UDT", „TÜV Rheinland, J. Nowak").
  final String? examiner;

  /// Data spawania złącza próbnego — od niej biegnie ważność (ISO 9606-1 §9.1).
  final DateTime? testDate;

  /// „Ważny do" z certyfikatu. `null` = bez daty końcowej (np. ISO 9606-1
  /// §9.3 c albo WPQ ASME utrzymywane ciągłością).
  final DateTime? expiryDate;

  /// Ostatnie potwierdzenie 6-miesięczne (ISO 9606-1 §9.2 — podpis
  /// koordynatora spawania / egzaminatora) albo ostatni wpis ciągłości WPQ
  /// prowadzony przez pracodawcę (ASME). Od v25 to tylko skrót (najnowsza
  /// data z [confirmations]) — status liczy się z całej historii.
  final DateTime? lastConfirmedDate;

  /// Historia potwierdzeń (tabela `welder_cert_confirmations`, v25),
  /// dołączana przez DAO; NIE jest kolumną `welder_certificates`, więc nie
  /// wchodzi do [toRow].
  final List<CertificateConfirmation> confirmations;

  /// Sposób przedłużania wg ISO 9606-1 §9.3 (informacyjnie).
  final IsoProlongation? prolongation;

  /// Proces(y): numery EN ISO 4063 („141", „135, 136") albo nazwy.
  final String processes;

  /// Grupa materiałowa wg ISO/TR 15608 („8.1") albo P-No ASME („P8").
  final String materialGroup;

  /// Zakres grubości (mm). `null` = bez ograniczenia z tej strony.
  final double? thicknessMinMm;
  final double? thicknessMaxMm;

  /// Zakres średnic zewnętrznych rur (mm). `null` = bez ograniczenia.
  final double? diameterMinMm;
  final double? diameterMaxMm;

  /// Pozycje OBJĘTE uprawnieniem (zakres, nie pozycja egzaminu), np.
  /// „PA, PC, PE, PF" albo „wszystkie".
  final String positions;

  /// Spoiwo / typ (np. „FM5, S 19 12 3 L" albo „F-No 6").
  final String filler;

  /// Rodzaje spoin objęte uprawnieniem (BW / FW).
  final Set<WeldJointKind> jointKinds;

  final String notes;

  /// Kopia zdjęcia certyfikatu w `<documents>/heat_photos` (objęte kopią
  /// zapasową, patrz `data_backup.dart`).
  final String? photoPath;

  final int createdAt;
  final int updatedAt;

  const WelderCertificate({
    required this.id,
    required this.standard,
    this.welderStamp,
    this.standardLabel,
    this.certNo,
    this.examiner,
    this.testDate,
    this.expiryDate,
    this.lastConfirmedDate,
    this.prolongation,
    this.processes = '',
    this.materialGroup = '',
    this.thicknessMinMm,
    this.thicknessMaxMm,
    this.diameterMinMm,
    this.diameterMaxMm,
    this.positions = '',
    this.filler = '',
    this.jointKinds = const <WeldJointKind>{},
    this.notes = '',
    this.photoPath,
    this.confirmations = const <CertificateConfirmation>[],
    required this.createdAt,
    required this.updatedAt,
  });

  /// Daty potwierdzeń do łańcucha ciągłości: cała historia plus
  /// [lastConfirmedDate] (wiersz odtworzony ze starszej kopii zapasowej ma
  /// tylko ją). Bez powtórzeń, rosnąco.
  List<DateTime> get confirmationDates {
    final seen = <DateTime>{
      for (final c in confirmations) dateOnly(c.date),
      if (lastConfirmedDate != null) dateOnly(lastConfirmedDate!),
    };
    return seen.toList()..sort();
  }

  /// Stempel właściciela certyfikatu po normalizacji (wielkie litery, bez
  /// spacji na brzegach); `null` dla certyfikatu bez stempla.
  String? get stampKey {
    final s = welderStamp?.trim().toUpperCase() ?? '';
    return s.isEmpty ? null : s;
  }

  /// Etykieta normy do wyświetlenia.
  String standardName({required bool english}) {
    if (standard == QualificationStandard.other) {
      final custom = standardLabel?.trim() ?? '';
      if (custom.isNotEmpty) return custom;
    }
    return english ? standard.labelEn : standard.labelPl;
  }

  /// Krótki opis do listy i powiadomień: „EN ISO 9606-1 · nr 123/2026".
  String shortTitle({required bool english}) {
    final no = certNo?.trim() ?? '';
    final name = standardName(english: english);
    if (no.isEmpty) return name;
    return english ? '$name · no. $no' : '$name · nr $no';
  }

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'welder_stamp': welderStamp,
        'standard': standard.code,
        'standard_label': standardLabel,
        'cert_no': certNo,
        'examiner': examiner,
        'test_date': testDate == null ? null : formatIsoDate(testDate!),
        'expiry_date': expiryDate == null ? null : formatIsoDate(expiryDate!),
        'last_confirmed_date': lastConfirmedDate == null
            ? null
            : formatIsoDate(lastConfirmedDate!),
        'prolongation': prolongation?.code,
        'processes': processes,
        'material_group': materialGroup,
        'thickness_min_mm': thicknessMinMm,
        'thickness_max_mm': thicknessMaxMm,
        'diameter_min_mm': diameterMinMm,
        'diameter_max_mm': diameterMaxMm,
        'positions': positions,
        'filler': filler,
        'joint_kinds': encodeJointKinds(jointKinds),
        'notes': notes,
        'photo_path': photoPath,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  /// Odczyt wiersza. Wartości, których nie da się odczytać (np. data
  /// z przyszłej wersji w innym formacie), dają `null`, a nie wyjątek — jeden
  /// zepsuty wiersz nie może ukryć całego rejestru.
  static WelderCertificate fromRow(Map<String, Object?> r) => WelderCertificate(
        id: r['id'] as String,
        welderStamp: _nullableText(r['welder_stamp']),
        standard: QualificationStandard.fromCode(r['standard'] as String?),
        standardLabel: _nullableText(r['standard_label']),
        certNo: _nullableText(r['cert_no']),
        examiner: _nullableText(r['examiner']),
        testDate: _date(r['test_date']),
        expiryDate: _date(r['expiry_date']),
        lastConfirmedDate: _date(r['last_confirmed_date']),
        prolongation: IsoProlongation.fromCode(r['prolongation'] as String?),
        processes: _text(r['processes']),
        materialGroup: _text(r['material_group']),
        thicknessMinMm: _num(r['thickness_min_mm']),
        thicknessMaxMm: _num(r['thickness_max_mm']),
        diameterMinMm: _num(r['diameter_min_mm']),
        diameterMaxMm: _num(r['diameter_max_mm']),
        positions: _text(r['positions']),
        filler: _text(r['filler']),
        jointKinds: decodeJointKinds(r['joint_kinds'] as String?),
        notes: _text(r['notes']),
        photoPath: _nullableText(r['photo_path']),
        createdAt: (r['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (r['updated_at'] as num?)?.toInt() ?? 0,
      );

  WelderCertificate copyWith({
    String? welderStamp,
    QualificationStandard? standard,
    String? standardLabel,
    String? certNo,
    String? examiner,
    DateTime? testDate,
    DateTime? expiryDate,
    DateTime? lastConfirmedDate,
    IsoProlongation? prolongation,
    String? processes,
    String? materialGroup,
    String? positions,
    String? filler,
    Set<WeldJointKind>? jointKinds,
    String? notes,
    String? photoPath,
    List<CertificateConfirmation>? confirmations,
    int? updatedAt,
  }) =>
      WelderCertificate(
        id: id,
        welderStamp: welderStamp ?? this.welderStamp,
        standard: standard ?? this.standard,
        standardLabel: standardLabel ?? this.standardLabel,
        certNo: certNo ?? this.certNo,
        examiner: examiner ?? this.examiner,
        testDate: testDate ?? this.testDate,
        expiryDate: expiryDate ?? this.expiryDate,
        lastConfirmedDate: lastConfirmedDate ?? this.lastConfirmedDate,
        prolongation: prolongation ?? this.prolongation,
        processes: processes ?? this.processes,
        materialGroup: materialGroup ?? this.materialGroup,
        thicknessMinMm: thicknessMinMm,
        thicknessMaxMm: thicknessMaxMm,
        diameterMinMm: diameterMinMm,
        diameterMaxMm: diameterMaxMm,
        positions: positions ?? this.positions,
        filler: filler ?? this.filler,
        jointKinds: jointKinds ?? this.jointKinds,
        notes: notes ?? this.notes,
        photoPath: photoPath ?? this.photoPath,
        confirmations: confirmations ?? this.confirmations,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
