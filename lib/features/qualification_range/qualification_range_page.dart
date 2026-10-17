// „Zakres uprawnień z próbki” — EN ISO 9606-1:2017. Spawacz wpisuje
// parametry złącza próbnego (proces, spoiwo, wyrób, BW/FW, grubość,
// średnica, pozycja, prowadzenie grani…) i widzi zakres kwalifikacji wg
// tabel normy, każdą pozycję z punktem / tabelą. Logika i źródła:
// lib/domain/qualification/iso9606_range.dart.
//
// Puste albo nieczytelne pole to komunikat „czego brakuje”, nie wynik.
// „Zapisz jako uprawnienie” najpierw pokazuje OBOWIĄZKOWY dialog z tym, czego
// kontrola spoiny z rejestru nie sprawdzi (grań, przenoszenie metalu, blacha
// / rura, FM, otulina, proces 2…), dopiero po „Rozumiem — zapisz” otwiera
// formularz rejestru (CertificateEditPage) ze szkicem — w polach tylko to,
// czego kontrola nie poszerzy, ograniczenia na początku notatki.
// Udostępnianie (tekst, PDF) wstrzykiwane w testach.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/qualification/iso9606_range.dart';
import '../../i18n/app_language.dart';
import '../../services/qualification_range_export.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import '../qualification/certificate_edit_page.dart';
import '../quotes/quote_widgets.dart';

/// Udostępnienie tekstu — wstrzykiwane w testach.
typedef QualificationRangeShareText = Future<void> Function(
    String text, String subject);

/// Udostępnienie PDF — wstrzykiwane w testach.
typedef QualificationRangeSharePdf = Future<void> Function(
    Iso9606Range range, bool english);

Future<void> _defaultShareText(String text, String subject) async {
  await Share.share(text, subject: subject);
}

Future<void> _defaultSharePdf(Iso9606Range range, bool english) =>
    QualificationRangeExport.sharePdf(range, en: english);

class QualificationRangePage extends StatefulWidget {
  const QualificationRangePage({super.key, this.shareText, this.sharePdf});

  final QualificationRangeShareText? shareText;
  final QualificationRangeSharePdf? sharePdf;

  @override
  State<QualificationRangePage> createState() => _QualificationRangePageState();
}

/// Stan jednego procesu na ekranie.
class _ProcessState {
  Iso9606Process? process;
  Iso9606Filler? filler;
  Iso9606Transfer? transfer;
  final TextEditingController thickness = TextEditingController();

  /// Wybór procesu: jedyny typ spoiwa wybiera się sam, niepasujący — znika.
  void select(Iso9606Process p) {
    process = p;
    if (p.fillers.length == 1) {
      filler = p.fillers.single;
    } else if (filler != null && !p.fillers.contains(filler)) {
      filler = null;
    }
    if (!p.hasTransferMode) transfer = null;
  }
}

class _QualificationRangePageState extends State<QualificationRangePage> {
  Iso9606Product _product = Iso9606Product.plate;
  Iso9606WeldType _type = Iso9606WeldType.bw;
  Iso6947Position? _position;
  bool _companion = false;
  final _first = _ProcessState();
  final _second = _ProcessState();
  bool _two = false;
  Iso9606FmGroup? _fm;
  final _parent = TextEditingController();
  final _diameter = TextEditingController();
  Iso9606Backing? _backing;
  Iso9606Layers? _layers;
  bool _supplementary = false;
  Iso9606FilletLayers? _filletLayers;
  Iso9606GasDirection? _gas;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [
      _first.thickness,
      _second.thickness,
      _parent,
      _diameter,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _en => context.language == AppLanguage.en;
  bool get _butt => _type == Iso9606WeldType.bw;
  bool get _pipe => _product == Iso9606Product.pipe;

  /// Liczba z pola: puste → `null` (brak), nieczytelne → NaN (komunikat).
  double? _num(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return parseDecimal(t) ?? double.nan;
  }

  Iso9606ProcessInput _input(_ProcessState p) => Iso9606ProcessInput(
        process: p.process,
        filler: p.filler,
        transfer: p.transfer,
        thicknessMm: _num(p.thickness),
      );

  Iso9606Sample get _sample => Iso9606Sample(
        product: _product,
        weldType: _type,
        first: _input(_first),
        second: _butt && _two ? _input(_second) : null,
        fm: _fm,
        parentGroup: _parent.text,
        diameterMm: _pipe ? _num(_diameter) : null,
        position: _position,
        pcCompanion: _companion,
        backing: _butt ? _backing : null,
        layers: _butt ? _layers : null,
        supplementaryFillet: _butt && _supplementary,
        filletLayers: _butt ? null : _filletLayers,
        gasDirection: _gas,
      );

  /// Pozycja / prowadzenie grani, których nie ma dla nowej próbki — znikają
  /// (wynik nigdy nie liczy się z ukrytego wyboru).
  void _dropInvalid() {
    if (_position != null &&
        !iso9606TestPositions(_type, _product).contains(_position)) {
      _position = null;
    }
    final p1 = _first.process;
    if (_backing != null && p1 != null && !_backing!.appliesTo(p1)) {
      _backing = null;
    }
  }

  // ── Akcje ──────────────────────────────────────────────────────────────

  Future<void> _shareText(Iso9606Range r) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      unawaited(Haptic.tap());
      await (widget.shareText ?? _defaultShareText)(
          iso9606ShareText(r, en: _en), iso9606Title(en: _en));
    } catch (_) {
      if (!mounted) return;
      _snack(context.tr(
          pl: 'Nie udało się udostępnić wyniku.',
          en: 'Could not share the result.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sharePdf(Iso9606Range r) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await (widget.sharePdf ?? _defaultSharePdf)(r, _en);
    } catch (_) {
      if (!mounted) return;
      _snack(context.tr(
          pl: 'Nie udało się przygotować PDF.',
          en: 'Could not prepare the PDF.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveToRegister(Iso9606Range r) async {
    final draft = iso9606CertificateDraft(r, en: _en);
    final problem = draft.problem;
    if (problem != null) {
      _snack(iso9606DraftProblemText(problem, en: _en));
      return;
    }
    // Obowiązkowo: czego rejestr nie sprawdza. Bez „Rozumiem” — bez zapisu.
    final understood = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('qr-limits-dialog'),
        title: Text(ctx.tr(
            pl: 'Czego rejestr nie sprawdzi',
            en: 'What the register will not check')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ctx.tr(
                    pl: 'Kontrola spoiny z rejestru porówna proces, grubość, '
                        'średnicę, pozycje i BW/FW. Poniższe ograniczenia '
                        'trafią na początek notatki certyfikatu; kontrola '
                        'sprawdzi je tylko, gdy spoina ma te dane (dziennik '
                        'zna dziś grupę spoiwa z oznaczenia, rurę z OD '
                        'i odgałęzienie — prowadzenia grani i przenoszenia '
                        'metalu nie zapisuje):',
                    en: 'The weld check against the register compares '
                        'process, thickness, diameter, positions and BW/FW. '
                        'The limitations below go to the top of the '
                        'certificate notes; the check enforces them only when '
                        'the weld has the data (the journal knows the filler '
                        'group from its designation, pipe from the OD and '
                        'branch joints — it does not record the root '
                        'condition or metal transfer):'),
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 10),
              for (final (i, l) in draft.limits.indexed)
                Padding(
                  key: ValueKey('qr-limit-$i'),
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• ${l.text(en: _en)}',
                      style: const TextStyle(fontSize: 13, height: 1.35)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('qr-limits-cancel'),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          FilledButton(
            key: const ValueKey('qr-limits-ok'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr(
                pl: 'Rozumiem — zapisz', en: 'Understood — save')),
          ),
        ],
      ),
    );
    if (understood != true || !mounted) return;
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CertificateEditPage(initial: draft.certificate),
    ));
    if (saved == true && mounted) {
      _snack(context.tr(
          pl: 'Zapisano w rejestrze uprawnień.',
          en: 'Saved to the qualification register.'));
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  // ── Budowa ekranu ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sample = _sample;
    final evaluation = evaluateIso9606(sample);
    final range = evaluation.range;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Zakres uprawnień z próbki',
            en: 'Range of qualification from a test piece')),
      ),
      body: ListView(
        key: const ValueKey('qr-list'),
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _sampleSection(),
          _processSection(_first, 1),
          if (_butt && _two) _processSection(_second, 2),
          _fillerSection(sample),
          _detailsSection(),
          if (evaluation.problems.isNotEmpty)
            KeyedSubtree(
              key: const ValueKey('qr-problems'),
              child: QuoteNotice(
                color: kWarn,
                icon: Icons.playlist_add_check,
                text: [
                  context.tr(pl: 'Brakuje danych:', en: 'Missing data:'),
                  for (final p in evaluation.problems)
                    '• ${iso9606ProblemText(p, en: _en)}',
                ].join('\n'),
              ),
            ),
          if (range != null) ..._result(range),
          KeyedSubtree(
            key: const ValueKey('qr-disclaimer'),
            child: QuoteNotice(
              color: kWarn,
              icon: Icons.gavel_outlined,
              text: iso9606Disclaimer(en: _en),
            ),
          ),
        ],
      ),
    );
  }

  Widget _caption(String text, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.only(top: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 12, color: kTextMut, height: 1.35)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(text, style: const TextStyle(color: kTextSec, fontSize: 13)),
      );

  Widget _chips(List<Widget> chips) =>
      Wrap(spacing: 6, runSpacing: 6, children: chips);

  /// Chip wyboru z celem dotyku ≥ 48 × 48 dp także dla krótkich etykiet.
  Widget _choice(String key, String label, bool selected, VoidCallback onTap,
          {String? tooltip}) {
    Widget chip = ChoiceChip(
      key: ValueKey(key),
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() {
        onTap();
        _dropInvalid();
      }),
    );
    if (tooltip != null) chip = Tooltip(message: tooltip, child: chip);
    return ConstrainedBox(
      constraints:
          const BoxConstraints(minWidth: kMinTapTarget, minHeight: kMinTapTarget),
      child: chip,
    );
  }

  Widget _numberField(TextEditingController c, String label,
          {required Key key, String? helper}) =>
      TextField(
        key: key,
        controller: c,
        keyboardType: numberKeyboard(),
        inputFormatters: numberInputFormatters(),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'mm',
          helperText: helper,
          helperMaxLines: 4,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _switch(String key, String title, String? subtitle, bool value,
          ValueChanged<bool> onChanged) =>
      SwitchListTile(
        key: ValueKey(key),
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle,
                style: const TextStyle(fontSize: 12, color: kTextMut)),
        value: value,
        onChanged: (v) => setState(() {
          onChanged(v);
          _dropInvalid();
        }),
      );

  // ── Próbka ─────────────────────────────────────────────────────────────

  Widget _sampleSection() {
    final positions = iso9606TestPositions(_type, _product);
    final canCompanion = _butt &&
        _pipe &&
        (_position == Iso6947Position.ph || _position == Iso6947Position.pj);
    return QuoteSection(
      title: context.tr(pl: 'Próbka', en: 'Test piece'),
      subtitle: context.tr(
          pl: 'Norma: EN ISO 9606-1:2017 (= ISO 9606-1:2012 + Cor 1, Cor 2). '
              'ASME IX nie jest liczona — zakres WPQ wg QW-451 / QW-452 '
              'i QW-461.9 sprawdź w normie.',
          en: 'Standard: EN ISO 9606-1:2017 (= ISO 9606-1:2012 + Cor 1, '
              'Cor 2). ASME IX is not calculated — check the WPQ range per '
              'QW-451 / QW-452 and QW-461.9.'),
      children: [
        _chips([
          _choice('qr-product-plate',
              context.tr(pl: 'Blacha (P)', en: 'Plate (P)'),
              _product == Iso9606Product.plate,
              () => _product = Iso9606Product.plate),
          _choice('qr-product-pipe',
              context.tr(pl: 'Rura (T)', en: 'Pipe (T)'),
              _product == Iso9606Product.pipe,
              () => _product = Iso9606Product.pipe),
        ]),
        const SizedBox(height: 6),
        _chips([
          _choice('qr-type-bw', context.tr(pl: 'BW — czołowa', en: 'BW — butt'),
              _butt, () => _type = Iso9606WeldType.bw),
          _choice('qr-type-fw',
              context.tr(pl: 'FW — pachwinowa', en: 'FW — fillet'), !_butt,
              () => _type = Iso9606WeldType.fw),
        ]),
        _label(context.tr(
            pl: 'Pozycja spawania próbki (ISO 6947)',
            en: 'Test piece welding position (ISO 6947)')),
        _chips([
          for (final p in positions)
            _choice('qr-pos-${p.code}', p.code, _position == p,
                () => _position = p),
        ]),
        if (canCompanion)
          _switch(
            'qr-companion',
            context.tr(
                pl: '+ druga rura w PC (ta sama D)',
                en: '+ second pipe in PC (same D)'),
            context.tr(
                pl: 'albo jedna rura D ≥ 150 mm: 2/3 obwodu ${_position!.code}, '
                    '1/3 PC — §5.8',
                en: 'or one pipe D ≥ 150 mm: 2/3 of the circumference '
                    '${_position!.code}, 1/3 PC — cl. 5.8'),
            _companion,
            (v) => _companion = v,
          ),
        if (_pipe) ...[
          const SizedBox(height: 12),
          _numberField(
            _diameter,
            context.tr(
                pl: 'Średnica zewnętrzna rury D',
                en: 'Pipe outside diameter D'),
            key: const ValueKey('qr-d'),
            helper: context.tr(
                pl: 'Profil zamknięty: krótszy bok (tab. 7).',
                en: 'Hollow section: the smaller side (Table 7).'),
          ),
        ],
      ],
    );
  }

  // ── Proces ─────────────────────────────────────────────────────────────

  String _fillerLabel(Iso9606Filler f) => switch (f) {
        Iso9606Filler.coveringRutile => 'A–R',
        Iso9606Filler.coveringBasic => 'B',
        Iso9606Filler.coveringCellulosic => 'C',
        Iso9606Filler.solid => 'S',
        Iso9606Filler.metalCored => 'M',
        Iso9606Filler.basicCored => 'B',
        Iso9606Filler.otherCored => 'R/P/V/W/Y/Z',
        Iso9606Filler.none => context.tr(pl: 'bez spoiwa', en: 'no filler'),
      };

  String _fillerDescription(Iso9606Filler f) => switch (f) {
        Iso9606Filler.coveringRutile => context.tr(
            pl: 'Otulina A, RA, RB, RC, RR, R (${f.isoNumbers}).',
            en: 'Covering A, RA, RB, RC, RR, R (${f.isoNumbers}).'),
        Iso9606Filler.coveringBasic => context.tr(
            pl: 'Otulina zasadowa B (${f.isoNumbers}).',
            en: 'Basic covering B (${f.isoNumbers}).'),
        Iso9606Filler.coveringCellulosic => context.tr(
            pl: 'Otulina celulozowa C (${f.isoNumbers}).',
            en: 'Cellulosic covering C (${f.isoNumbers}).'),
        Iso9606Filler.solid => context.tr(
            pl: 'Drut / pręt lity (S).', en: 'Solid wire / rod (S).'),
        Iso9606Filler.metalCored => context.tr(
            pl: 'Drut / pręt z rdzeniem metalicznym (M).',
            en: 'Metal-cored wire / rod (M).'),
        Iso9606Filler.basicCored => context.tr(
            pl: 'Drut / pręt proszkowy zasadowy (B).',
            en: 'Basic flux-cored wire / rod (B).'),
        Iso9606Filler.otherCored => context.tr(
            pl: 'Drut / pręt proszkowy R, P, V, W, Y albo Z.',
            en: 'Flux-cored wire / rod R, P, V, W, Y or Z.'),
        Iso9606Filler.none => context.tr(
            pl: 'Bez spoiwa (nm) — zakres to grupa materiału z próby.',
            en: 'No filler (nm) — the range is the parent material group of '
                'the test.'),
      };

  Widget _processSection(_ProcessState s, int n) {
    final p = s.process;
    final title = !_butt || !_two
        ? context.tr(pl: 'Proces', en: 'Process')
        : (n == 1
            ? context.tr(pl: 'Proces 1 — grań', en: 'Process 1 — root')
            : context.tr(
                pl: 'Proces 2 — wypełnienie i lico',
                en: 'Process 2 — fill and cap'));
    final thicknessLabel = !_butt
        ? context.tr(
            pl: 'Grubość materiału próbki t', en: 'Test piece material thickness t')
        : (!_two
            ? context.tr(
                pl: 'Grubość próbki t (= grubość stopiwa s)',
                en: 'Test piece thickness t (= deposited thickness s)')
            : (n == 1
                ? context.tr(
                    pl: 'Grubość stopiwa grani s₁',
                    en: 'Root deposited thickness s₁')
                : context.tr(
                    pl: 'Grubość stopiwa s₂', en: 'Deposited thickness s₂')));
    return QuoteSection(
      key: ValueKey('qr-process-$n'),
      title: title,
      subtitle: n == 2
          ? context.tr(
              pl: 'Tab. 1: proces 1 spawa grań bez podkładki, proces 2 — na '
                  'niej (jak na podkładce).',
              en: 'Table 1: process 1 welds the root without backing, process '
                  '2 on top of it (as on backing).')
          : null,
      children: [
        _chips([
          for (final proc in Iso9606Process.values)
            _choice('qr-p$n-${proc.code}', proc.code, p == proc,
                () => s.select(proc),
                tooltip: _en ? proc.nameEn : proc.namePl),
        ]),
        if (p != null)
          _caption(_en ? p.nameEn : p.namePl, key: ValueKey('qr-p$n-name')),
        if (p != null && p.fillers.length > 1) ...[
          _label(context.tr(pl: 'Typ spoiwa', en: 'Filler type')),
          _chips([
            for (final f in p.fillers)
              _choice('qr-f$n-${f.name}', _fillerLabel(f), s.filler == f,
                  () => s.filler = f),
          ]),
        ],
        if (s.filler != null) _caption(_fillerDescription(s.filler!)),
        if (p != null && p.hasTransferMode) ...[
          _label(context.tr(
              pl: 'Przenoszenie metalu (§5.2)', en: 'Metal transfer (cl. 5.2)')),
          _chips([
            _choice('qr-tr$n-dip',
                context.tr(pl: 'zwarciowe (dip)', en: 'dip (short-circuit)'),
                s.transfer == Iso9606Transfer.dip,
                () => s.transfer = Iso9606Transfer.dip),
            _choice('qr-tr$n-other',
                context.tr(pl: 'inne (natrysk, puls)', en: 'other (spray, pulse)'),
                s.transfer == Iso9606Transfer.other,
                () => s.transfer = Iso9606Transfer.other),
          ]),
        ],
        const SizedBox(height: 12),
        _numberField(s.thickness, thicknessLabel, key: ValueKey('qr-s$n')),
        if (n == 1 && _butt)
          _switch(
            'qr-second',
            context.tr(
                pl: 'Drugi proces (np. 141 grań + 111)',
                en: 'Second process (e.g. 141 root + 111)'),
            context.tr(
                pl: 'Grubość stopiwa liczy się dla każdego procesu osobno '
                    '(tab. 1 i 6).',
                en: 'Deposited thickness counts for each process separately '
                    '(Tables 1 and 6).'),
            _two,
            (v) => _two = v,
          ),
      ],
    );
  }

  // ── Spoiwo ─────────────────────────────────────────────────────────────

  Widget _fillerSection(Iso9606Sample sample) {
    final fillers = [for (final p in sample.processes) p.filler];
    final allNone = fillers.every((f) => f == Iso9606Filler.none);
    // Pole także przy próbie ze spoiwem, która obejmuje spawanie bez spoiwa
    // (141 → 142, 311, 15) — §5.6 uwaga.
    final needsParent = iso9606NeedsParentGroup(sample);
    return QuoteSection(
      title: context.tr(pl: 'Spoiwo i materiał', en: 'Filler and material'),
      children: [
        if (!allNone) ...[
          Text(context.tr(pl: 'Grupa spoiwa (tab. 2)', en: 'Filler group (Table 2)'),
              style: const TextStyle(color: kTextSec, fontSize: 13)),
          const SizedBox(height: 6),
          _chips([
            for (final g in Iso9606FmGroup.values)
              _choice('qr-fm-${g.code}', g.code, _fm == g, () => _fm = g),
          ]),
          if (_fm != null) _caption(_en ? _fm!.nameEn : _fm!.namePl),
        ],
        if (needsParent) ...[
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('qr-parent'),
            controller: _parent,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: context.tr(
                  pl: 'Grupa materiału rodzimego próby (ISO/TR 15608)',
                  en: 'Test parent material group (ISO/TR 15608)'),
              helperText: allNone
                  ? context.tr(
                      pl: 'np. 1.1, 8.1 — bez spoiwa tylko ta grupa (§5.6).',
                      en: 'e.g. 1.1, 8.1 — without filler only this group '
                          '(cl. 5.6).')
                  : context.tr(
                      pl: 'np. 1.1, 8.1 — jak na certyfikacie (§5.1). '
                          'Spawanie bez spoiwa (142…) tylko na tej grupie '
                          '(§5.6).',
                      en: 'e.g. 1.1, 8.1 — as on the certificate (cl. 5.1). '
                          'Welding without filler (142…) only on this group '
                          '(cl. 5.6).'),
              helperMaxLines: 3,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }

  // ── Szczegóły spoiny ───────────────────────────────────────────────────

  String _backingDescription(Iso9606Backing b) => switch (b) {
        Iso9606Backing.ssNb => context.tr(
            pl: 'jednostronnie, bez podkładki',
            en: 'single side, no backing'),
        Iso9606Backing.ssMb => context.tr(
            pl: 'jednostronnie, na podkładce', en: 'single side, material backing'),
        Iso9606Backing.bs => context.tr(
            pl: 'dwustronnie', en: 'both sides'),
        Iso9606Backing.ssGb => context.tr(
            pl: 'jednostronnie, gaz formujący', en: 'single side, gas backing'),
        Iso9606Backing.ci => context.tr(
            pl: 'wkładka topliwa', en: 'consumable insert'),
        Iso9606Backing.ssFb => context.tr(
            pl: 'jednostronnie, podkładka topnikowa',
            en: 'single side, flux backing'),
      };

  Widget _detailsSection() {
    final p1 = _first.process;
    final uses311 = _first.process == Iso9606Process.p311 ||
        (_butt && _two && _second.process == Iso9606Process.p311);
    return QuoteSection(
      title: context.tr(pl: 'Szczegóły spoiny', en: 'Weld details'),
      children: [
        if (_butt) ...[
          Text(
              context.tr(
                  pl: 'Prowadzenie grani (tab. 11)',
                  en: 'Root / backing (Table 11)'),
              style: const TextStyle(color: kTextSec, fontSize: 13)),
          const SizedBox(height: 6),
          _chips([
            for (final b in Iso9606Backing.values)
              if (p1 == null || b.appliesTo(p1))
                _choice('qr-back-${b.name}', b.code, _backing == b,
                    () => _backing = b),
          ]),
          if (_backing != null) _caption(_backingDescription(_backing!)),
          _label(context.tr(
              pl: 'Liczba warstw próbki', en: 'Number of layers')),
          _chips([
            _choice('qr-layers-one', context.tr(pl: '1 warstwa', en: '1 layer'),
                _layers == Iso9606Layers.one, () => _layers = Iso9606Layers.one),
            _choice('qr-layers-two', context.tr(pl: '2 warstwy', en: '2 layers'),
                _layers == Iso9606Layers.two, () => _layers = Iso9606Layers.two),
            _choice(
                'qr-layers-threeOrMore',
                context.tr(pl: '3 i więcej', en: '3 or more'),
                _layers == Iso9606Layers.threeOrMore,
                () => _layers = Iso9606Layers.threeOrMore),
          ]),
          _caption(context.tr(
              pl: 'Potrzebna przy s ≥ 12 mm (min. 3 warstwy) i przy dodatkowej '
                  'próbce pachwinowej.',
              en: 'Needed for s ≥ 12 mm (at least 3 layers) and for the '
                  'supplementary fillet test.')),
          _switch(
            'qr-supplementary',
            context.tr(
                pl: 'Dodatkowa próbka pachwinowa (§5.4 e)',
                en: 'Supplementary fillet test (cl. 5.4 e)'),
            context.tr(
                pl: 'min. 10 mm, jedna warstwa w PB — daje spoiny pachwinowe',
                en: 'min. 10 mm, single layer in PB — gives fillet welds'),
            _supplementary,
            (v) => _supplementary = v,
          ),
        ] else ...[
          Text(
              context.tr(
                  pl: 'Technika spoiny pachwinowej (tab. 12)',
                  en: 'Fillet weld technique (Table 12)'),
              style: const TextStyle(color: kTextSec, fontSize: 13)),
          const SizedBox(height: 6),
          _chips([
            _choice('qr-fl-sl',
                context.tr(pl: 'sl — jedna warstwa', en: 'sl — single layer'),
                _filletLayers == Iso9606FilletLayers.sl,
                () => _filletLayers = Iso9606FilletLayers.sl),
            _choice('qr-fl-ml',
                context.tr(pl: 'ml — wielowarstwowa', en: 'ml — multi-layer'),
                _filletLayers == Iso9606FilletLayers.ml,
                () => _filletLayers = Iso9606FilletLayers.ml),
          ]),
        ],
        if (uses311) ...[
          _label(context.tr(
              pl: 'Kierunek spawania 311 (§5.9)',
              en: 'Welding direction 311 (cl. 5.9)')),
          _chips([
            _choice('qr-gas-leftward',
                context.tr(pl: 'lw — w lewo', en: 'lw — leftward'),
                _gas == Iso9606GasDirection.leftward,
                () => _gas = Iso9606GasDirection.leftward),
            _choice('qr-gas-rightward',
                context.tr(pl: 'rw — w prawo', en: 'rw — rightward'),
                _gas == Iso9606GasDirection.rightward,
                () => _gas = Iso9606GasDirection.rightward),
          ]),
        ],
      ],
    );
  }

  // ── Wynik ──────────────────────────────────────────────────────────────

  List<Widget> _result(Iso9606Range r) {
    final lines = iso9606Lines(r, en: _en);
    return [
      QuoteSection(
        key: const ValueKey('qr-result'),
        title: context.tr(pl: 'Zakres uprawnienia', en: 'Range of qualification'),
        subtitle: iso9606Designation(r.sample, en: _en),
        children: [
          for (final l in lines)
            Padding(
              key: ValueKey('qr-line-${l.key}'),
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l.label,
                      style: const TextStyle(fontSize: 12, color: kTextSec)),
                  const SizedBox(height: 2),
                  Text(l.value,
                      key: ValueKey('qr-value-${l.key}'),
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: kText)),
                  Text(l.clause,
                      style: const TextStyle(fontSize: 11.5, color: kTextMut)),
                ],
              ),
            ),
        ],
      ),
      for (final (i, n) in r.notes.indexed)
        KeyedSubtree(
          key: ValueKey('qr-note-$i'),
          child: QuoteNotice(
            color: n.check ? kWarn : kTextSec,
            icon: n.check ? Icons.fact_check_outlined : Icons.info_outline,
            text: n.check
                ? '${context.tr(pl: 'Sprawdź: ', en: 'Check: ')}${n.text(en: _en)}'
                : n.text(en: _en),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FilledButton.icon(
          key: const ValueKey('qr-share'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: kArc,
            foregroundColor: kOnArc,
          ),
          onPressed: _busy ? null : () => unawaited(_shareText(r)),
          icon: const Icon(Icons.share_outlined),
          label: Text(context.tr(pl: 'Udostępnij wynik', en: 'Share the result'),
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: OutlinedButton.icon(
          key: const ValueKey('qr-pdf'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52)),
          onPressed: _busy ? null : () => unawaited(_sharePdf(r)),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(context.tr(pl: 'PDF', en: 'PDF')),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton.icon(
          key: const ValueKey('qr-save'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52)),
          onPressed: () => unawaited(_saveToRegister(r)),
          icon: const Icon(Icons.workspace_premium_outlined),
          label: Text(context.tr(
              pl: 'Zapisz jako uprawnienie', en: 'Save as qualification')),
        ),
      ),
    ];
  }
}
