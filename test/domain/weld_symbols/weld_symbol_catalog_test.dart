// Kompletność ściągi: każdy symbol podstawowy dokładnie raz, opis PL i EN,
// zdaniem (nie WERSALIKAMI). Ścieg od strony grani jest w EN ISO 2553:2019
// symbolem uzupełniającym — nie ma go wśród podstawowych.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/weld_symbols/weld_symbol.dart';
import 'package:cut_list_app/domain/weld_symbols/weld_symbol_catalog.dart';
import 'package:cut_list_app/domain/weld_symbols/weld_symbol_description.dart';

void main() {
  test('każdy symbol podstawowy dokładnie raz, bez ściegu od grani', () {
    final kinds = basicSymbolCatalog.map((e) => e.kind).toList();
    expect(kinds.toSet().length, kinds.length);
    expect(kinds.toSet(),
        WeldKind.values.toSet().difference({WeldKind.backingRun}));
  });

  test('kreator obejmuje pachwinę i wszystkie spoiny czołowe z rowkiem', () {
    expect(WeldKind.builderKinds.toSet(),
        WeldKind.values.where((k) => k.inBuilder).toSet());
    expect(WeldKind.builderKinds.first, WeldKind.fillet);
    expect(WeldKind.builderKinds.skip(1).every((k) => k.isGrooveButt), isTrue);
  });

  test('opisy PL i EN niepuste, zdaniem, z kropką na końcu', () {
    for (final e in basicSymbolCatalog) {
      for (final text in [e.bodyPl, e.bodyEn, e.awsPl, e.awsEn]) {
        expect(text.trim(), isNotEmpty, reason: e.kind.name);
        expect(text.endsWith('.'), isTrue, reason: '${e.kind.name}: $text');
        // Zdanie, nie krzyk: małych liter więcej niż wielkich.
        final upper = RegExp(r'[A-ZĄĆĘŁŃÓŚŹŻ]').allMatches(text).length;
        final lower = RegExp(r'[a-ząćęłńóśźż]').allMatches(text).length;
        expect(lower, greaterThan(upper), reason: text);
      }
    }
  });

  test('nazwy PL wg terminologii: ½U (J), na I, napawanie', () {
    expect(weldKindName(WeldKind.singleJ, en: false), 'Spoina na ½U (J)');
    expect(weldKindName(WeldKind.squareButt, en: false), 'Spoina na I');
    expect(weldKindName(WeldKind.surfacing, en: false), 'Napawanie');
    for (final k in WeldKind.values) {
      expect(weldKindName(k, en: true), isNotEmpty);
      expect(weldKindName(k, en: false), isNotEmpty);
    }
  });
}
