import 'electrode_exposure.dart';

/// Reference defaults only. Never evaluates or mutates a stock batch.
String electrodeReferenceText(ElectrodeClass c, ElectrodeSource source,
    {required bool en}) {
  final limit = defaultLimitMinutes(c, source);
  final origin = source == ElectrodeSource.oven
      ? (en ? 'holding oven' : 'piecyk-przechowalnik')
      : (en
          ? 'freshly opened hermetic pack'
          : 'świeżo otwarte opakowanie hermetyczne');
  return [
    en
        ? 'Electrode table group: ${c.code}'
        : 'Grupa tabeli elektrod: ${c.code}',
    '${en ? "Origin" : "Pochodzenie"}: $origin',
    '${en ? "App model default exposure limit" : "Domyślny limit ekspozycji w modelu aplikacji"}: ${formatSpan(Duration(minutes: limit))} ($limit min)',
    c.desc(en: en),
    c.family.perManufacturer
        ? (en
            ? 'EN classification alone does not set this time. This is an app default/analogy; the actual product data sheet and packaging conditions govern.'
            : 'Sama klasyfikacja EN nie ustanawia tego czasu. To ustawienie domyślne/analogia modelu; wiążąca jest karta konkretnego produktu i warunki opakowania.')
        : (en
            ? 'Reference basis: AWS D1.1/D1.1M:2020, 7.3.2 / Table 7.1, column A. This does not verify the requirements of another edition or project.'
            : 'Podstawa referencyjna: AWS D1.1/D1.1M:2020, 7.3.2 / tablica 7.1, kolumna A. Nie oznacza weryfikacji wymagań innego wydania lub projektu.'),
    '${en ? "Redrying reference" : "Informacja referencyjna o suszeniu"}: ${c.family.redry(en: en)}',
    '${en ? "Default maximum redrying count in the model" : "Domyślna maksymalna liczba ponownych suszeń w modelu"}: ${defaultMaxRedries(c)}',
    en
        ? 'This reference does not create a batch, reset exposure or confirm fitness for use. Product data sheet, WPS and project procedure govern; previous exposure and moisture condition matter.'
        : 'Ta informacja nie tworzy partii, nie zeruje ekspozycji i nie potwierdza przydatności do spawania. Wiążące są karta produktu, WPS i procedura projektu; znaczenie mają wcześniejsza ekspozycja i zawilgocenie.',
  ].join('\n');
}
