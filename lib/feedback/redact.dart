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
//
// Wzorce szukają na KOPII tekstu, w której każdy ciąg białych znaków
// (podwójna spacja, twarda spacja U+00A0, wąska U+202F, tabulator, nowa
// linia…) jest jedną spacją; trafienia są przenoszone na oryginał, więc
// reszta tekstu zostaje bez zmian. Trafienia wszystkich wzorców są łączone
// (suma zakresów), każdy spójny zakres → jedno `***`.

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

/// Grupy cyfr rozdzielone „-” (także z odstępami) albo „.”
/// (600-100-200, 600 - 100 - 200, 600.100.200, 123-456-78-90). Kropka bez
/// odstępów, żeby „1200. 1500. 1800” (wymiary w zdaniach) zostało.
final RegExp _separated = RegExp(r'\b\d{2,4}(?:(?: ?- ?|\.)\d{2,4}){2,4}\b');

/// Stacjonarny: 22 123 45 67, (22) 123-45-67.
final RegExp _landline =
    RegExp(r'\(?\b\d{2}\)?[ \-.]\d{3}[ \-.]\d{2}[ \-.]\d{2}\b');

/// Komórka PL w zapisie 3-3-3 ze spacjami.
final RegExp _mobileSpaced = RegExp(r'\b[4-8]\d{2} \d{3} \d{3}\b');

/// Każdy ciąg co najmniej 9 cyfr.
final RegExp _longDigits = RegExp(r'\d{9,}');

final RegExp _digit = RegExp(r'\d');

int _digitCount(String s) => _digit.allMatches(s).length;

/// Biały znak w rozumieniu `\s` z JavaScriptu (także U+00A0, U+202F,
/// U+2000–U+200A, U+3000, U+FEFF).
bool _isSpace(int c) =>
    (c >= 0x09 && c <= 0x0D) ||
    c == 0x20 ||
    c == 0x85 ||
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000 ||
    c == 0xFEFF;

/// Zastępuje dane kontaktowe i długie ciągi cyfr znakiem [kRedactedMark].
String redactPersonalData(String text) {
  if (text.isEmpty) return text;

  // Kopia do dopasowania: każdy ciąg białych znaków = jedna spacja.
  // [from]/[to] — zakres w oryginale odpowiadający znakowi kopii.
  final copy = StringBuffer();
  final from = <int>[];
  final to = <int>[];
  var i = 0;
  while (i < text.length) {
    if (_isSpace(text.codeUnitAt(i))) {
      var j = i;
      while (j < text.length && _isSpace(text.codeUnitAt(j))) {
        j++;
      }
      copy.writeCharCode(0x20);
      from.add(i);
      to.add(j);
      i = j;
    } else {
      copy.writeCharCode(text.codeUnitAt(i));
      from.add(i);
      to.add(i + 1);
      i++;
    }
  }
  final n = copy.toString();

  final masked = List<bool>.filled(n.length, false);
  void mark(RegExp re, [int minDigits = 0]) {
    for (final m in re.allMatches(n)) {
      if (minDigits > 0 && _digitCount(m[0]!) < minDigits) continue;
      for (var k = m.start; k < m.end; k++) {
        masked[k] = true;
      }
    }
  }

  mark(_email);
  mark(_spokenEmail);
  mark(_accountGrouped);
  mark(_international, 8);
  mark(_separated, 9);
  mark(_landline);
  mark(_mobileSpaced);
  mark(_longDigits);

  if (!masked.contains(true)) return text;
  final out = StringBuffer();
  var pos = 0;
  var k = 0;
  while (k < n.length) {
    if (!masked[k]) {
      k++;
      continue;
    }
    var e = k;
    while (e < n.length && masked[e]) {
      e++;
    }
    out
      ..write(text.substring(pos, from[k]))
      ..write(kRedactedMark);
    pos = to[e - 1];
    k = e;
  }
  out.write(text.substring(pos));
  return out.toString();
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
