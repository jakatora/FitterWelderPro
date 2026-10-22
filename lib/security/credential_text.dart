// Deliberately narrow local guard for labelled credentials and known key shapes.
// It is not a detector for arbitrary unlabeled secrets or general personal data.
const credentialInputNoticePl =
    'Dane logowania wpisz wyłącznie w formularzu konta. Ta wiadomość nie została wysłana do AI ani dodana do historii.';
const credentialInputNoticeEn =
    'Enter sign-in details only in the account form. This message was not sent to AI or added to history.';
const credentialRedactedText = '***';
const _labels =
    r'(?:hasło|haslo|password|passwd|pwd|pin|otp|api[ _-]?key|klucz api|access[ _-]?token|refresh[ _-]?token|token dost[eę]pu|kod (?:logowania|weryfikacyjny|dost[eę]pu)|verification code|one[ -]time (?:password|code))';
final _assigned = RegExp('($_labels)' r'''["']?\s*[:=]\s*(\S+)''',
    caseSensitive: false, unicode: true);
final _owned = RegExp(
    r'\b(?:moje|moj|mój|my)\s+'
    '$_labels'
    r'\s*(?:[:=]|\b(?:to|is|jest|wynosi)\b)\s*\S+',
    caseSensitive: false,
    unicode: true);
final _bare =
    RegExp('($_labels)' r'\s+(\S+)', caseSensitive: false, unicode: true);
final _auth = RegExp(
    r'\b(?:zaloguj|zalogowac|zalogować|login|log in|sign in|sign up|zarejestruj|zaloz konto|załóż konto)\b',
    caseSensitive: false,
    unicode: true);
final _glossary = RegExp(
    r'^(?:wyjaśnij|wyjasnij|wytłumacz|wytlumacz|zdefiniuj|co (?:to )?znaczy|co oznacza|define|explain)\b',
    caseSensitive: false,
    unicode: true);
final _keys = RegExp(
    r'\b(?:sk-ant-[A-Za-z0-9_-]{12,}|sk-[A-Za-z0-9_-]{20,}|(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{12,}|eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,})');
final _bearer = RegExp(
    r'\b(?:authorization\s*:\s*bearer\s+\S+|bearer\s+\S{16,})',
    caseSensitive: false);
final _jsonToken = RegExp(r'''["']token["']\s*:\s*["'][A-Za-z0-9_-]{20,}["']''',
    caseSensitive: false);
final _letters = RegExp(r'[A-Za-z]');
final _digits = RegExp(r'[0-9]');
final _numericCode = RegExp(r'^["\x27]?[0-9]{4,10}["\x27]?[.,!?]?$');

bool containsCredentialValue(String text) {
  if (text.isEmpty) return false;
  if (_keys.hasMatch(text) ||
      _bearer.hasMatch(text) ||
      _jsonToken.hasMatch(text) ||
      _owned.hasMatch(text)) {
    return true;
  }
  final auth = _auth.hasMatch(text);
  for (final match in _assigned.allMatches(text)) {
    final label = match[1]!.toLowerCase(), value = match[2]!;
    if ((label == 'pin' || label == 'otp') &&
        !_numericCode.hasMatch(value) &&
        value.length < 4) {
      continue;
    }
    // Polish 'hasło' also means a glossary entry, not necessarily a password.
    if (!auth &&
        _glossary.hasMatch(text) &&
        (label == 'hasło' || label == 'haslo') &&
        !(_letters.hasMatch(value) && _digits.hasMatch(value))) {
      continue;
    }
    return true;
  }
  for (final match in _bare.allMatches(text)) {
    final label = match[1]!.toLowerCase(), value = match[2]!;
    if (auth ||
        _letters.hasMatch(value) &&
            _digits.hasMatch(value) &&
            value.length >= 6 ||
        (label == 'pin' || label == 'otp') && _numericCode.hasMatch(value)) {
      return true;
    }
  }
  return false;
}

String redactCredentialText(String text) =>
    containsCredentialValue(text) ? credentialRedactedText : text;
