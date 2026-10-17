// Grupa spoiwa FM1–FM6 (EN ISO 9606-1 tab. 2) z oznaczenia spoiwa wpisanego
// w dzienniku spoin (`weld_journal.filler_class`, np. „ER70S-6”,
// „E 19 12 3 L R”, „ERNiCr-3”). Czysty Dart.
//
// Tab. 2 normy grupuje spoiwa wg NORMY wyrobu:
//  FM1 — ISO 2560, ISO 14341, ISO 636, ISO 14171, ISO 17632;
//  FM2 — ISO 18275, ISO 16834, ISO 26304, ISO 18276;
//  FM3 / FM4 — ISO 3580, ISO 21952, ISO 24598, ISO 17634 (FM3: Cr < 3,75 %,
//              FM4: 3,75 ≤ Cr ≤ 12 %);
//  FM5 — ISO 3581, ISO 14343, ISO 17633;
//  FM6 — ISO 14172, ISO 18274.
// Rozpoznajemy tylko oznaczenia, których norma wynika z budowy symbolu:
//  • ISO, system A: klasa wytrzymałości 35/38/42/46/50 → FM1, 55/62/69/79/89
//    → FM2; „19 9 L”, „23 12”, „22 9 3 N L”… (Cr Ni) → FM5; „Mo”, „CrMo1”,
//    „CrMo2” → FM3; „CrMo5/9/91”, „CrMoWV12” → FM4; „Ni 6082” → FM6;
//    zwarte symbole drutu „G3Si1”, „W3Ni1” (ISO 14341 / 636) → FM1;
//  • ISO 2560-B: E43xx, E49xx, E55xx, E57xx → FM1;
//  • AWS: E60xx / E70xx / E7xT / ER70S / E70C → FM1; dopisek -A1, -B1…-B5
//    → FM3; -B6, -B8, -B9, -B91 → FM4; Ni (-C1…-C3, -Ni1…3) przy klasie
//    ≤ 80 ksi → FM1; klasa ≥ 100 ksi → FM2; ER3xx, E3xx, ER4xx, 2209, 2594…
//    → FM5; ERNi…, ENi… → FM6.
// Wszystko inne (nazwy handlowe, Al, Cu, klasy niejednoznaczne jak E9018-G
// czy ER80S-D2, kilka spoiw z różnych grup) → `null`: kontrola mówi „nie da
// się porównać”, nie zgaduje.

final RegExp _kParens = RegExp(r'\([^)]*\)');
final RegExp _kStdPrefix = RegExp(
    r'^(?:(?:EN|PN-EN|DIN EN|BS EN)\s+)?(?:ISO|EN)\s*\d{3,5}(?:-\d)?(?:-[AB])?\s*:?\s*');
final RegExp _kAwsPrefix = RegExp(r'^(?:AWS|SFA)[\s-]*A?\d+\.\d+M?\s*:?\s*');
final RegExp _kContinuation = RegExp(r'^-?\s*\d+[A-Z]?$');

final RegExp _kIsoNickel = RegExp(r'\bNI\s*\d{4}\b');
final RegExp _kIsoNonSteel = RegExp(r'^(?:[SEGWT]\s*)?(?:CU|AL)\s*\d{4}');
final RegExp _kIsoB = RegExp(r'^E(\d{2})(\d{2})(?![\d])');
final RegExp _kIsoA = RegExp(r'^([EGWTSPBL])\s*(\d{2})(?:\s|$)');
final RegExp _kIsoCompactWire = RegExp(r'^[GW]\s*\d(?:SI|NI|TI|MN|MO|AL|C|$)');
final RegExp _kIsoAlloy = RegExp(r'^[EGWTS]\s+([A-Z][A-Z0-9,.]*)');

final RegExp _kAwsNickel = RegExp(r'^ER?NI[A-Z]');
final RegExp _kAwsStainless =
    RegExp(r'^ER?(?:[34]\d\d|2209|2307|2553|2594)(?!\d)');
final RegExp _kAwsCarbon = RegExp(r'^(ER|E)(\d{2,3})(S|C|T\d?|\d{2})(.*)$');
final RegExp _kAwsAlloyToken = RegExp(r'-\s*([A-Z][A-Z0-9]*)');

const Set<int> _kAwsStrength = {60, 70, 80, 90, 100, 110, 120};
const Set<int> _kStainlessCr = {13, 16, 17, 18, 19, 20, 22, 23, 25, 29};

/// Grupa FM (`'FM1'`…`'FM6'`) z oznaczenia spoiwa albo `null`, gdy
/// oznaczenie nie jest jednoznaczne. Kilka spoiw („ER70S-6 / E7018”) — jedna
/// grupa, gdy wszystkie rozpoznane i zgodne; inaczej `null`.
String? fmGroupOfFillerClass(String? raw) {
  if (raw == null) return null;
  final text = raw.toUpperCase().replaceAll(_kParens, ' ');
  String? group;
  var any = false;
  for (final part in text.split(RegExp(r'[/+;]'))) {
    final p = part.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (p.isEmpty || _kContinuation.hasMatch(p)) continue;
    final g = _fmOfDesignation(p);
    if (g == null) return null;
    if (group != null && g != group) return null;
    group = g;
    any = true;
  }
  return any ? group : null;
}

String? _fmOfDesignation(String designation) {
  var s = designation
      .replaceFirst(_kStdPrefix, '')
      .replaceFirst(_kAwsPrefix, '')
      .trim();
  if (s.isEmpty) return null;

  // ---- Nikiel, metale nieżelazne.
  if (_kIsoNickel.hasMatch(s)) return 'FM6';
  if (_kIsoNonSteel.hasMatch(s)) return null;

  // ---- AWS (bez spacji po E / ER).
  if (_kAwsNickel.hasMatch(s)) {
    // ENiFe-CI itp. — spoiwa do żeliwa, nie do stali.
    return s.contains('-CI') ? null : 'FM6';
  }
  if (_kAwsStainless.hasMatch(s)) return 'FM5';

  // ---- ISO 2560-B (E4918, E5516-N5): klasa 43–57 → ISO 2560 → FM1.
  final b = _kIsoB.firstMatch(s);
  if (b != null) {
    final cls = int.parse(b.group(1)!);
    if (const {43, 49, 55, 57}.contains(cls)) return 'FM1';
  }

  // ---- AWS stale węglowe i niskostopowe.
  final aws = _kAwsCarbon.firstMatch(s);
  if (aws != null) {
    final digits = aws.group(2)!;
    // E7018 → 70; E71T → 70 (druga cyfra to pozycja); E10018 → 100.
    final strength = digits.length == 3
        ? int.parse(digits)
        : int.parse(digits[0]) * 10;
    if (_kAwsStrength.contains(strength)) {
      return _awsGroup(strength, _kAwsAlloyToken.firstMatch(aws.group(4)!)
          ?.group(1));
    }
  }

  // ---- ISO system A (ze spacjami: „E 42 3 B”, „W 19 9 L”, „G CrMo1Si”).
  final a = _kIsoA.firstMatch(s);
  if (a != null) {
    final n = int.parse(a.group(2)!);
    if (const {35, 38, 42, 46, 50}.contains(n)) return 'FM1';
    if (const {55, 62, 69, 79, 89}.contains(n)) return 'FM2';
    if (_kStainlessCr.contains(n)) return 'FM5';
    return null;
  }
  if (_kIsoCompactWire.hasMatch(s)) return 'FM1';
  final alloy = _kIsoAlloy.firstMatch(s)?.group(1);
  if (alloy != null) {
    if (alloy.startsWith('MO')) return 'FM3';
    if (alloy.startsWith('CRMO')) {
      final m = RegExp(r'\d+').firstMatch(alloy.substring(4));
      final cr = m == null ? null : int.parse(m.group(0)!);
      if (cr == null) return null;
      if (cr <= 2) return 'FM3';
      if (cr >= 5) return 'FM4';
    }
  }
  return null;
}

String? _awsGroup(int strength, String? alloy) {
  // Dopiski wodoru (H4, H4R) i wilgoci (R) nie mówią nic o grupie.
  final a = (alloy == null || alloy.startsWith('H')) ? null : alloy;
  if (a != null) {
    if (a == 'A1') return 'FM3';
    final bm = RegExp(r'^B(\d{1,2})L?$').firstMatch(a);
    if (bm != null) {
      final n = int.parse(bm.group(1)!);
      if (n <= 5) return 'FM3';
      if (n == 6 || n == 8 || n == 9 || n == 91) return 'FM4';
      return null;
    }
    if (RegExp(r'^(C[1-3]L?|NI[1-3][A-Z0-9]*)$').hasMatch(a)) {
      return strength <= 80 ? 'FM1' : null;
    }
    return strength >= 100 ? 'FM2' : null;
  }
  if (strength <= 70) return 'FM1';
  if (strength >= 100) return 'FM2';
  return null;
}
