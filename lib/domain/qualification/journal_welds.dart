// Odczyt dziennika spoin na potrzeby ciągłości uprawnień — TYLKO ODCZYT.
//
// Dziennik (tabela `weld_journal`) należy do innego modułu i trzyma wszystko
// jako wolny tekst: datę („2026-09-10", ale też „10.09.2026" wpisane z ręki),
// metodę („TIG", „MIG/MAG", „MMA", „Tandem") i spawacza (stempel, ale
// edytowalny). Ta funkcja bierze wiersz tak, jak leży w bazie, i albo zwraca
// jednoznaczną spoinę, albo `null`. Wszystko niepewne jest pomijane —
// pominięta spoina co najwyżej przyspieszy ostrzeżenie, a policzona błędnie
// mogłaby przedłużyć uprawnienie, którego nikt nie utrzymał.

import 'certificate_status.dart';
import 'qualification_dates.dart';
import 'weld_process.dart';

String _upperTrim(Object? v) => v is String ? v.trim().toUpperCase() : '';

/// Spoina z wiersza `weld_journal` albo `null`, gdy:
///  • [stamp] jest pusty (nie wiemy, czyje to spoiny — nie liczymy żadnych),
///  • spoinę podpisał ktoś inny niż [stamp] (dziennik bywa prowadzony za
///    całą brygadę),
///  • data nie daje się jednoznacznie odczytać albo jest późniejsza niż
///    [today],
///  • nie rozpoznano procesu.
///
/// Proces bierzemy z kolumny `method`; jeżeli moduł dziennika doda kiedyś
/// kolumnę `process` (np. numer ISO 4063), też zostanie odczytana.
JournalWeld? journalWeldFromRow(
  Map<String, Object?> row, {
  required String? stamp,
  required DateTime today,
}) {
  final who = stamp?.trim().toUpperCase() ?? '';
  if (who.isEmpty) return null;
  if (_upperTrim(row['welder']) != who) return null;
  final date = parseFlexibleDate(row['date'] as String?);
  if (date == null || date.isAfter(dateOnly(today))) return null;
  final families = <WeldProcessFamily>{
    ...processFamiliesIn(row['method'] as String?),
    ...processFamiliesIn(row['process'] as String?),
  };
  if (families.isEmpty) return null;
  return JournalWeld(date, families);
}

/// [journalWeldFromRow] dla wielu wierszy, z pominięciem odrzuconych.
List<JournalWeld> journalWeldsFromRows(
  Iterable<Map<String, Object?>> rows, {
  required String? stamp,
  required DateTime today,
}) =>
    <JournalWeld>[
      for (final r in rows)
        if (journalWeldFromRow(r, stamp: stamp, today: today)
            case final JournalWeld w)
          w,
    ];
