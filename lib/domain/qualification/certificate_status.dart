// Status uprawnienia spawacza na dany dzień — czyste funkcje.
//
// DWA NIEZALEŻNE TERMINY
//  1. Data ważności z certyfikatu („ważny do"). Po niej uprawnienie wygasło.
//  2. Termin ciągłości co 6 miesięcy:
//     • EN ISO 9606-1 §9.2 — co 6 miesięcy koordynator spawania (albo
//       egzaminator / jednostka egzaminująca) potwierdza, że spawacz pracował
//       w zakresie uprawnienia; bez potwierdzenia certyfikat traci ważność.
//       Termin = (ostatnie potwierdzenie albo data egzaminu) + 6 miesięcy.
//       Spoiny w dzienniku są tu tylko DOWODEM dla koordynatora — samo
//       spawanie nie przedłuża ISO 9606-1, potrzebny jest podpis.
//     • ASME IX QW-322.1(a) — uprawnienie do PROCESU wygasa, gdy spawacz nie
//       spawał nim przez 6 miesięcy lub dłużej; każda spoina tym procesem
//       (pod nadzorem organizacji kwalifikującej) przesuwa termin o kolejne
//       6 miesięcy od jej daty. Termin liczymy z łańcucha: egzamin → kolejne
//       spoiny z dziennika / wpisy ciągłości. Przerwa dłuższa niż 6 miesięcy
//       przerywa łańcuch — późniejsza spoina NIE wskrzesza wygasłego WPQ
//       (odnowienie to QW-322.2, nowy egzamin → nowa data egzaminu).
//     • Inna norma — terminu ciągłości nie liczymy (nie zgadujemy cudzych
//       reguł), pilnujemy tylko daty ważności.
//
// Źródła (weryfikacja 2026-09-24): streszczenie EN ISO 9606-1:2017 rozdz. 9
// (doawise.com „Welder qualification to EN ISO 9606-1"; EWF-654-13), treść
// ASME IX QW-322.1 cytowana na forach eng-tips / AWS. Pełnych tekstów norm
// nie mamy — patrz raport.

import 'qualification_dates.dart';
import 'weld_process.dart';
import 'welder_certificate.dart';

/// Ile miesięcy wolno bez potwierdzenia / bez spawania procesem.
const int kContinuityMonths = 6;

/// Od ilu dni przed terminem ostrzegamy (baner, status „wymaga potwierdzenia").
const int kAttentionWindowDays = 30;

/// Status uprawnienia, od najlepszego do najgorszego.
enum QualificationState {
  /// Ważne, żaden termin nie jest bliżej niż [kAttentionWindowDays].
  valid,

  /// Do terminu 6-miesięcznego zostało ≤ 30 dni — trzeba potwierdzenia
  /// (ISO) albo spoiny tym procesem (ASME).
  confirmationDue,

  /// Do daty ważności zostało ≤ 30 dni.
  expiringSoon,

  /// Termin 6-miesięczny minął — uprawnienie przeterminowane (ISO: brak
  /// potwierdzenia; ASME: przerwa w spawaniu procesem).
  lapsed,

  /// Data ważności minęła.
  expired;

  /// 0 — w porządku, 1 — ostrzeżenie (bursztyn), 2 — nie wolno spawać
  /// (czerwień).
  int get severity => switch (this) {
        QualificationState.valid => 0,
        QualificationState.confirmationDue => 1,
        QualificationState.expiringSoon => 1,
        QualificationState.lapsed => 2,
        QualificationState.expired => 2,
      };

  /// Uprawnienie pozwala dziś spawać (także z ostrzeżeniem).
  bool get allowsWelding => severity < 2;
}

/// Reguła ciągłości zastosowana do certyfikatu.
enum ContinuityRule {
  /// Brak reguły (inna norma) albo brak danych do jej policzenia.
  none,

  /// ISO 9606-1 §9.2 — potwierdzenie co 6 miesięcy.
  confirmation,

  /// ASME IX QW-322.1(a) — spawanie procesem co najmniej raz na 6 miesięcy.
  processUse,
}

/// Skąd wziął się ostatni punkt łańcucha ciągłości.
enum ContinuitySource { test, confirmation, journal }

/// Spoina z dziennika zredukowana do tego, czego potrzebuje ciągłość:
/// dzień i rodzina(y) procesu.
class JournalWeld {
  final DateTime date;
  final Set<WeldProcessFamily> families;

  const JournalWeld(this.date, this.families);
}

/// Spoiny z [journal] wykonane procesem objętym [certificate] — daty,
/// posortowane rosnąco. Wpis bez rozpoznanego procesu nie liczy się do
/// ciągłości (nie wiadomo, czym spawano).
List<DateTime> journalWeldsFor(
  WelderCertificate certificate,
  Iterable<JournalWeld> journal,
) {
  final families = processFamiliesIn(certificate.processes);
  if (families.isEmpty) return const <DateTime>[];
  final out = <DateTime>[
    for (final w in journal)
      if (w.families.any(families.contains)) dateOnly(w.date),
  ]..sort();
  return out;
}

/// Wynik oceny jednego certyfikatu na dany dzień.
class CertificateEvaluation {
  final WelderCertificate certificate;

  /// Dzień, na który liczono.
  final DateTime asOf;

  final QualificationState state;

  /// Dni do daty ważności (ujemne po terminie); `null` bez daty.
  final int? daysToExpiry;

  final ContinuityRule rule;

  /// Termin 6-miesięczny (ostatni dzień, w którym uprawnienie jest jeszcze
  /// utrzymane); `null`, gdy reguły nie ma albo brak danych.
  final DateTime? continuityDeadline;

  /// Dni do [continuityDeadline] (ujemne po terminie).
  final int? daysToContinuityDeadline;

  /// Ostatni punkt łańcucha i jego źródło.
  final DateTime? continuityAnchor;
  final ContinuitySource? continuitySource;

  /// Ostatnia spoina tym procesem w dzienniku (do [asOf] włącznie).
  final DateTime? lastJournalWeld;

  /// Ciągłość powinna być liczona, ale brakuje daty egzaminu i potwierdzenia.
  final bool continuityUnknown;

  const CertificateEvaluation({
    required this.certificate,
    required this.asOf,
    required this.state,
    required this.daysToExpiry,
    required this.rule,
    required this.continuityDeadline,
    required this.daysToContinuityDeadline,
    required this.continuityAnchor,
    required this.continuitySource,
    required this.lastJournalWeld,
    required this.continuityUnknown,
  });

  DateTime? get expiryDate => certificate.expiryDate;
}

/// Ocena [certificate] na dzień [asOf].
///
/// [journalWelds] — daty spoin TEGO spawacza procesem objętym certyfikatem
/// (patrz [journalWeldsFor]); daty późniejsze niż [asOf] są ignorowane, tak
/// samo jak wcześniejsze niż data egzaminu (spoiny sprzed egzaminu nie
/// utrzymują uprawnienia, którego jeszcze nie było).
CertificateEvaluation evaluateCertificate(
  WelderCertificate certificate, {
  required DateTime asOf,
  Iterable<DateTime> journalWelds = const <DateTime>[],
}) {
  final today = dateOnly(asOf);
  final test = certificate.testDate == null ? null : dateOnly(certificate.testDate!);
  final confirmed = certificate.lastConfirmedDate == null
      ? null
      : dateOnly(certificate.lastConfirmedDate!);

  bool inWindow(DateTime d) =>
      !d.isAfter(today) && (test == null || !d.isBefore(test));

  final welds = <DateTime>[
    for (final d in journalWelds)
      if (inWindow(dateOnly(d))) dateOnly(d),
  ]..sort();
  final lastWeld = welds.isEmpty ? null : welds.last;

  // ---- Data ważności
  final expiry = certificate.expiryDate;
  final daysToExpiry =
      expiry == null ? null : calendarDaysBetween(today, expiry);

  // ---- Ciągłość
  var rule = ContinuityRule.none;
  DateTime? deadline;
  DateTime? anchor;
  ContinuitySource? source;
  var unknown = false;

  switch (certificate.standard) {
    case QualificationStandard.iso9606_1:
      rule = ContinuityRule.confirmation;
      // Znamy tylko OSTATNIE potwierdzenie (historii podpisów nie
      // przechowujemy), więc termin to ono + 6 miesięcy. Potwierdzenie z datą
      // w przyszłości (literówka) nie liczy się.
      final usableConfirmation =
          confirmed != null && !confirmed.isAfter(today) ? confirmed : null;
      if (usableConfirmation != null &&
          (test == null || !usableConfirmation.isBefore(test))) {
        anchor = usableConfirmation;
        source = ContinuitySource.confirmation;
      } else if (test != null) {
        anchor = test;
        source = ContinuitySource.test;
      }
      if (anchor != null) {
        deadline = addMonthsClamped(anchor, kContinuityMonths);
      } else {
        unknown = true;
      }
    case QualificationStandard.asmeIx:
      rule = ContinuityRule.processUse;
      final events = <(DateTime, ContinuitySource)>[
        if (test != null && !test.isAfter(today)) (test, ContinuitySource.test),
        if (confirmed != null && inWindow(confirmed))
          (confirmed, ContinuitySource.confirmation),
        for (final w in welds) (w, ContinuitySource.journal),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      if (events.isEmpty) {
        unknown = true;
        break;
      }
      anchor = events.first.$1;
      source = events.first.$2;
      deadline = addMonthsClamped(anchor, kContinuityMonths);
      // Zdarzenia są posortowane, więc każde kolejne w terminie przesuwa
      // termin dalej.
      for (final (date, src) in events.skip(1)) {
        // Przerwa: zdarzenie po terminie nie przedłuża już wygasłego WPQ.
        if (date.isAfter(deadline!)) break;
        anchor = date;
        source = src;
        deadline = addMonthsClamped(date, kContinuityMonths);
      }
    case QualificationStandard.other:
      rule = ContinuityRule.none;
  }

  final daysToDeadline =
      deadline == null ? null : calendarDaysBetween(today, deadline);

  // ---- Status: najgorszy z obu terminów. Data ważności oceniana pierwsza,
  // więc przy remisie wagi („wygasł" i „brak potwierdzenia" — oba czerwone)
  // zostaje mocniejszy komunikat o dacie ważności.
  var state = QualificationState.valid;
  void worsen(QualificationState s) {
    if (s.severity > state.severity) state = s;
  }

  if (daysToExpiry != null) {
    if (daysToExpiry < 0) {
      worsen(QualificationState.expired);
    } else if (daysToExpiry <= kAttentionWindowDays) {
      worsen(QualificationState.expiringSoon);
    }
  }
  if (daysToDeadline != null) {
    if (daysToDeadline < 0) {
      worsen(QualificationState.lapsed);
    } else if (daysToDeadline <= kAttentionWindowDays) {
      worsen(QualificationState.confirmationDue);
    }
  }
  return CertificateEvaluation(
    certificate: certificate,
    asOf: today,
    state: state,
    daysToExpiry: daysToExpiry,
    rule: rule,
    continuityDeadline: deadline,
    daysToContinuityDeadline: daysToDeadline,
    continuityAnchor: anchor,
    continuitySource: source,
    lastJournalWeld: lastWeld,
    continuityUnknown: unknown,
  );
}

/// Podsumowanie całego rejestru — to, co pokazuje baner w menu SPAWACZ.
class QualificationOverview {
  final List<CertificateEvaluation> evaluations;

  const QualificationOverview(this.evaluations);

  static const QualificationOverview empty =
      QualificationOverview(<CertificateEvaluation>[]);

  /// Najgorszy status w rejestrze; [QualificationState.valid] dla pustego.
  QualificationState get worstState {
    var worst = QualificationState.valid;
    for (final e in evaluations) {
      if (e.state.severity > worst.severity) worst = e.state;
    }
    return worst;
  }

  /// Certyfikaty wymagające uwagi, najpilniejsze pierwsze (czerwone przed
  /// bursztynowymi, potem najbliższy termin).
  List<CertificateEvaluation> get needingAttention {
    final list = evaluations
        .where((e) => e.state != QualificationState.valid)
        .toList();
    list.sort((a, b) {
      final bySeverity = b.state.severity.compareTo(a.state.severity);
      if (bySeverity != 0) return bySeverity;
      return _nearestDays(a).compareTo(_nearestDays(b));
    });
    return list;
  }

  static int _nearestDays(CertificateEvaluation e) {
    final candidates = <int>[
      if (e.daysToExpiry != null) e.daysToExpiry!,
      if (e.daysToContinuityDeadline != null) e.daysToContinuityDeadline!,
    ];
    if (candidates.isEmpty) return 1 << 30;
    return candidates.reduce((a, b) => a < b ? a : b);
  }
}
