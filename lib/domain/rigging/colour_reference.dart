import 'rigging_colors.dart';

/// The colour of a sewn label is a material code, not a WLL colour.
const slingTagMaterials = <SlingColour, String>{
  SlingColour.blue: 'PES',
  SlingColour.green: 'PA',
  SlingColour.brown: 'PP',
};
String slingColourReference(SlingColour colour,
    {required bool tag, required bool en}) {
  if (tag) {
    final material = switch (slingTagMaterials[colour]) {
      'PES' => en ? 'polyester (PES)' : 'poliester (PES)',
      'PA' => en ? 'polyamide (PA)' : 'poliamid (PA)',
      'PP' => en ? 'polypropylene (PP)' : 'polipropylen (PP)',
      _ => null,
    };
    return '${en ? "Label colour" : "Kolor etykiety"}: ${colour.label(en: en)} — ${material ?? (en ? "outside the material code" : "poza kodem materiału")}.'
        '\n${en ? "This identifies material, not lifting capacity. Read WLL from the label and assess the hitch, angle and condition separately." : "To oznaczenie materiału, nie nośności. WLL odczytaj z etykiety; osobno oceń układ, kąt i stan zawiesia."}';
  }
  final t = colour.nominalT;
  return '${en ? "Textile sling colour" : "Kolor tekstylnego pasa/zawiesia"}: ${colour.label(en: en)}.'
      '\n${en ? "Reference WLL for a straight lift" : "Referencyjne WLL przy podnoszeniu prostym"}: ${t == null ? (en ? "no colour code" : "brak kodu") : '${t.toStringAsFixed(0)} t${colour.orAbove ? (en ? " and above" : " i więcej") : ""}'}.'
      '\n${en ? "EN 1492-1/-2 colour code. This is not the capacity of your lifting arrangement. The legible label governs; a missing/unreadable label means STOP. Never infer label data or completed inspection from colour." : "Kod kolorów EN 1492-1/-2. To nie jest nośność Twojego układu podnoszenia. Decyduje czytelna etykieta; brak lub nieczytelna etykieta oznacza STOP. Kolor nie potwierdza danych etykiety ani wykonania kontroli."}';
}
