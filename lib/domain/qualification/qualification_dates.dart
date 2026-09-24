// Daty w rejestrze uprawnień — wyłącznie DATY (bez godzin).
//
// Stary baner liczył `wpqrExpiry.difference(DateTime.now()).inDays`. Duration
// obcina w stronę zera, a różnica ściennego czasu przez zmianę czasu (DST) ma
// 23 albo 25 godzin — stąd „wygasa za 0 dni" na certyfikacie martwym od
// pięciu godzin i przeskoki o dzień w marcu i październiku. Tu wszystko idzie
// przez daty kalendarzowe liczone w UTC, więc „ważny do 2026-09-10" znaczy
// ważny przez cały 10 września, a liczba dni nie zależy od pory dnia ani od
// strefy czasowej.

/// Północ tego samego dnia kalendarzowego (czas lokalny).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Dni kalendarzowe od [from] do [to] (ujemne, gdy [to] jest wcześniej).
/// Godziny i strefa czasowa nie mają znaczenia.
int calendarDaysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// [date] + [months] miesięcy, z dniem przyciętym do końca miesiąca:
/// 31 sierpnia + 6 miesięcy = 28 (29) lutego, nie 3 marca. Norma mówi
/// „co sześć miesięcy" — przesunięcie terminu o trzy dni w przód byłoby
/// ustępstwem na korzyść spawacza, którego nikt nie przyznał.
DateTime addMonthsClamped(DateTime date, int months) {
  // Licznik miesięcy od roku 0 — dodatni dla każdej realnej daty, więc `~/`
  // i `%` nie mają tu pułapek z liczbami ujemnymi.
  final total = date.year * 12 + (date.month - 1) + months;
  final year = total ~/ 12;
  final month = total % 12 + 1;
  // Dzień 0 następnego miesiąca = ostatni dzień tego miesiąca.
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = date.day > lastDay ? lastDay : date.day;
  return DateTime(year, month, day);
}

String _two(int v) => v.toString().padLeft(2, '0');

/// `2026-09-10` — format zapisu w bazie, w JSON-ie WPS i na ekranie
/// (jednoznaczny dla brygady mieszającej konwencje PL i EN).
String formatIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

final RegExp _kIsoLike =
    RegExp(r'^(\d{4})[-./](\d{1,2})[-./](\d{1,2})(?:[T\s].*)?$');
final RegExp _kDayFirst = RegExp(r'^(\d{1,2})[-./](\d{1,2})[-./](\d{4})$');

/// Data wpisana ręcznie, albo `null`, gdy tekst nie jest jednoznaczną,
/// istniejącą datą.
///
/// Dziennik spoin trzyma datę jako WOLNY tekst (pole z kalendarzem, ale
/// edytowalne), więc spotykamy: `2026-09-10`, `2026-09-10T08:00`,
/// `2026.09.10`, `10.09.2026`, `10-09-2026`, `10/09/2026`, `1.9.2026`.
/// Wszystko inne — rok dwucyfrowy, `2026-02-30`, `jutro`, pusty tekst — daje
/// `null`: lepiej pominąć spoinę w liczeniu ciągłości, niż przypisać ją do
/// złego dnia i przedłużyć uprawnienie, którego nikt nie potwierdził.
DateTime? parseFlexibleDate(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  int y;
  int m;
  int d;
  final iso = _kIsoLike.firstMatch(text);
  if (iso != null) {
    y = int.parse(iso.group(1)!);
    m = int.parse(iso.group(2)!);
    d = int.parse(iso.group(3)!);
  } else {
    final dayFirst = _kDayFirst.firstMatch(text);
    if (dayFirst == null) return null;
    d = int.parse(dayFirst.group(1)!);
    m = int.parse(dayFirst.group(2)!);
    y = int.parse(dayFirst.group(3)!);
  }
  if (y < 1970 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  final date = DateTime(y, m, d);
  // DateTime(2026, 2, 30) po cichu robi 2 marca — odrzucamy taką datę.
  if (date.year != y || date.month != m || date.day != d) return null;
  return date;
}
