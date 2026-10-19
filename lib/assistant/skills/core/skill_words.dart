// Wspólne słowa i formatowanie umiejętności z grupy „core".

import '../../../i18n/app_language.dart';
import '../../assistant_validator.dart' show assistantNumber;
import '../../core/utterance.dart';

/// Czasowniki poleceń zapisu i rysowania („dodaj zawór", „zapisz TIG…",
/// „narysuj rurę") — przy nich pytania o liczby z tabel nie trafiają.
final RegExp kCommandVerbRe = RegExp(
    r'\b(?:zapisz|zapamietaj|zanotuj|dodaj|dopisz|wpisz|save|store|remember|'
    r'record|add|log|narysuj|rysuj|dorysuj|draw|wstaw|insert)\b');

/// „Otwórz / pokaż / włącz…" na początku zdania (jak w starym parserze).
final RegExp kOpenVerbAtStartRe = RegExp(
    r'^(?:(?:prosze|please|hej|hey|ok|okej|asystencie|asystent)\s+)*'
    r'(?:otworz|pokaz|uruchom|wlacz|przejdz do|idz do|open|show|launch|start|'
    r'go to|take me to)\b');

/// Słowa ciężaru — pytanie o masę to inny moduł (pipe_weight, steel_weight).
bool mentionsWeight(Utterance u) =>
    u.hasStem(const ['waz', 'waga', 'wagi', 'ciezar', 'masa', 'masy', 'weigh']) ||
    u.hasAny(const ['kg', 'kilogram', 'kilogramow', 'mass']);

/// Słowa ścianki i harmonogramu.
bool mentionsWall(Utterance u) =>
    u.hasStem(const ['sciank', 'grubos', 'schedul', 'szedul', 'szedzul']) ||
    u.hasAny(const ['wall', 'walls', 'thickness', 'sch']);

/// Słowa spawania (prąd, proces) — „jaka ścianka na TIG 60 A" to nie tabela.
bool mentionsWelding(Utterance u) {
  if (u.hasStem(const ['amper', 'amp', 'prad', 'spaw', 'elektrod', 'drut']) ||
      u.hasAny(const ['tig', 'mig', 'mag', 'mma', 'weld', 'welding'])) {
    return true;
  }
  // „60 A" — liczba z jednostką ampera (samo „a" to spójnik).
  final items = u.items;
  for (var i = 0; i + 1 < items.length; i++) {
    if (items[i].isNumber && !items[i + 1].isNumber && items[i + 1].word == 'a') {
      return true;
    }
  }
  return false;
}

/// Kształtki — „wymiar kolana DN50" to moduł kolan, nie „DN ↔ mm".
bool mentionsFitting(Utterance u) =>
    u.hasStem(const [
      'kolan', 'luk', 'trojnik', 'redukc', 'zawor', 'kolnierz', 'zaslep',
      'denn', 'elbow', 'tee', 'reducer', 'valve', 'flange', 'cap',
    ]);

/// Liczba po polsku/angielsku: 48.3 → „48,3" / „48.3" (bez zbędnych zer).
String fmt(double v, AppLanguage lang) => assistantNumber(v, lang);

/// „milimetr" w dobrej formie po liczbie (TTS czyta „mm" jako „em em").
String plMillimetres(double v) {
  if (v != v.roundToDouble()) return 'milimetra';
  final n = v.toInt();
  if (n == 1) return 'milimetr';
  final d = n % 10, t = n % 100;
  if (d >= 2 && d <= 4 && (t < 12 || t > 14)) return 'milimetry';
  return 'milimetrów';
}

/// „millimetre(s)".
String enMillimetres(double v) => v == 1 ? 'millimetre' : 'millimetres';

final _numberRe = RegExp(r'^[\d.]+$');

/// Liczba słów treści spoza słownika umiejętności — każde obniża wynik
/// (zdanie o czymś innym, w którym przypadkiem padło „DN40").
int unknownWords(Utterance u, Set<String> vocabulary,
    {List<String> stems = const []}) {
  var n = 0;
  for (final t in u.tokens) {
    if (t.length < 3) continue;
    if (_numberRe.hasMatch(t)) continue;
    if (vocabulary.contains(t)) continue;
    if (stems.any(t.startsWith)) continue;
    n++;
  }
  return n;
}

/// Słowa, które nie mówią nic o temacie (pytajniki, grzeczności, spójniki).
const Set<String> kNeutralWords = {
  // PL
  'jaka', 'jaki', 'jakie', 'jakiej', 'jakiego', 'jest', 'ile', 'maja',
  'dla', 'prosze', 'powiedz', 'hej', 'okej', 'asystent', 'asystencie', 'czy',
  'wiesz', 'mam', 'wynosi', 'daje', 'ktora', 'ktory', 'sprawdz', 'podaj',
  'pokaz', 'otworz', 'tabela', 'tabeli', 'tabelce', 'jeszcze', 'teraz',
  'dobra', 'dobrze', 'eee', 'yyy', 'tez', 'tej', 'tego', 'ten', 'mnie',
  'nam', 'sie', 'bedzie', 'byla', 'byl', 'moze', 'chce', 'chcialbym',
  // EN
  'what', 'whats', 'the', 'for', 'how', 'many', 'much', 'and', 'about',
  'tell', 'please', 'show', 'open', 'table', 'check', 'give', 'need', 'want',
  'does', 'have', 'has', 'with', 'this', 'that', 'there', 'again', 'now',
};
