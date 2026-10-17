// Wady spoin: przyczyny i naprawa.
//
// Spawacz: „wyszła mi wada — co robię źle i jak to naprawić”. Wybiera wadę
// (szukanie po nazwie PL / EN lub numerze ISO 6520-1), proces (ISO 4063),
// opcjonalnie materiał i pozycję, a ekran pokazuje:
//  • przyczyny w kolejności sprawdzania — każda z konkretnym sprawdzeniem
//    i środkiem zaradczym dla procesu, ze źródłem,
//  • naprawę, kiedy spoina idzie do wycięcia i BHP,
//  • przejście do limitów EN ISO 5817 (gdy wada jest w tablicy 1),
//  • listę „przed następnym ściegiem” (tylko w pamięci ekranu) i
//    udostępnianie tekstem.
//
// Dane ze źródłami: lib/data/weld_defects.dart. Logika:
// lib/domain/defects/defect_advice.dart.

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/weld_defects.dart';
import '../../domain/defects/defect_advice.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic.dart';
import '../iso5817/iso5817_page.dart';

/// Udostępnienie tekstu (podmieniane w testach).
typedef WeldDefectsShareFn = Future<void> Function(String text, String subject);

class WeldDefectsPage extends StatefulWidget {
  /// Domyślnie arkusz udostępniania systemu ([Share.share]).
  final WeldDefectsShareFn? onShare;

  const WeldDefectsPage({super.key, this.onShare});

  @override
  State<WeldDefectsPage> createState() => _WeldDefectsPageState();
}

class _WeldDefectsPageState extends State<WeldDefectsPage> {
  final _search = TextEditingController();
  final _processKey = GlobalKey();
  final _resultKey = GlobalKey();

  String? _defectId;
  DefectProcess? _process;
  DefectMaterial? _material;
  DefectPosition? _position;

  /// Odhaczone punkty „przed następnym ściegiem” — tylko w pamięci ekranu.
  final Set<String> _checked = {};

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearch);
  }

  void _onSearch() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  WeldDefect? get _defect =>
      _defectId == null ? null : weldDefectById(_defectId!);

  void _pickDefect(WeldDefect d) {
    Haptic.tap();
    FocusScope.of(context).unfocus();
    setState(() {
      _defectId = d.id;
      _checked.clear();
      // Proces zostaje, jeśli wada go dotyczy; jedyny proces wybieramy sami.
      if (_process != null && !d.processes.contains(_process)) {
        _process = null;
      }
      if (_process == null && d.processes.length == 1) {
        _process = d.processes.first;
      }
      _fixMaterial();
    });
    _search.clear();
    _scrollTo(_processKey);
  }

  void _changeDefect() {
    Haptic.tap();
    setState(() {
      _defectId = null;
      _checked.clear();
    });
  }

  void _pickProcess(DefectProcess p) {
    Haptic.tap();
    setState(() {
      _process = p;
      _checked.clear();
      _fixMaterial();
    });
    _scrollTo(_resultKey);
  }

  /// Materiał spoza wady / procesu znika; jedyny możliwy jest narzucany.
  void _fixMaterial() {
    final p = _process;
    final d = _defect;
    if (p == null || d == null) return;
    final allowed = d.materialsFor(p);
    if (allowed.length == 1) {
      _material = allowed.first;
    } else if (_material != null && !allowed.contains(_material)) {
      _material = null;
    }
  }

  void _scrollTo(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 250));
      }
    });
  }

  Future<void> _share(DefectAdvice a) async {
    final en = context.language == AppLanguage.en;
    final text = buildDefectShareText(a, en: en, checked: _checked);
    final subject = context.tr(
      pl: 'Wada spoiny — ${a.defect.title.pl}',
      en: 'Weld defect — ${a.defect.title.en}',
    );
    try {
      final fn = widget.onShare;
      if (fn != null) {
        await fn(text, subject);
      } else {
        await Share.share(text, subject: subject);
      }
    } catch (e) {
      debugPrint('weld defects share failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(context.tr(
            pl: 'Nie udało się udostępnić — spróbuj ponownie',
            en: 'Share failed — try again',
          )),
        ));
    }
  }

  void _openIso5817() {
    Haptic.tap();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const Iso5817Page()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final defect = _defect;
    final process = _process;
    final advice = defect == null || process == null
        ? null
        : defectAdvice(defect, process,
            material: _material, position: _position);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
          pl: 'Wady spoin: przyczyny i naprawa',
          en: 'Weld defects: causes and repair',
        )),
      ),
      body: ListView(
        key: const ValueKey('defects-list'),
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          Text(
            context.tr(
              pl: 'Wybierz wadę, proces i — jeśli chcesz — materiał oraz '
                  'pozycję. Dostaniesz przyczyny w kolejności sprawdzania, '
                  'sposób naprawy i listę do odhaczenia przed następnym '
                  'ściegiem.',
              en: 'Pick the defect, the process and — if you want — the '
                  'material and position. You get the causes in the order to '
                  'check them, how to repair and a list to tick before the '
                  'next run.',
            ),
            style: const TextStyle(color: kTextSec, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 12),
          _Notice(
            key: const ValueKey('defects-disclaimer'),
            color: kWarn,
            icon: Icons.gavel_outlined,
            text: defectDisclaimer(en: en),
          ),
          const SizedBox(height: 18),
          _SectionTitle(context.tr(pl: '1. Wada', en: '1. Defect')),
          const SizedBox(height: 8),
          if (defect == null)
            ..._defectPicker(context, en)
          else
            _SelectedDefect(
              defect: defect,
              en: en,
              onChange: _changeDefect,
            ),
          if (defect != null) ...[
            const SizedBox(height: 18),
            KeyedSubtree(
              key: _processKey,
              child: _SectionTitle(
                  context.tr(pl: '2. Proces', en: '2. Process')),
            ),
            const SizedBox(height: 8),
            _processChips(context, defect, en),
            if (process == null)
              Padding(
                key: const ValueKey('defects-pick-process'),
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.tr(
                    pl: 'Wybierz proces — przyczyny i sprawdzenia zależą od '
                        'metody spawania.',
                    en: 'Pick the process — the causes and checks depend on '
                        'the welding method.',
                  ),
                  style: const TextStyle(color: kTextSec, fontSize: 13),
                ),
              ),
          ],
          if (defect != null && process != null && advice != null) ...[
            const SizedBox(height: 18),
            _SectionTitle(context.tr(
                pl: '3. Materiał i pozycja (opcjonalnie)',
                en: '3. Material and position (optional)')),
            const SizedBox(height: 8),
            _materialChips(context, defect, process, en),
            const SizedBox(height: 10),
            _positionDropdown(context, en),
            const SizedBox(height: 22),
            KeyedSubtree(
              key: _resultKey,
              child: _SectionTitle(context.tr(
                pl: 'Przyczyny — sprawdzaj po kolei',
                en: 'Causes — check in this order',
              )),
            ),
            const SizedBox(height: 8),
            for (final (i, c) in advice.causes.indexed)
              _CauseCard(
                key: ValueKey('defects-cause-${c.id}'),
                index: i + 1,
                cause: c,
                advice: advice,
                en: en,
              ),
            const SizedBox(height: 18),
            _SectionTitle(context.tr(pl: 'Naprawa', en: 'Repair')),
            const SizedBox(height: 8),
            _RepairCard(advice: advice, en: en),
            const SizedBox(height: 18),
            _SectionTitle(context.tr(
                pl: 'Przed następnym ściegiem',
                en: 'Before the next run')),
            const SizedBox(height: 8),
            _checklist(context, advice, en),
            const SizedBox(height: 18),
            _SectionTitle(context.tr(pl: 'Powiązania', en: 'Related')),
            const SizedBox(height: 8),
            if (advice.iso5817.isNotEmpty) ...[
              OutlinedButton.icon(
                key: const ValueKey('defects-iso5817'),
                onPressed: _openIso5817,
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(context.tr(
                  pl: 'Zobacz limit wg ISO 5817',
                  en: 'See the ISO 5817 limit',
                )),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr(
                  pl: 'EN ISO 5817, tablica 1 — poz. '
                      '${advice.iso5817.map((i) => i.no).join(', ')}',
                  en: 'EN ISO 5817, Table 1 — item '
                      '${advice.iso5817.map((i) => i.no).join(', ')}',
                ),
                key: const ValueKey('defects-iso5817-items'),
                style: const TextStyle(color: kTextMut, fontSize: 12),
              ),
              const SizedBox(height: 10),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  context.tr(
                    pl: 'Tej wady nie ocenia się wizualnie wg EN ISO 5817 '
                        '(tablica 1 obejmuje niezgodności zewnętrzne) — '
                        'kryterium podaje specyfikacja badań RT / UT.',
                    en: 'This defect is not assessed visually per EN ISO 5817 '
                        '(Table 1 covers surface imperfections) — the '
                        'criterion comes from the RT / UT specification.',
                  ),
                  key: const ValueKey('defects-iso5817-none'),
                  style: const TextStyle(color: kTextMut, fontSize: 12),
                ),
              ),
            Text(
              context.tr(
                pl: 'Naprawę zapisz w Dzienniku spoin przy konkretnej spoinie '
                    '(R1, R2…) — dziennik pilnuje ponownego badania.',
                en: 'Record the repair in the Weld journal on the specific '
                    'weld (R1, R2…) — the journal tracks re-examination.',
              ),
              style: const TextStyle(color: kTextMut, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('defects-share'),
              style: FilledButton.styleFrom(
                backgroundColor: kArc,
                foregroundColor: kOnArc,
                minimumSize: const Size(0, kMinTapTarget),
              ),
              onPressed: () => _share(advice),
              icon: const Icon(Icons.share_outlined),
              label: Text(context.tr(
                  pl: 'Udostępnij tekstem', en: 'Share as text')),
            ),
            const SizedBox(height: 16),
            _SourcesFootnote(advice: advice, en: en),
          ],
        ],
      ),
    );
  }

  List<Widget> _defectPicker(BuildContext context, bool en) {
    final query = _search.text;
    final results = searchDefects(query);
    return [
      TextField(
        key: const ValueKey('defects-search'),
        controller: _search,
        textInputAction: TextInputAction.search,
        autocorrect: false,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, color: kTextSec),
          hintText: context.tr(
              pl: 'Szukaj: nazwa lub nr ISO 6520-1',
              en: 'Search: name or ISO 6520-1 no.'),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  key: const ValueKey('defects-search-clear'),
                  tooltip: context.tr(pl: 'Wyczyść', en: 'Clear'),
                  icon: const Icon(Icons.close),
                  onPressed: _search.clear,
                ),
        ),
      ),
      const SizedBox(height: 10),
      if (query.trim().isNotEmpty) ...[
        if (results.isEmpty)
          Padding(
            key: const ValueKey('defects-search-empty'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              context.tr(
                pl: 'Brak wady dla „${query.trim()}”. Spróbuj numeru ISO '
                    '(np. 2011) albo innego słowa.',
                en: 'No defect for “${query.trim()}”. Try an ISO number '
                    '(e.g. 2011) or another word.',
              ),
              style: const TextStyle(color: kTextSec, fontSize: 13),
            ),
          )
        else
          for (final d in results)
            _DefectTile(defect: d, en: en, onTap: () => _pickDefect(d)),
      ] else
        for (final g in DefectGroup.values) ...[
          if (kWeldDefects.any((d) => d.group == g)) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                '${g.digit}xx · ${en ? g.en : g.pl}',
                style: const TextStyle(
                    color: kTextMut,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ),
            for (final d in kWeldDefects.where((d) => d.group == g))
              _DefectTile(defect: d, en: en, onTap: () => _pickDefect(d)),
          ],
        ],
    ];
  }

  Widget _processChips(BuildContext context, WeldDefect defect, bool en) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final p in DefectProcess.values)
          if (defect.processes.contains(p))
            ChoiceChip(
              key: ValueKey('defects-process-${p.name}'),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              showCheckmark: false,
              selected: _process == p,
              selectedColor: kArc,
              labelStyle: TextStyle(
                color: _process == p ? kOnArc : kText,
                fontWeight: FontWeight.w700,
              ),
              label: Text(p.label),
              tooltip: en ? p.en : p.pl,
              onSelected: (_) => _pickProcess(p),
            ),
      ],
    );
  }

  Widget _materialChips(
      BuildContext context, WeldDefect d, DefectProcess p, bool en) {
    final allowed = d.materialsFor(p);
    if (allowed.length == 1) {
      return Text(
        context.tr(
          pl: 'Materiał: ${allowed.first.pl}',
          en: 'Material: ${allowed.first.en}',
        ),
        key: const ValueKey('defects-material-fixed'),
        style: const TextStyle(color: kTextSec, fontSize: 13),
      );
    }
    Widget chip(String key, String label, DefectMaterial? m) => ChoiceChip(
          key: ValueKey(key),
          materialTapTargetSize: MaterialTapTargetSize.padded,
          showCheckmark: false,
          selected: _material == m,
          selectedColor: kArc,
          labelStyle: TextStyle(
            color: _material == m ? kOnArc : kText,
            fontWeight: FontWeight.w600,
          ),
          label: Text(label),
          onSelected: (_) {
            Haptic.tap();
            setState(() {
              _material = m;
              _checked.clear();
            });
          },
        );
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        chip('defects-material-any', context.tr(pl: 'Każdy', en: 'Any'),
            null),
        for (final m in allowed)
          chip('defects-material-${m.name}', en ? m.en : m.pl, m),
      ],
    );
  }

  Widget _positionDropdown(BuildContext context, bool en) {
    return DropdownButtonFormField<DefectPosition?>(
      key: const ValueKey('defects-position'),
      initialValue: _position,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: context.tr(pl: 'Pozycja (ISO 6947)', en: 'Position (ISO 6947)'),
      ),
      items: [
        DropdownMenuItem<DefectPosition?>(
          value: null,
          child: Text(context.tr(pl: 'Dowolna', en: 'Any')),
        ),
        for (final p in DefectPosition.values)
          DropdownMenuItem<DefectPosition?>(
            value: p,
            child: Text(
              '${p.code} · ${en ? p.en : p.pl}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (p) {
        Haptic.tap();
        setState(() => _position = p);
      },
    );
  }

  Widget _checklist(BuildContext context, DefectAdvice a, bool en) {
    return Card(
      key: const ValueKey('defects-checklist'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final s in a.checklist)
            CheckboxListTile(
              key: ValueKey('defects-check-${s.id}'),
              value: _checked.contains(s.id),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: kArc,
              checkColor: kOnArc,
              title: Text(
                s.text.of(en: en),
                style: const TextStyle(color: kText, fontSize: 14),
              ),
              onChanged: (v) {
                Haptic.tap();
                setState(() {
                  if (v ?? false) {
                    _checked.add(s.id);
                  } else {
                    _checked.remove(s.id);
                  }
                });
              },
            ),
        ],
      ),
    );
  }
}

// ── Elementy ekranu ─────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          color: kTextSec, fontSize: 13, fontWeight: FontWeight.w700),
    );
  }
}

/// Ramka informacyjna (bez elementów dotykowych w środku).
class _Notice extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _Notice(
      {super.key, required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style:
                    const TextStyle(color: kText, fontSize: 12, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

class _DefectTile extends StatelessWidget {
  final WeldDefect defect;
  final bool en;
  final VoidCallback onTap;
  const _DefectTile(
      {required this.defect, required this.en, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey('defects-pick-${defect.id}'),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minTileHeight: kMinTapTarget + 8,
        onTap: onTap,
        title: Text(
          defect.title.of(en: en),
          style: const TextStyle(
              color: kText, fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'ISO 6520-1: ${defect.codesLabel}',
          style: const TextStyle(color: kTextMut, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: kTextSec),
      ),
    );
  }
}

class _SelectedDefect extends StatelessWidget {
  final WeldDefect defect;
  final bool en;
  final VoidCallback onChange;
  const _SelectedDefect(
      {required this.defect, required this.en, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('defects-selected'),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: kArc, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              defect.title.of(en: en),
              key: const ValueKey('defects-selected-title'),
              style: const TextStyle(
                  color: kText, fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            for (final r in defect.refs)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '${r.code} · ${en ? r.en : r.pl}',
                  style: const TextStyle(color: kTextSec, fontSize: 12),
                ),
              ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                defect.looks.of(en: en),
                style: const TextStyle(
                    color: kTextSec, fontSize: 13, height: 1.4),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('defects-change'),
                style: TextButton.styleFrom(
                  foregroundColor: kArc,
                  minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                ),
                onPressed: onChange,
                icon: const Icon(Icons.swap_horiz),
                label: Text(context.tr(pl: 'Zmień wadę', en: 'Change defect')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CauseCard extends StatelessWidget {
  final int index;
  final DefectCause cause;
  final DefectAdvice advice;
  final bool en;
  const _CauseCard({
    super.key,
    required this.index,
    required this.cause,
    required this.advice,
    required this.en,
  });

  @override
  Widget build(BuildContext context) {
    final tags = <String>[
      if (advice.material == null && cause.materials.isNotEmpty)
        cause.materials.map((m) => en ? m.en : m.pl).join(', '),
      if (cause.positions.isNotEmpty)
        cause.positions.map((p) => p.code).join(', '),
    ];
    final sources = defectSourceLabel(cause.sources);
    final positionHit =
        advice.position != null && cause.positions.contains(advice.position);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: positionHit ? kArc : kBorder, width: positionHit ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: index == 1 ? kArc : kBorder,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '$index',
                    style: TextStyle(
                      color: index == 1 ? kOnArc : kText,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    cause.cause.of(en: en),
                    style: const TextStyle(
                        color: kText,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.3),
                  ),
                ),
              ],
            ),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 38),
                child: Text(
                  tags.join(' · '),
                  style: const TextStyle(
                      color: kGold, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
            const SizedBox(height: 8),
            _Labeled(
              label: context.tr(pl: 'Sprawdź', en: 'Check'),
              text: cause.check.of(en: en),
              icon: Icons.search,
            ),
            const SizedBox(height: 6),
            _Labeled(
              label: context.tr(pl: 'Zaradczo', en: 'Fix'),
              text: cause.fix.of(en: en),
              icon: Icons.build_outlined,
            ),
            if (sources.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                context.tr(pl: 'Źródło: $sources', en: 'Source: $sources'),
                style: const TextStyle(
                    color: kTextMut, fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  final String label;
  final String text;
  final IconData icon;
  const _Labeled({required this.label, required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: kTextSec),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '$label: ',
                style: const TextStyle(
                    color: kText, fontWeight: FontWeight.w700),
              ),
              TextSpan(text: text),
            ]),
            style: const TextStyle(color: kTextSec, fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _RepairCard extends StatelessWidget {
  final DefectAdvice advice;
  final bool en;
  const _RepairCard({required this.advice, required this.en});

  @override
  Widget build(BuildContext context) {
    final d = advice.defect;
    final sources = defectSourceLabel(d.repairSources);
    return Card(
      key: const ValueKey('defects-repair'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, s) in advice.repair.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text('${i + 1}.',
                          style: const TextStyle(
                              color: kArc,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                    ),
                    Expanded(
                      child: Text(s.text.of(en: en),
                          style: const TextStyle(
                              color: kText, fontSize: 13, height: 1.4)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            _Notice(
              key: const ValueKey('defects-cutout'),
              color: kFail,
              icon: Icons.content_cut,
              text: '${context.tr(pl: 'Do wycięcia', en: 'Cut out')}: '
                  '${d.cutOut.of(en: en)}',
            ),
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('defects-safety'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kWarn.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kWarn.withValues(alpha: 0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.health_and_safety_outlined,
                          color: kWarn, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(context.tr(pl: 'BHP', en: 'Safety'),
                            style: const TextStyle(
                                color: kText,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final s in d.safety)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• ${s.of(en: en)}',
                          style: const TextStyle(
                              color: kText, fontSize: 12, height: 1.4)),
                    ),
                ],
              ),
            ),
            if (sources.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                context.tr(pl: 'Źródło: $sources', en: 'Source: $sources'),
                style: const TextStyle(
                    color: kTextMut, fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourcesFootnote extends StatelessWidget {
  final DefectAdvice advice;
  final bool en;
  const _SourcesFootnote({required this.advice, required this.en});

  @override
  Widget build(BuildContext context) {
    final keys = <String>{
      for (final c in advice.causes) ...c.sources,
      ...advice.defect.repairSources,
    };
    final list = [
      for (final k in keys)
        if (kDefectSources[k] != null) kDefectSources[k]!
    ];
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('defects-sources'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr(pl: 'Źródła', en: 'Sources'),
            style: const TextStyle(
                color: kTextMut, fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        for (final s in list)
          Text(
            '${s.short}: ${s.title}',
            style: const TextStyle(
                color: kTextMut, fontSize: 11, fontStyle: FontStyle.italic),
          ),
      ],
    );
  }
}
