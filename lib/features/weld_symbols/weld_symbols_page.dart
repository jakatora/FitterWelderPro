// Symbole spawalnicze — czytnik symbolu i ściąga wg EN ISO 2553:2019
// (z odniesieniami do AWS A2.4).
//
// Problem: młody spawacz / monter dostaje rysunek warsztatowy z symbolami
// spoin i nie wie, po której stronie spawać, jaki rowek, czy liczba to a czy
// z, co znaczy n × l (e), chorągiewka, kółko. Zła strona spoiny = poprawka.
//
// Zakładki:
//   • Czytnik — spawacz wskazuje, co widzi na rysunku; aplikacja rysuje
//     symbol z przekrojem złącza i mówi zdaniem, co zrobić;
//   • Symbole — symbole podstawowe z przekrojami;
//   • Uzupełniające — lico, podkładka, dookoła, montażowa, ogon;
//   • Linia i strony — system A i B, strona strzałki / przeciwna;
//   • Wymiary — a i z (z przelicznikiem), s, przerywana, przestawna.

import 'package:flutter/material.dart';

import '../../i18n/app_language.dart';
import 'weld_symbol_builder.dart';
import 'weld_symbols_reference.dart';

class WeldSymbolsPage extends StatelessWidget {
  const WeldSymbolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
              context.tr(pl: 'Symbole spawalnicze', en: 'Welding symbols')),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: context.tr(pl: 'Czytnik', en: 'Reader')),
              Tab(text: context.tr(pl: 'Symbole', en: 'Symbols')),
              Tab(text: context.tr(pl: 'Uzupełniające', en: 'Supplementary')),
              Tab(text: context.tr(pl: 'Linia i strony', en: 'Line and sides')),
              Tab(text: context.tr(pl: 'Wymiary', en: 'Dimensions')),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            WeldSymbolBuilderView(),
            BasicSymbolsView(),
            SupplementarySymbolsView(),
            ReferenceLineView(),
            DimensionsView(),
          ],
        ),
      ),
    );
  }
}
