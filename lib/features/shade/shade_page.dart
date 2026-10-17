// Filtr przyłbicy: stopień zaciemnienia. Proces + prąd (przy gazie:
// przepływ i grubość) → zalecany numer skali wg EN 169 i dla porównania
// wg ANSI Z49.1 / OSHA. Tabele, źródła i rozbieżności:
// domain/welding/shade_number.dart.
//
// Zasady ekranu: puste pole to komunikat, nie wynik; na granicy przedziału
// wyższy stopień; poza tabelą — nie zgadujemy w dół (najniższy przedział
// albo „co najmniej”) i ostrzegamy. „Bezpiecznie”: zacznij od ciemniejszego
// z obu źródeł i rozjaśniaj, ale nie poniżej minimum OSHA ani EN 169 − 1.
// Bez zapisu i bez bazy.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/welding/shade_number.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_helper.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import '../../widgets/readout.dart';
import '../quotes/quote_widgets.dart';

/// Udostępnienie tekstu — wstrzykiwane w testach.
typedef ShadeShareText = Future<void> Function(String text, String subject);

Future<void> _defaultShareText(String text, String subject) async {
  await Share.share(text, subject: subject);
}

class ShadePage extends StatefulWidget {
  const ShadePage({super.key, this.shareText = _defaultShareText});

  final ShadeShareText shareText;

  @override
  State<ShadePage> createState() => _ShadePageState();
}

class _ShadePageState extends State<ShadePage> {
  final _current = TextEditingController();
  final _flow = TextEditingController();
  final _thickness = TextEditingController();

  ShadeProcess _process = ShadeProcess.mma;
  bool _sharing = false;

  @override
  void dispose() {
    for (final c in [_current, _flow, _thickness]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _en => context.language == AppLanguage.en;

  /// Pole: puste → null, nieczytelne → NaN (domena odróżnia oba).
  double? _read(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return parseDecimal(t) ?? double.nan;
  }

  ShadeInput get _input => ShadeInput(
        process: _process,
        currentA: _read(_current),
        gasFlowLh: _read(_flow),
        thicknessMm: _read(_thickness),
      );

  String _v(double v) => formatShadeValue(v, en: _en);

  // ── Udostępnianie ──────────────────────────────────────────────────────

  Future<void> _share(ShadeAdvice a) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final text = shadeShareText(a, en: _en);
      unawaited(Haptic.tap());
      await widget.shareText(
          text,
          context.tr(
              pl: 'Stopień zaciemnienia filtra', en: 'Welding filter shade'));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(
              pl: 'Nie udało się udostępnić wyniku.',
              en: 'Could not share the result.'))));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  // ── Budowa ekranu ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final input = _input;
    final problems = shadeProblems(input);
    final advice = computeShade(input);

    return Scaffold(
      appBar: AppBar(
          title: Text(context.tr(
              pl: 'Filtr przyłbicy: stopień zaciemnienia',
              en: 'Welding filter: shade number'))),
      body: ListView(
        key: const ValueKey('shade-list'),
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _processSection(),
          _inputSection(problems),
          if (advice == null && _missing(problems))
            KeyedSubtree(
              key: const ValueKey('shade-prompt'),
              child: QuoteNotice(
                color: kTextSec,
                icon: Icons.edit_outlined,
                text: _process.isGas
                    ? context.tr(
                        pl: 'Podaj przepływ gazu (EN 169) albo grubość '
                            'materiału (ANSI/OSHA) — wtedy pokażę stopień.',
                        en: 'Enter the gas flow (EN 169) or the material '
                            'thickness (ANSI/OSHA) to see the shade.')
                    : context.tr(
                        pl: 'Podaj prąd (A) — z ustawień źródła albo z WPS. '
                            'Bez prądu nie ma stopnia.',
                        en: 'Enter the current (A) — from the power source '
                            'or the WPS. No current, no shade.'),
              ),
            ),
          if (advice != null) ...[
            _resultSection(advice),
            ..._warnings(advice),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton.icon(
                key: const ValueKey('shade-share'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: kArc,
                  foregroundColor: kOnArc,
                ),
                onPressed: _sharing ? null : () => unawaited(_share(advice)),
                icon: const Icon(Icons.share_outlined),
                label: Text(
                    context.tr(pl: 'Udostępnij wynik', en: 'Share the result'),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
          _rowSection(advice),
          _notesSection(),
          KeyedSubtree(
            key: const ValueKey('shade-sources'),
            child: QuoteNotice(
              color: kWarn,
              icon: Icons.menu_book_outlined,
              text: context.tr(
                  pl: 'Źródła: EN 169:2002 — tabela doboru (norma wycofana '
                      'w 2022 r., zastąpiona przez EN ISO 16321; tabela za '
                      'DGUV Regel 112-192 zał. 2 i DGUV Information 209-010, '
                      'tabl. 3). OSHA 29 CFR 1910.133(a)(5) — minimum. '
                      'ANSI Z49.1:2005 — zalecany (za OSHA FS-3499). '
                      'Orientacyjnie: decyduje instrukcja przyłbicy i ocena '
                      'ryzyka na stanowisku.',
                  en: 'Sources: EN 169:2002 — selection table (withdrawn in '
                      '2022, replaced by EN ISO 16321; table via DGUV Regel '
                      '112-192 annex 2 and DGUV Information 209-010, table 3). '
                      'OSHA 29 CFR 1910.133(a)(5) — minimum. ANSI Z49.1:2005 '
                      '— suggested (via OSHA FS-3499). Guidance only: the '
                      'helmet manual and the workplace risk assessment '
                      'govern.'),
            ),
          ),
        ],
      ),
    );
  }

  bool _missing(List<ShadeProblem> p) =>
      p.contains(ShadeProblem.currentMissing) ||
      p.contains(ShadeProblem.gasInputMissing);

  Widget _caption(String text, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.only(top: 8),
        child: Text(text,
            style:
                const TextStyle(fontSize: 12, color: kTextMut, height: 1.35)),
      );

  Widget _field(TextEditingController c, String label,
          {required Key key,
          required String unit,
          String? helper,
          String? error}) =>
      TextField(
        key: key,
        controller: c,
        keyboardType: numberKeyboard(),
        inputFormatters: numberInputFormatters(),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          helperText: helper,
          helperMaxLines: 3,
          errorText: error,
          errorMaxLines: 3,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  // ── Wejście ────────────────────────────────────────────────────────────

  Widget _processSection() {
    return QuoteSection(
      title: context.tr(pl: 'Proces', en: 'Process'),
      children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in ShadeProcess.values)
            ChoiceChip(
              key: ValueKey('shade-proc-${p.name}'),
              label: Text(p.label(en: _en)),
              selected: _process == p,
              onSelected: (_) => setState(() => _process = p),
            ),
        ]),
        _caption(_processNote(_process),
            key: const ValueKey('shade-proc-note')),
      ],
    );
  }

  String _processNote(ShadeProcess p) => switch (p) {
        ShadeProcess.mma => context.tr(
            pl: 'EN 169: „elektrody otulone”. ANSI: SMAW.',
            en: 'EN 169: "covered electrodes". ANSI: SMAW.'),
        ShadeProcess.mag => context.tr(
            pl: 'Drut lity i proszkowy w osłonie gazu. EN 169: „MAG”. '
                'ANSI: GMAW i FCAW.',
            en: 'Solid and flux-cored wire with shielding gas. EN 169: '
                '"MAG". ANSI: GMAW and FCAW.'),
        ShadeProcess.migHeavy => context.tr(
            pl: 'EN 169: „MIG na metalach ciężkich” — stale, stale stopowe, '
                'miedź i jej stopy. ANSI nie rozróżnia metalu (GMAW).',
            en: 'EN 169: "MIG with heavy metals" — steels, alloy steels, '
                'copper and its alloys. ANSI does not split by metal (GMAW).'),
        ShadeProcess.migLight => context.tr(
            pl: 'EN 169: „MIG na stopach lekkich” (aluminium). Przy tym samym '
                'prądzie tabela daje do 1 stopnia ciemniej niż dla stali. '
                'ANSI nie rozróżnia metalu (GMAW).',
            en: 'EN 169: "MIG with light alloys" (aluminium). At the same '
                'current the table gives up to 1 shade darker than for '
                'steel. ANSI does not split by metal (GMAW).'),
        ShadeProcess.tig => context.tr(
            pl: 'EN 169: „TIG”, tabela od 10 A. ANSI: GTAW.',
            en: 'EN 169: "TIG", table from 10 A. ANSI: GTAW.'),
        ShadeProcess.arcGouging => context.tr(
            pl: 'Elektroda węglowa i sprężone powietrze. ANSI: CAC-A.',
            en: 'Carbon electrode and compressed air. ANSI: CAC-A.'),
        ShadeProcess.plasmaCutting => context.tr(
            pl: 'EN 169 obejmuje cięcie plazmowe od 100 A. OSHA: wartości dla '
                'łuku widocznego wprost — gdy łuk zasłania cięty materiał, '
                'można jaśniej.',
            en: 'EN 169 covers plasma cutting from 100 A. OSHA: values for an '
                'arc seen directly — when the workpiece hides the arc, a '
                'lighter filter may be used.'),
        ShadeProcess.plasmaWelding => context.tr(
            pl: 'EN 169: wiersz „spawanie mikroplazmowe” (w tabeli do 300 A). '
                'ANSI: PAW.',
            en: 'EN 169: the "microplasma arc welding" row (up to 300 A in '
                'the table). ANSI: PAW.'),
        ShadeProcess.gasWelding => context.tr(
            pl: 'EN 169 dobiera po przepływie acetylenu — podaje go producent '
                'palnika dla nasadki. ANSI/OSHA — po grubości materiału. '
                'Z topnikiem (np. aluminium) płomień świeci na żółto — OSHA '
                'zaleca filtr pochłaniający żółtą linię sodu.',
            en: 'EN 169 selects by acetylene flow — the torch maker gives it '
                'for each tip. ANSI/OSHA — by material thickness. With flux '
                '(e.g. aluminium) the flame glows yellow — OSHA recommends a '
                'filter that absorbs the yellow sodium line.'),
        ShadeProcess.oxyCutting => context.tr(
            pl: 'EN 169 dobiera po przepływie tlenu tnącego (cięcie wzdłuż '
                'linii). ANSI/OSHA — po grubości materiału.',
            en: 'EN 169 selects by cutting oxygen flow (cutting along a '
                'line). ANSI/OSHA — by material thickness.'),
      };

  Widget _inputSection(List<ShadeProblem> problems) {
    final notNumber = context.tr(
        pl: 'Wpisz liczbę większą od 0.', en: 'Enter a number greater than 0.');
    if (!_process.isGas) {
      final cutting = _process == ShadeProcess.plasmaCutting ||
          _process == ShadeProcess.arcGouging;
      return QuoteSection(
        title: context.tr(pl: 'Parametry', en: 'Parameters'),
        children: [
          _field(
            _current,
            cutting
                ? context.tr(
                    pl: 'Prąd cięcia / żłobienia I',
                    en: 'Cutting / gouging current I')
                : context.tr(pl: 'Prąd spawania I', en: 'Welding current I'),
            key: const ValueKey('shade-current'),
            unit: 'A',
            error: problems.contains(ShadeProblem.currentInvalid)
                ? notNumber
                : null,
          ),
        ],
      );
    }
    final oxy = _process == ShadeProcess.oxyCutting;
    return QuoteSection(
      title: context.tr(pl: 'Parametry', en: 'Parameters'),
      children: [
        _field(
          _flow,
          oxy
              ? context.tr(
                  pl: 'Przepływ tlenu tnącego (EN 169)',
                  en: 'Cutting oxygen flow (EN 169)')
              : context.tr(
                  pl: 'Przepływ acetylenu (EN 169)',
                  en: 'Acetylene flow (EN 169)'),
          key: const ValueKey('shade-flow'),
          unit: 'l/h',
          helper: context.tr(
              pl: 'Z tabeli producenta palnika dla tej nasadki.',
              en: 'From the torch maker\'s table for this tip.'),
          error: problems.contains(ShadeProblem.flowInvalid) ? notNumber : null,
        ),
        const SizedBox(height: 12),
        _field(
          _thickness,
          context.tr(
              pl: 'Grubość materiału (ANSI/OSHA)',
              en: 'Material thickness (ANSI/OSHA)'),
          key: const ValueKey('shade-thickness'),
          unit: 'mm',
          error: problems.contains(ShadeProblem.thicknessInvalid)
              ? notNumber
              : null,
        ),
      ],
    );
  }

  // ── Wynik ──────────────────────────────────────────────────────────────

  Widget _resultSection(ShadeAdvice a) {
    final e = a.en;
    final s = a.ansi;
    final children = <Widget>[];
    if (e != null) {
      children.add(Readout(
        key: const ValueKey('shade-en'),
        label: 'EN 169',
        value: formatShade(e),
        unit: context.tr(
            pl: 'stopień · ${formatBand(e, en: _en)}',
            en: 'shade · ${formatBand(e, en: _en)}'),
        hot: true,
      ));
    } else if (s != null) {
      children.add(Readout(
        key: const ValueKey('shade-ansi-main'),
        label: context.tr(
            pl: 'ANSI Z49.1 — zalecany', en: 'ANSI Z49.1 — suggested'),
        value: formatAnsiSuggested(s),
        unit: context.tr(
            pl: 'stopień · ${formatBand(s, en: _en)}',
            en: 'shade · ${formatBand(s, en: _en)}'),
        hot: true,
      ));
      children.add(_caption(context.tr(
          pl: 'EN 169 dobiera po przepływie gazu — podaj go, żeby porównać.',
          en: 'EN 169 selects by gas flow — enter it to compare.')));
    }
    children.add(const SizedBox(height: 12));
    if (s != null) {
      final code = a.process.ansiCode;
      children.add(_kv(
          context.tr(
              pl: 'ANSI Z49.1 — zalecany ($code)',
              en: 'ANSI Z49.1 — suggested ($code)'),
          formatAnsiSuggested(s),
          valueKey: 'shade-ansi-suggested'));
      children.add(_kv(context.tr(pl: 'OSHA — minimum', en: 'OSHA — minimum'),
          formatShade(s),
          valueKey: 'shade-osha-min'));
      children.add(_kv(
          context.tr(pl: 'Przedział ANSI/OSHA', en: 'ANSI/OSHA band'),
          formatBand(s, en: _en),
          valueKey: 'shade-ansi-band'));
      if (s.band.suggestedHigh == null) {
        children.add(_caption(context.tr(
            pl: 'ANSI nie podaje tu zalecanego stopnia — tylko minimum.',
            en: 'ANSI gives no suggested shade here — only the minimum.')));
      }
    } else {
      children.add(_caption(context.tr(
          pl: 'ANSI/OSHA dobiera po grubości materiału — podaj ją, żeby '
              'porównać.',
          en: 'ANSI/OSHA selects by material thickness — enter it to '
              'compare.')));
    }
    children.add(const SizedBox(height: 12));
    final start = a.startShade;
    final floor = a.floorShade;
    children.add(KeyedSubtree(
      key: const ValueKey('shade-safe'),
      child: QuoteNotice(
        color: kPass,
        icon: Icons.shield_outlined,
        text: start == floor
            ? context.tr(
                pl: 'Bezpiecznie: stopień $start — nie jaśniej.',
                en: 'Safe choice: shade $start — not lighter.')
            : context.tr(
                pl: 'Bezpiecznie: zacznij od $start i rozjaśniaj, aż dobrze '
                    'widzisz jeziorko i krawędzie — nie jaśniej niż $floor '
                    '(minimum OSHA, EN 169 ±1).',
                en: 'Safe choice: start at $start and go lighter until you '
                    'see the pool and edges well — not lighter than $floor '
                    '(OSHA minimum, EN 169 ±1).'),
      ),
    ));
    return QuoteSection(
      title: context.tr(pl: 'Stopień zaciemnienia', en: 'Shade number'),
      subtitle: context.tr(
          pl: 'Gdy źródła się różnią — ciemniej. Na granicy przedziału — '
              'wyższy stopień.',
          en: 'When the sources differ — darker. On a band boundary — the '
              'higher shade.'),
      children: children,
    );
  }

  List<Widget> _warnings(ShadeAdvice a) {
    final e = a.en;
    final s = a.ansi;
    final out = <Widget>[];
    String what(ShadeLookup l) =>
        shadeQuantityName(a.process, l.table.unit, en: _en);
    if (e != null && e.range == ShadeRange.below) {
      out.add(KeyedSubtree(
        key: const ValueKey('shade-en-below'),
        child: QuoteNotice(
          color: kFail,
          icon: Icons.warning_amber_outlined,
          text: context.tr(
              pl: '${what(e)} ${_v(e.value)} ${e.table.unit.symbol} — poniżej '
                  'tabeli EN 169 dla tego procesu '
                  '(${formatTableRange(e.table, en: false)}). Pokazano stopień '
                  'z najniższego przedziału: ${e.shade}. Tabela nie podaje '
                  'jaśniejszego filtra — nie dobieraj go „na oko”.',
              en: '${what(e)} ${_v(e.value)} ${e.table.unit.symbol} — below '
                  'the EN 169 table for this process '
                  '(${formatTableRange(e.table, en: true)}). Shown: the shade '
                  'of the lowest band, ${e.shade}. The table gives no lighter '
                  'filter — do not guess one.'),
        ),
      ));
    }
    if (e != null && e.range == ShadeRange.above) {
      out.add(KeyedSubtree(
        key: const ValueKey('shade-en-above'),
        child: QuoteNotice(
          color: kFail,
          icon: Icons.warning_amber_outlined,
          text: context.tr(
              pl: '${what(e)} ${_v(e.value)} ${e.table.unit.symbol} — powyżej '
                  'tabeli EN 169 dla tego procesu '
                  '(${formatTableRange(e.table, en: false)}). Co najmniej '
                  '${e.shade}; jeśli łuk razi — ciemniej. Sprawdź instrukcję '
                  'przyłbicy.',
              en: '${what(e)} ${_v(e.value)} ${e.table.unit.symbol} — above '
                  'the EN 169 table for this process '
                  '(${formatTableRange(e.table, en: true)}). At least '
                  '${e.shade}; darker if the arc dazzles. Check the helmet '
                  'manual.'),
        ),
      ));
    }
    if (s != null && s.range == ShadeRange.above) {
      out.add(KeyedSubtree(
        key: const ValueKey('shade-ansi-above'),
        child: QuoteNotice(
          color: kFail,
          icon: Icons.warning_amber_outlined,
          text: context.tr(
              pl: '${what(s)} ${_v(s.value)} ${s.table.unit.symbol} — powyżej '
                  'tabeli ANSI/OSHA (${formatTableRange(s.table, en: false)}). '
                  'Minimum co najmniej ${s.shade}, zalecany co najmniej '
                  '${s.band.suggestedHigh ?? s.shade}.',
              en: '${what(s)} ${_v(s.value)} ${s.table.unit.symbol} — above '
                  'the ANSI/OSHA table (${formatTableRange(s.table, en: true)}). '
                  'Minimum at least ${s.shade}, suggested at least '
                  '${s.band.suggestedHigh ?? s.shade}.'),
        ),
      ));
    }
    if (a.startShade > kTypicalAutoDarkeningMax) {
      out.add(KeyedSubtree(
        key: const ValueKey('shade-over13'),
        child: QuoteNotice(
          color: kWarn,
          icon: Icons.info_outline,
          text: context.tr(
              pl: 'Wiele przyłbic samościemniających ma najciemniej 13 '
                  '(np. 3M Speedglas 9100: 5, 8, 9–13). Stopień '
                  '${a.startShade} wymaga filtra, który go ma — sprawdź '
                  'oznaczenie swojego.',
              en: 'Many auto-darkening helmets go no darker than 13 (e.g. '
                  '3M Speedglas 9100: 5, 8, 9–13). Shade ${a.startShade} '
                  'needs a filter that has it — check your marking.'),
        ),
      ));
    }
    return out;
  }

  /// Cały wiersz EN 169 procesu — do doboru zakresu filtra przy zakupie.
  Widget _rowSection(ShadeAdvice? a) {
    final t = en169Table(_process);
    final current = a?.en;
    final rows = <Widget>[];
    var lower = t.from;
    for (final b in t.bands) {
      final l = ShadeLookup(
          table: t,
          band: b,
          from: lower,
          range: ShadeRange.within,
          value: lower);
      final on = current != null && current.band.upTo == b.upTo;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(
            width: 40,
            child: Text('${b.shade}',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: on ? kArc : kText,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          Expanded(
            child: Text(formatBand(l, en: _en),
                style: TextStyle(
                    fontSize: 13.5,
                    color: on ? kArc : kTextSec,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w400)),
          ),
        ]),
      ));
      lower = b.upTo;
    }
    return KeyedSubtree(
      key: const ValueKey('shade-row'),
      child: QuoteSection(
        title: context.tr(
            pl: 'Tabela EN 169 — ${_process.label(en: false)}',
            en: 'EN 169 table — ${_process.label(en: true)}'),
        subtitle: context.tr(
            pl: 'Cały zakres procesu — przy zakupie filtra albo przyłbicy '
                'sprawdź, czy ma potrzebne stopnie.',
            en: 'The whole range of the process — when buying a filter or '
                'helmet check that it has the shades you need.'),
        children: rows,
      ),
    );
  }

  // ── Uwagi ──────────────────────────────────────────────────────────────

  Widget _note(String key, String title, String body) => Padding(
        key: ValueKey(key),
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: kText)),
            const SizedBox(height: 4),
            Text(body,
                style: const TextStyle(
                    fontSize: 13, color: kTextSec, height: 1.4)),
          ],
        ),
      );

  Widget _notesSection() {
    return QuoteSection(
      key: const ValueKey('shade-notes'),
      title: context.tr(pl: 'Ważne', en: 'Important'),
      children: [
        _note(
          'shade-note-bystanders',
          context.tr(pl: 'Pomocnik i osoby obok', en: 'Helper and bystanders'),
          context.tr(
              pl: 'Kto patrzy na łuk — pomocnik, dozór pożarowy — potrzebuje '
                  'tego samego stopnia co spawacz (OSHA FS-3499). Pomocnik, '
                  'który nie patrzy wprost w łuk, może mieć okulary o niższym '
                  'stopniu, np. 1–4 (DGUV 209-010). Stanowisko odgrodź '
                  'zasłonami spawalniczymi EN ISO 25980 — im ciemniejsze, tym '
                  'lepiej pochłaniają UV; ekrany z gołej blachy odbijają UV.',
              en: 'Anyone who watches the arc — helper, fire watch — needs the '
                  'same shade as the welder (OSHA FS-3499). A helper who does '
                  'not look straight into the arc may wear glasses with a '
                  'lower shade, e.g. 1–4 (DGUV 209-010). Screen the work area '
                  'with EN ISO 25980 welding curtains — the darker, the more '
                  'UV they absorb; bare sheet-metal screens reflect UV.'),
        ),
        _note(
          'shade-note-adf',
          context.tr(
              pl: 'Przyłbica samościemniająca (EN 379)',
              en: 'Auto-darkening helmet (EN 379)'),
          context.tr(
              pl: 'Oznaczenie np. „3/9–13 … 1/1/1/2 EN 379”: 3 — stopień '
                  'w stanie jasnym, 9–13 — zakres w stanie ciemnym. Cztery '
                  'cyfry to klasy: optyczna, rozproszenia światła, '
                  'jednorodności i zależności od kąta patrzenia — 1 najlepsza, '
                  '3 najsłabsza. Stan jasny (zwykle 3–4) nie służy do '
                  'spawania: jeśli filtr nie ściemni się po zajarzeniu łuku, '
                  'przerwij pracę. Ochrona UV/IR dobrego filtra działa stale, '
                  'także w stanie jasnym (np. 3M Speedglas 9100 — jak 13).',
              en: 'Marking e.g. "3/9–13 … 1/1/1/2 EN 379": 3 — light-state '
                  'shade, 9–13 — dark-state range. The four digits are the '
                  'classes: optical, diffusion of light, homogeneity and '
                  'angle dependence — 1 best, 3 worst. The light state '
                  '(usually 3–4) is not for welding: if the filter does not '
                  'darken when the arc strikes, stop work. A good filter\'s '
                  'UV/IR protection is permanent, in the light state too '
                  '(e.g. 3M Speedglas 9100 — as shade 13).'),
        ),
        _note(
          'shade-note-conditions',
          context.tr(
              pl: 'Tabela = przeciętne warunki',
              en: 'The table assumes average conditions'),
          context.tr(
              pl: 'EN 169: zależnie od warunków o 1 stopień ciemniej albo '
                  'jaśniej — położenie względem łuku, oświetlenie stanowiska, '
                  'indywidualna wrażliwość wzroku. Długi łuk — o 1 ciemniej '
                  '(DGUV 209-010). OSHA/ANSI: zacznij od filtra za ciemnego, '
                  'by widzieć spoinę, i rozjaśniaj do dobrej widoczności — '
                  'nie poniżej minimum.',
              en: 'EN 169: one shade darker or lighter depending on '
                  'conditions — position relative to the arc, local lighting, '
                  'the welder\'s own eyes. Long arc — one shade darker (DGUV '
                  '209-010). OSHA/ANSI: start with a shade too dark to see '
                  'the weld zone, then go lighter until you see it well — '
                  'never below the minimum.'),
        ),
        _note(
          'shade-note-skin',
          context.tr(pl: 'Skóra i UV', en: 'Skin and UV'),
          context.tr(
              pl: 'UV z łuku parzy skórę jak słońce — także szyję między '
                  'kołnierzem a przyłbicą. Zakryj całe ciało: zapięty '
                  'kołnierz, osłona szyi, rękawice; odsłonięte miejsca — krem '
                  'z filtrem UV do spawania (DGUV 209-010). Przyłbica nagłowna '
                  'osłania też skronie — lepsza niż tarcza ręczna.',
              en: 'Arc UV burns skin like the sun — including the neck between '
                  'the collar and the helmet. Cover the whole body: buttoned '
                  'collar, neck cover, gloves; exposed skin — a welding UV '
                  'cream (DGUV 209-010). A head-mounted helmet also covers '
                  'the temples — better than a hand shield.'),
        ),
      ],
    );
  }

  Widget _kv(String k, String v, {String? valueKey}) => CopyOnLongPress(
        value: v,
        label: k,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: Text(k,
                      style: const TextStyle(fontSize: 13.5, color: kTextSec))),
              const SizedBox(width: 8),
              Flexible(
                child: Text(v,
                    key: valueKey == null ? null : ValueKey(valueKey),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kText,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ),
            ],
          ),
        ),
      );
}
