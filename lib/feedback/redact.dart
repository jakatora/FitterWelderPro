// Maskowanie danych kontaktowych w tekście zgłoszenia — PRZED zapisem do
// kolejki, więc niezamaskowany tekst nie leży nawet w pamięci telefonu.
//
// Maskujemy (zastępując całość `***`):
//   - adresy e-mail, także podyktowane („jan małpa wp kropka pl”);
//   - telefony: +48 600 100 200, (+48) 600-100-200, 0048 600100200,
//     600-100-200, 600.100.200, 600 100 200 (komórki PL zaczynają się od 4–8),
//     stacjonarne 22 123 45 67 i (22) 123-45-67;
//   - numery kont w grupach (PL61 1090 1014 0000 0712 1981 2874);
//   - każdy ciąg ≥ 9 cyfr (PESEL, NIP, konto, telefon bez odstępów).
//
// Świadomie NIE maskujemy list wymiarów („1200 1500 800”, „DN 50 100 200”),
// dat ani pojedynczych liczb — to treść, z której właściciel uczy asystenta.
// Koszt: trzy liczby trzycyfrowe od 4–8 w zapisie 3-3-3 („600 100 200”)
// wyglądają jak komórka i zostaną zamaskowane. Prywatność ma pierwszeństwo.

const String kRedactedMark = '***';

final RegExp _email = RegExp(
  r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}',
);

/// E-mail z mowy: „jan małpa wp kropka pl”, „jan at gmail.com”. Kropka
/// literalna tylko bez odstępów, żeby nie łapać końca zdania („at startup. …”).
final RegExp _spokenEmail = RegExp(
  r'[\p{L}\p{N}._\-]+\s+(?:małpa|malpa|at)\s+[\p{L}\p{N}\-]+'
  r'(?:(?:\s+(?:kropka|dot)\s+|\.)[\p{L}\p{N}\-]+)+',
  caseSensitive: false,
  unicode: true,
);

/// Numer z prefiksem kraju: „+48 …”, „(+48) …”, „0048 …”.
final RegExp _international = RegExp(r'\(?(?:\+|\b00)\d[\d \-.()]{6,}\d');

/// Konto w grupach po 4 cyfry (opcjonalnie z kodem kraju).
final RegExp _accountGrouped =
    RegExp(r'\b(?:[A-Za-z]{2})?\d{2}(?: ?\d{4}){5,7}\b');

/// Grupy cyfr rozdzielone „-” albo „.” (600-100-200, 123-456-78-90).
final RegExp _separated = RegExp(r'\b\d{2,4}(?:[\-.]\d{2,4}){2,4}\b');

/// Stacjonarny: 22 123 45 67, (22) 123-45-67.
final RegExp _landline =
    RegExp(r'\(?\b\d{2}\)?[ \-.]\d{3}[ \-.]\d{2}[ \-.]\d{2}\b');

/// Komórka PL w zapisie 3-3-3 ze spacjami.
final RegExp _mobileSpaced = RegExp(r'\b[4-8]\d{2} \d{3} \d{3}\b');

/// Każdy ciąg co najmniej 9 cyfr.
final RegExp _longDigits = RegExp(r'\d{9,}');

final RegExp _digit = RegExp(r'\d');

int _digitCount(String s) => _digit.allMatches(s).length;

/// Zastępuje dane kontaktowe i długie ciągi cyfr znakiem [kRedactedMark].
String redactPersonalData(String text) {
  if (text.isEmpty) return text;
  var out = text;
  out = out.replaceAll(_email, kRedactedMark);
  out = out.replaceAll(_spokenEmail, kRedactedMark);
  // Konto przed numerem międzynarodowym: grupa „0000” w koncie wygląda jak
  // prefiks „00” i zamaskowałaby tylko ogon numeru.
  out = out.replaceAll(_accountGrouped, kRedactedMark);
  out = out.replaceAllMapped(
      _international, (m) => _digitCount(m[0]!) >= 8 ? kRedactedMark : m[0]!);
  out = out.replaceAllMapped(
      _separated, (m) => _digitCount(m[0]!) >= 9 ? kRedactedMark : m[0]!);
  out = out.replaceAll(_landline, kRedactedMark);
  out = out.replaceAll(_mobileSpaced, kRedactedMark);
  out = out.replaceAll(_longDigits, kRedactedMark);
  return out;
}

/// Przycina do [max] jednostek UTF-16 (tak liczy `String.length` w Dart i w
/// JavaScript, więc tak samo jak walidacja backendu), bez rozcinania pary
/// zastępczej (emoji).
String truncateUtf16(String s, int max) {
  if (s.length <= max) return s;
  var end = max;
  final last = s.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end -= 1;
  return s.substring(0, end);
}

/// Tekst gotowy do kolejki: zamaskowany, bez skrajnych odstępów, ≤ [max].
String prepareFeedbackText(String text, {int max = 500}) =>
    truncateUtf16(redactPersonalData(text).trim(), max);
