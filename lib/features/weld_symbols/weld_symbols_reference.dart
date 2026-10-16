// Zakładki ściągi: symbole podstawowe, uzupełniające, linia odniesienia
// i strony, wymiary (z przelicznikiem a ↔ z).

import 'package:flutter/material.dart';

import '../../domain/weld_symbols/fillet_throat.dart';
import '../../domain/weld_symbols/weld_symbol.dart';
import '../../domain/weld_symbols/weld_symbol_catalog.dart';
import '../../domain/weld_symbols/weld_symbol_description.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../widgets/number_field.dart';
import '../../widgets/readout.dart';
import 'dimension_painters.dart';
import 'joint_section.dart';
import 'weld_symbol_painter.dart';
import 'weld_symbols_widgets.dart';

EdgeInsets _listPadding(BuildContext context) => EdgeInsets.fromLTRB(
    16, 16, 16, 24 + MediaQuery.viewPaddingOf(context).bottom);

// ── Symbole podstawowe ──────────────────────────────────────────────────────

class BasicSymbolsView extends StatelessWidget {
  const BasicSymbolsView({super.key});

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    return ListView(
      key: const ValueKey('ws-basic-list'),
      padding: _listPadding(context),
      children: [
        IntroText(context.tr(
          pl: 'Symbol podstawowy mówi, JAKA to spoina. Po lewej znak z '
              'rysunku, po prawej przekrój złącza (bursztyn = spoina). '
              'Pionowa kreska pachwiny, ½V, ½Y i J jest zawsze po lewej '
              'stronie znaku.',
          en: 'The basic symbol says WHAT weld it is. Left: the sign from the '
              'drawing, right: the joint cross-section (amber = weld). The '
              'vertical line of the fillet, bevel, ½Y and J signs is always '
              'on the left.',
        )),
        for (final info in basicSymbolCatalog)
          SymbolCard(
            key: ValueKey('ws-basic-${info.kind.name}'),
            title: weldKindName(info.kind, en: en),
            subtitle: en ? info.awsEn : info.awsPl,
            body: en ? info.bodyEn : info.bodyPl,
            drawings: [
              GlyphOnLinePainter(info.kind),
              JointSectionPainter(info.kind),
            ],
          ),
        SourceNote(context.tr(
          pl: 'Wg EN ISO 2553:2019 i AWS A2.4. Przekroje są poglądowe — '
              'kąty, odstępy i progi bierz z rysunku i WPS.',
          en: 'Per EN ISO 2553:2019 and AWS A2.4. Cross-sections are '
              'illustrative — take angles, gaps and root faces from the '
              'drawing and the WPS.',
        )),
      ],
    );
  }
}

// ── Symbole uzupełniające ───────────────────────────────────────────────────

class _Supplementary {
  const _Supplementary(
      this.id, this.titlePl, this.titleEn, this.bodyPl, this.bodyEn, this.spec,
      {this.showJoint = false, this.backRun = false});

  final String id;
  final String titlePl;
  final String titleEn;
  final String bodyPl;
  final String bodyEn;
  final WeldSymbolSpec spec;
  final bool showJoint;

  /// Własny rysunek: V + półkole po drugiej stronie linii, z przekrojem.
  final bool backRun;

  List<CustomPainter> drawings(bool en) => backRun
      ? const [
          BackRunSymbolPainter(),
          JointSectionPainter(WeldKind.backingRun),
        ]
      : [WeldSymbolPainter(spec: spec, en: en, showJoint: showJoint)];
}

const List<_Supplementary> _supplementary = [
  _Supplementary(
    'back-run',
    'Ścieg od strony grani (podpawanie)',
    'Back run / backing weld',
    'Półkole płaską stroną na linii, po przeciwnej stronie linii niż symbol '
        'spoiny głównej (tu: V od strony strzałki, ścieg od grani po stronie '
        'przeciwnej). Back run kładzie się PO spoinie głównej, backing weld '
        '— PRZED nią; kolejność podaje uwaga w rozwidleniu, dodatkowa linia '
        'odniesienia albo WPS.',
    'Half circle, flat side on the line, on the opposite side of the line '
        'from the main weld symbol (here: V on the arrow side, root-side run '
        'on the other side). A back run is laid AFTER the main weld, a '
        'backing weld BEFORE it; the order comes from a note in the tail, an '
        'extra reference line or the WPS.',
    WeldSymbolSpec(kind: WeldKind.singleV),
    backRun: true,
  ),
  _Supplementary(
    'flat',
    'Lico płaskie',
    'Flat (flush) face',
    'Prosta kreska nad symbolem. Lico równe z powierzchnią. Jeśli trzeba '
        'je szlifować lub obrabiać, rysunek podaje to osobno (uwaga '
        'w rozwidleniu albo znak obróbki).',
    'A straight line over the symbol. Face level with the surface. If it '
        'must be ground or machined, the drawing says so separately (a note '
        'in the tail or a finishing symbol).',
    WeldSymbolSpec(kind: WeldKind.singleV, contour: WeldContour.flat),
    showJoint: true,
  ),
  _Supplementary(
    'convex',
    'Lico wypukłe',
    'Convex face',
    'Łuk wygięty na zewnątrz — nadlew zostaje wypukły.',
    'An arc bulging outwards — the cap stays convex.',
    WeldSymbolSpec(kind: WeldKind.singleV, contour: WeldContour.convex),
    showJoint: true,
  ),
  _Supplementary(
    'concave',
    'Lico wklęsłe',
    'Concave face',
    'Łuk wygięty do symbolu — lico wklęsłe. Przy pachwinie łuk biegnie '
        'wzdłuż skośnego boku trójkąta.',
    'An arc dipping towards the symbol — concave face. On a fillet the arc '
        'follows the sloping side of the triangle.',
    WeldSymbolSpec(contour: WeldContour.concave),
    showJoint: true,
  ),
  _Supplementary(
    'backing-m',
    'Podkładka stała — M',
    'Permanent backing strip — M',
    'Litera M w prostokącie, po drugiej stronie linii niż symbol spoiny '
        '(od strony grani). Podkładka zostaje w złączu.',
    'Letter M in a box, on the other side of the line from the weld symbol. '
        'The strip stays in the joint.',
    WeldSymbolSpec(
        kind: WeldKind.singleV,
        system: SymbolSystem.b,
        backing: BackingStrip.permanent),
    showJoint: true,
  ),
  _Supplementary(
    'backing-mr',
    'Podkładka usuwana — MR',
    'Removable backing strip — MR',
    'Litery MR w prostokącie. Podkładkę zdejmuje się po spawaniu. Pusty '
        'prostokąt = podkładka bez określenia rodzaju.',
    'Letters MR in a box. The strip is removed after welding. An empty box '
        '= backing strip, type not specified.',
    WeldSymbolSpec(
        kind: WeldKind.singleV,
        system: SymbolSystem.b,
        backing: BackingStrip.removable),
    showJoint: true,
  ),
  _Supplementary(
    'all-around',
    'Spoina dookoła',
    'Weld all around',
    'Kółko na załamaniu strzałki i linii odniesienia. Spoina po całym '
        'obwodzie — np. rura w kołnierzu, profil przyspawany do blachy. Nie '
        'stosuje się go, gdy spoina jest nieciągła albo zmienia rodzaj lub '
        'wymiar na obwodzie.',
    'A circle where the arrow meets the reference line. The weld goes round '
        'the whole perimeter — e.g. a pipe in a flange, a section on a plate. '
        'Not used when the weld is not continuous or changes type or size '
        'round the perimeter.',
    WeldSymbolSpec(size: 4, allAround: true),
  ),
  _Supplementary(
    'field',
    'Spoina montażowa',
    'Field (site) weld',
    'Chorągiewka na załamaniu strzałki. Spoinę wykonuje się na budowie / '
        'przy montażu, nie w warsztacie.',
    'A flag where the arrow meets the reference line. The weld is made on '
        'site / at erection, not in the shop.',
    WeldSymbolSpec(size: 4, fieldWeld: true),
  ),
  _Supplementary(
    'tail',
    'Rozwidlenie (ogon) — proces i odwołania',
    'Tail — process and references',
    'Rozwidlenie na końcu linii odniesienia. W nim numer procesu wg EN ISO '
        '4063 (111 — elektroda otulona, 135 — MAG, 141 — TIG), poziom jakości '
        '(np. ISO 5817-C), pozycja, spoiwo i inne odwołania, rozdzielone '
        'ukośnikiem. Rozwidlenie zamknięte w ramkę = odwołanie do osobnego '
        'dokumentu.',
    'A fork at the end of the reference line. It carries the process number '
        'to EN ISO 4063 (111 — covered electrode, 135 — MAG, 141 — TIG), the '
        'quality level (e.g. ISO 5817-C), position, filler and other '
        'references, separated by slashes. A closed (boxed) tail = reference '
        'to a separate document.',
    WeldSymbolSpec(size: 4, process: '111', reference: 'WPS-01'),
  ),
];

class SupplementarySymbolsView extends StatelessWidget {
  const SupplementarySymbolsView({super.key});

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    return ListView(
      key: const ValueKey('ws-supplementary-list'),
      padding: _listPadding(context),
      children: [
        IntroText(context.tr(
          pl: 'Symbole uzupełniające dopowiadają, JAK ma wyglądać spoina '
              'i GDZIE ją robić: kształt lica, podkładka, spoina dookoła, '
              'montażowa, proces w ogonie.',
          en: 'Supplementary symbols add HOW the weld must look and WHERE it '
              'is made: face shape, backing strip, all around, field weld, '
              'process in the tail.',
        )),
        for (final s in _supplementary)
          SymbolCard(
            key: ValueKey('ws-supp-${s.id}'),
            title: en ? s.titleEn : s.titlePl,
            body: en ? s.bodyEn : s.bodyPl,
            drawingHeight: s.backRun ? 110 : (s.showJoint ? 170 : 120),
            stackDrawings: s.backRun,
            drawings: s.drawings(en),
          ),
        SourceNote(context.tr(
          pl: 'Wg EN ISO 2553:2013/2019. Symbolu łagodnego przejścia lica '
              'do materiału nie ma w aplikacji — sprawdź go w normie.',
          en: 'Per EN ISO 2553:2013/2019. The "toes blended smoothly" symbol '
              'is not in the app — check it in the standard.',
        )),
      ],
    );
  }
}

// ── Linia odniesienia i strony ──────────────────────────────────────────────

class ReferenceLineView extends StatelessWidget {
  const ReferenceLineView({super.key});

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    Widget drawing(String id, WeldSymbolSpec spec, String pl, String enText) =>
        SymbolCard(
          key: ValueKey('ws-ref-$id'),
          title: context.tr(pl: pl, en: enText),
          body: describeWeldSymbol(spec, en: en).sentence,
          drawingHeight: 190,
          drawings: [WeldSymbolPainter(spec: spec, en: en)],
        );

    return ListView(
      key: const ValueKey('ws-reference-list'),
      padding: _listPadding(context),
      children: [
        IntroText(context.tr(
          pl: 'Symbol spoiny składa się ze strzałki, linii odniesienia, '
              'symbolu z wymiarami i (opcjonalnie) ogona. Strzałka dotyka '
              'złącza. Strona strzałki to ta strona złącza, którą dotyka '
              'strzałka; strona przeciwna — druga strona tego samego złącza.',
          en: 'A welding symbol is made of the arrow, the reference line, the '
              'symbol with its dimensions and (optionally) the tail. The arrow '
              'touches the joint. The arrow side is the side of the joint the '
              'arrow touches; the other side is the opposite side of the same '
              'joint.',
        )),
        SectionLabel(context.tr(
            pl: 'System A — linia ciągła i przerywana',
            en: 'System A — solid and dashed line')),
        IntroText(context.tr(
          pl: 'Liczy się, NA KTÓREJ LINII stoi symbol. Na ciągłej — strona '
              'strzałki. Na przerywanej — strona przeciwna. Linię przerywaną '
              'rysuje się zwykle pod ciągłą (na starszych rysunkach bywa nad '
              'nią). Spoina symetryczna — ten sam symbol i wymiary po obu '
              'stronach — bez linii przerywanej.',
          en: 'What counts is WHICH LINE the symbol sits on. Solid line — '
              'arrow side. Dashed line — other side. The dashed line is '
              'usually drawn below the solid one (older drawings may have it '
              'above). Symmetric weld — the same symbol and dimensions on both '
              'sides — no dashed line.',
        )),
        drawing('a-arrow', const WeldSymbolSpec(size: 5),
            'Symbol na linii ciągłej', 'Symbol on the solid line'),
        drawing('a-other', const WeldSymbolSpec(size: 5, side: WeldSide.other),
            'Symbol na linii przerywanej', 'Symbol on the dashed line'),
        drawing(
            'a-both',
            const WeldSymbolSpec(size: 5, side: WeldSide.both),
            'Symbole po obu stronach, bez przerywanej',
            'Symbols on both sides, no dashed line'),
        SectionLabel(context.tr(
            pl: 'System B — jedna linia (jak AWS)',
            en: 'System B — single line (as AWS)')),
        IntroText(context.tr(
          pl: 'Tylko linia ciągła. Liczy się, czy symbol jest POD, czy NAD '
              'linią: pod — strona strzałki, nad — strona przeciwna. Tak samo '
              'czyta się rysunki amerykańskie (AWS A2.4).',
          en: 'Solid line only. What counts is whether the symbol is BELOW or '
              'ABOVE it: below — arrow side, above — other side. American '
              'drawings (AWS A2.4) read the same way.',
        )),
        drawing(
            'b-arrow',
            const WeldSymbolSpec(size: 5, system: SymbolSystem.b),
            'Symbol pod linią',
            'Symbol below the line'),
        drawing(
            'b-other',
            const WeldSymbolSpec(
                size: 5, system: SymbolSystem.b, side: WeldSide.other),
            'Symbol nad linią',
            'Symbol above the line'),
        Container(
          margin: const EdgeInsets.only(top: 4, bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kWarn.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kWarn.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, color: kWarn, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr(
                    pl: 'Ten sam symbol NAD linią znaczy co innego w systemie '
                        'A (z linią przerywaną pod spodem: strona strzałki) '
                        'i w systemie B (strona przeciwna). Najpierw sprawdź, '
                        'czy na rysunku jest linia przerywana.',
                    en: 'The same symbol ABOVE the line means different things '
                        'in system A (with a dashed line below: arrow side) and '
                        'in system B (other side). First check whether the '
                        'drawing has a dashed line.',
                  ),
                  style: const TextStyle(
                      color: kTextSec, fontSize: 12.5, height: 1.45),
                ),
              ),
            ],
          ),
        ),
        SourceNote(context.tr(
          pl: 'Wg EN ISO 2553:2019 (systemy A i B) i AWS A2.4.',
          en: 'Per EN ISO 2553:2019 (systems A and B) and AWS A2.4.',
        )),
      ],
    );
  }
}

// ── Wymiary ─────────────────────────────────────────────────────────────────

class DimensionsView extends StatefulWidget {
  const DimensionsView({super.key});

  @override
  State<DimensionsView> createState() => _DimensionsViewState();
}

class _DimensionsViewState extends State<DimensionsView> {
  FilletSize _from = FilletSize.throat;
  final _input = TextEditingController(text: '5');

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final v = parseDecimal(_input.text);
    final result = v == null
        ? null
        : (_from == FilletSize.throat ? legFromThroat(v) : throatFromLeg(v));
    final resultLetter = _from == FilletSize.throat ? 'z' : 'a';

    return ListView(
      key: const ValueKey('ws-dimensions-list'),
      padding: _listPadding(context),
      children: [
        IntroText(context.tr(
          pl: 'Przed symbolem — wymiar przekroju (a, z, s). Za symbolem — '
              'długość albo n × l (e). Nic za symbolem — spoina ciągła na '
              'całej długości złącza.',
          en: 'Before the symbol — cross-section size (a, z, s). After the '
              'symbol — length or n × l (e). Nothing after the symbol — a '
              'continuous weld along the whole joint.',
        )),
        SectionLabel(context.tr(pl: 'Pachwina: a czy z', en: 'Fillet: a or z')),
        SymbolCard(
          key: const ValueKey('ws-dim-fillet'),
          title: context.tr(
              pl: 'a — grubość obliczeniowa, z — długość boku',
              en: 'a — throat thickness, z — leg length'),
          body: context.tr(
            pl: 'a to wysokość największego trójkąta równoramiennego '
                'wpisanego w spoinę, od narożnika do lica. z to długość boku '
                'spoiny. Litera stoi przed liczbą: a5, z7. Pachwina '
                'równoramienna w złączu pod kątem prostym: a = z / √2 ≈ 0,7 · z, '
                'z = a · √2 ≈ 1,4 · a. Uwaga: z7 to nie a7 — a7 to spoina '
                'o boku ok. 9,9 mm. Spoinę o nierównych bokach wymiaruje się '
                'przez z1 i z2, bez a.',
            en: 'a is the height of the largest isosceles triangle inscribed '
                'in the weld, from the root corner to the face. z is the leg '
                'length. The letter comes before the number: a5, z7. Equal-leg '
                'fillet in a right-angle joint: a = z / √2 ≈ 0.7 · z, '
                'z = a · √2 ≈ 1.4 · a. Note: z7 is not a7 — a7 is a weld with a '
                'leg of about 9.9 mm. Unequal legs are dimensioned by z1 and '
                'z2, without a.',
          ),
          drawingHeight: 170,
          drawings: const [FilletDimensionPainter()],
        ),
        SectionLabel(
            context.tr(pl: 'Przelicznik a i z', en: 'a and z converter')),
        SegmentedButton<FilletSize>(
          key: const ValueKey('ws-conv-from'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
                value: FilletSize.throat,
                label: Text(context.tr(pl: 'Mam a', en: 'I have a'))),
            ButtonSegment(
                value: FilletSize.leg,
                label: Text(context.tr(pl: 'Mam z', en: 'I have z'))),
          ],
          selected: {_from},
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(0, kMinTapTarget)),
          ),
          onSelectionChanged: (s) => setState(() => _from = s.first),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('ws-conv-input'),
          controller: _input,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
            labelText: _from == FilletSize.throat ? 'a (mm)' : 'z (mm)',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        Readout(
          key: const ValueKey('ws-conv-result'),
          label: _from == FilletSize.throat
              ? context.tr(pl: 'Długość boku z', en: 'Leg length z')
              : context.tr(
                  pl: 'Grubość obliczeniowa a', en: 'Throat thickness a'),
          value: result == null
              ? '—'
              : '$resultLetter ${formatWeldMmPrecise(result, en: en)}',
          unit: context.tr(
              pl: 'mm · pachwina równoramienna, 90°',
              en: 'mm · equal-leg fillet, 90°'),
          hot: true,
        ),
        const SizedBox(height: 8),
        Text(
          context.tr(
            pl: 'Tylko dla pachwiny równoramiennej i ścianek pod kątem '
                'prostym. Wymiar na rysunku jest wiążący — nie zamieniaj a na '
                'z bez zgody projektanta.',
            en: 'Only for an equal-leg fillet between walls at a right angle. '
                'The size on the drawing governs — do not swap a for z without '
                'the designer\'s approval.',
          ),
          style: const TextStyle(color: kTextMut, fontSize: 12, height: 1.4),
        ),
        SectionLabel(context.tr(
            pl: 'Spoina czołowa: głębokość wtopienia',
            en: 'Butt weld: penetration depth')),
        IntroText(context.tr(
          pl: 'Liczba przed symbolem spoiny czołowej (np. 8 przed V) to '
              'głębokość wtopienia s w mm — spoina nie musi przechodzić przez '
              'całą grubość. Brak liczby = pełny przetop. Na starszych '
              'rysunkach (ISO 2553:1992) ten sam wymiar zapisywano jako s8.',
          en: 'A number before a butt-weld symbol (e.g. 8 before a V) is the '
              'penetration depth s in mm — the weld need not go through the '
              'full thickness. No number = full penetration. Older drawings '
              '(ISO 2553:1992) wrote the same dimension as s8.',
        )),
        SectionLabel(context.tr(
            pl: 'Spoina przerywana n × l (e)',
            en: 'Intermittent weld n × l (e)')),
        SymbolCard(
          key: const ValueKey('ws-dim-intermittent'),
          title: 'a5  3 × 50 (100)',
          body: context.tr(
            pl: 'n — liczba odcinków, l — długość jednego odcinka, e — odstęp '
                '(prześwit) między sąsiednimi odcinkami. Tu: 3 odcinki po '
                '50 mm, przerwy po 100 mm. Bez n — układ l (e) na całej '
                'długości złącza.',
            en: 'n — number of segments, l — length of one segment, e — gap '
                'between neighbouring segments. Here: 3 segments of 50 mm, '
                '100 mm gaps. Without n — the l (e) pattern runs along the '
                'whole joint.',
          ),
          drawingHeight: 200,
          drawings: [
            WeldSymbolPainter(
              en: en,
              showJoint: false,
              spec: const WeldSymbolSpec(
                  size: 5,
                  intermittent: true,
                  count: 3,
                  elementLength: 50,
                  gap: 100),
            ),
          ],
        ),
        SizedBox(
          height: 90,
          child: Container(
            decoration: BoxDecoration(
              color: kBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBorder),
            ),
            child: const CustomPaint(
              painter: IntermittentPainter(count: 3, length: 50, gap: 100),
              size: Size.infinite,
            ),
          ),
        ),
        SectionLabel(context.tr(
            pl: 'Przestawna (po obu stronach)', en: 'Staggered (both sides)')),
        IntroText(context.tr(
          pl: 'Przerywana pachwina po obu stronach środnika. Na rysunku znak Z '
              'między n × l a (e), przecinający linię odniesienia. Środki '
              'odcinków po jednej stronie leżą naprzeciw środków przerw po '
              'drugiej. Bez Z odcinki leżą naprzeciw siebie (łańcuchowa).',
          en: 'Intermittent fillet on both sides of the web. On the drawing a Z '
              'between n × l and (e), crossing the reference line. Segment '
              'centres on one side face gap centres on the other. Without the '
              'Z the segments sit opposite each other (chain).',
        )),
        SizedBox(
          height: 100,
          child: Container(
            decoration: BoxDecoration(
              color: kBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBorder),
            ),
            child: const CustomPaint(
              painter: IntermittentPainter(
                  count: 3, length: 50, gap: 100, staggered: true),
              size: Size.infinite,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SourceNote(context.tr(
          pl: 'Wg EN ISO 2553:2019; znak Z przestawnej wg EN ISO 2553:2013. '
              'AWS A2.4 zapisuje przerywaną inaczej: długość-podziałka '
              '(podziałka między środkami odcinków), a przestawną pokazuje '
              'symbolami przesuniętymi wzdłuż linii.',
          en: 'Per EN ISO 2553:2019; the staggered Z per EN ISO 2553:2013. '
              'AWS A2.4 writes intermittent welds differently: length-pitch '
              '(pitch between segment centres), and shows staggering by '
              'offsetting the symbols along the line.',
        )),
      ],
    );
  }
}
