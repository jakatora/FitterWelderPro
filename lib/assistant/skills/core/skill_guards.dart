/// Wspólne, raz skompilowane strażniki początku wypowiedzi: „otwórz…”,
/// „do czego służy…” należą do tool.open / tool.explain, nie do umiejętności
/// liczących. RegExp tworzony w `match` kompilowałby się przy każdej
/// wypowiedzi dla każdej umiejętności.
final RegExp kOpenOrAboutStart =
    RegExp(r'^(?:otworz|pokaz|open|show|do czego)\b');

/// Jak [kOpenOrAboutStart], ale bez „pokaż/show” — dla umiejętności, które
/// same odpowiadają na „pokaż …” (rejestry, listy).
final RegExp kOpenOrAboutStartNoShow = RegExp(r'^(?:otworz|open|do czego)\b');
