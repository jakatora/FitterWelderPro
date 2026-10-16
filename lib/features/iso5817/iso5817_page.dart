// Odbiór wizualny spoin — EN ISO 5817:2014 (tablica 1).
//
// Spawacz / kontroler VT wpisuje poziom jakości, rodzaj spoiny i wymiary
// złącza (t, b, a), a ekran:
//  • liczy dopuszczalne wymiary najczęstszych niezgodności zewnętrznych dla
//    B / C / D (z rozróżnieniem 0,5–3 mm i > 3 mm),
//  • ocenia wpisany pomiar („mieści się w C”, „przekracza B, mieści się
//    w C”, „niedopuszczalne”),
//  • udostępnia wynik tekstem do protokołu.
//
// Cała logika i dane z komentarzami źródłowymi: lib/domain/iso5817/.

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/iso5817/iso5817_limits.dart';
import '../../domain/iso5817/iso5817_table.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../../utils/clipboard_helper.dart';
import '../../utils/haptic.dart';
import '../../widgets/number_field.dart';
import '../../widgets/readout.dart';

/// Udostępnienie tekstu wyniku (podmieniane w testach).
typedef Iso5817ShareFn = Future<void> Function(String text, String subject);

class Iso5817Page extends StatefulWidget {
  /// Domyślnie arkusz udostępniania systemu ([Share.share]).
  final Iso5817ShareFn? onShare;

  /// Data w protokole (domyślnie dziś).
  final DateTime Function()? clock;

  const Iso5817Page({super.key, this.onShare, this.clock});

  @override
  State<Iso5817Page> createState() => _Iso5817PageState();
}

class _Iso5817PageState extends State<Iso5817Page> {
  Iso5817Level _level = Iso5817Level.c;
  Iso5817WeldKind _kind = Iso5817WeldKind.butt;
  String _itemId = '1.7';
  bool _isShort = true;

  final _t = TextEditingController();
  final _b = TextEditingController();
  final _bRoot = TextEditingController();
  final _a = TextEditingController();
  final _measured = TextEditingController();
  final _checkKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    for (final c in _controllers) {
      c.addListener(_recalc);
    }
  }

  List<TextEditingController> get _controllers =>
      [_t, _b, _bRoot, _a, _measured];

  void _recalc() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Iso5817Input get _input => Iso5817Input(
        t: parseDecimal(_t.text),
        b: parseDecimal(_b.text),
        bRoot:
            _kind == Iso5817WeldKind.butt ? parseDecimal(_bRoot.text) : null,
        a: _kind == Iso5817WeldKind.fillet ? parseDecimal(_a.text) : null,
      );

  Iso5817Item get _item {
    final item = iso5817ItemById(_itemId);
    if (item != null && item.appliesTo(_kind)) return item;
    return iso5817ItemsFor(_kind).first;
  }

  void _setLevel(Iso5817Level level) {
    Haptic.tap();
    setState(() => _level = level);
  }

  void _setKind(Iso5817WeldKind kind) {
    Haptic.tap();
    final current = iso5817ItemById(_itemId);
    var itemId = _itemId;
    if (current == null || !current.appliesTo(kind)) {
      // Ta sama pozycja normy dla drugiego rodzaju spoiny (1.3, 1.12),
      // inaczej podtopienie — dotyczy obu.
      final twin = iso5817ItemsFor(kind)
          .where((i) => current != null && i.no == current.no);
      itemId = twin.isNotEmpty ? twin.first.id : '1.7';
    }
    setState(() {
      _kind = kind;
      _itemId = itemId;
    });
    // Pomiar dotyczył innej niezgodności — werdykt nie może go użyć.
    if (itemId != current?.id) _measured.clear();
  }

  void _selectItem(String id, {bool scroll = false}) {
    if (id != _itemId) {
      Haptic.tap();
      setState(() => _itemId = id);
      // Pomiar dotyczył innej niezgodności — werdykt nie może go użyć.
      _measured.clear();
    }
    if (scroll) {
      final ctx = _checkKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 250));
      }
    }
  }

  Future<void> _share(Iso5817Assessment a) async {
    final en = context.language == AppLanguage.en;
    final text = buildIso5817Report(
      assessment: a,
      kind: _kind,
      input: _input,
      en: en,
      date: (widget.clock ?? DateTime.now)(),
    );
    final subject = context.tr(
      pl: 'Odbiór spoiny ISO 5817 — ${a.item.no}',
      en: 'Weld acceptance ISO 5817 — ${a.item.no}',
    );
    try {
      final fn = widget.onShare;
      if (fn != null) {
        await fn(text, subject);
      } else {
        await Share.share(text, subject: subject);
      }
    } catch (e) {
      debugPrint('iso5817 share failed: $e');
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

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final input = _input;
    final item = _item;
    final assessment = assessIso5817(
      item: item,
      required: _level,
      input: input,
      measured: parseDecimal(_measured.text),
      isShort: _isShort,
    );
    final t = input.t;
    final outOfScope = t != null && t > 0 && t < kIso5817MinThicknessMm;
    final range = iso5817Range(t);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Odbiór spoin ISO 5817', en: 'Weld acceptance ISO 5817')),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          Text(
            context.tr(
              pl: 'Wpisz poziom jakości z rysunku lub specyfikacji i wymiary '
                  'złącza. Aplikacja liczy dopuszczalne wymiary niezgodności '
                  'zewnętrznych (VT) wg EN ISO 5817:2014, tablica 1, i ocenia '
                  'Twój pomiar.',
              en: 'Enter the quality level from the drawing or specification '
                  'and the joint dimensions. The app works out the permitted '
                  'size of surface imperfections (VT) per EN ISO 5817:2014, '
                  'Table 1, and checks your measurement.',
            ),
            style: const TextStyle(color: kTextSec, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 12),
          const _DisclaimerBox(),
          const SizedBox(height: 18),
          _SectionTitle(context.tr(pl: 'Złącze', en: 'Joint')),
          const SizedBox(height: 8),
          _levelSelector(context),
          const SizedBox(height: 10),
          _kindSelector(context),
          const SizedBox(height: 14),
          _numField(
            key: const ValueKey('iso5817-t'),
            controller: _t,
            label: context.tr(pl: 'Grubość t (mm)', en: 'Thickness t (mm)'),
            helper: context.tr(
                pl: 'Nominalna grubość ścianki / blachy (przy różnych — cieńsza)',
                en: 'Nominal wall / plate thickness (if different — the thinner)'),
          ),
          _numField(
            key: const ValueKey('iso5817-b'),
            controller: _b,
            label: context.tr(
                pl: 'Szerokość lica b (mm)', en: 'Face width b (mm)'),
            helper: context.tr(
                pl: 'Do nadlewu lica, wypukłości i nawisu',
                en: 'For excess weld metal, convexity and overlap'),
          ),
          if (_kind == Iso5817WeldKind.butt)
            _numField(
              key: const ValueKey('iso5817-broot'),
              controller: _bRoot,
              label: context.tr(
                  pl: 'Szerokość grani b (mm)', en: 'Root width b (mm)'),
              helper: context.tr(
                  pl: 'Do nadmiernego nadlewu grani (1.11)',
                  en: 'For excess penetration (1.11)'),
            )
          else
            _numField(
              key: const ValueKey('iso5817-a'),
              controller: _a,
              label: context.tr(
                  pl: 'Grubość spoiny a (mm)', en: 'Throat thickness a (mm)'),
              helper: context.tr(
                  pl: 'Nominalna grubość spoiny pachwinowej z rysunku',
                  en: 'Nominal fillet weld throat from the drawing'),
            ),
          if (outOfScope)
            _Notice(
              color: kFail,
              icon: Icons.block,
              text: context.tr(
                pl: 't < 0,5 mm — EN ISO 5817 nie obejmuje tej grubości.',
                en: 't < 0.5 mm — EN ISO 5817 does not cover this thickness.',
              ),
            )
          else if (range != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                range == Iso5817Range.thin
                    ? context.tr(
                        pl: 'Zakres tablicy 1: 0,5–3 mm',
                        en: 'Table 1 range: 0.5–3 mm')
                    : context.tr(
                        pl: 'Zakres tablicy 1: t > 3 mm',
                        en: 'Table 1 range: t > 3 mm'),
                style: const TextStyle(color: kTextMut, fontSize: 12),
              ),
            ),
          const SizedBox(height: 18),
          KeyedSubtree(
            key: _checkKey,
            child: _SectionTitle(
                context.tr(pl: 'Sprawdź pomiar', en: 'Check a measurement')),
          ),
          const SizedBox(height: 8),
          _itemDropdown(context, item, en),
          const SizedBox(height: 12),
          if (item.measure != Iso5817Measure.presence)
            _numField(
              key: const ValueKey('iso5817-measured'),
              controller: _measured,
              label: item.measure == Iso5817Measure.angleDeg
                  ? context.tr(
                      pl: 'Zmierzony kąt ${item.symbol} (°)',
                      en: 'Measured angle ${item.symbol} (°)')
                  : context.tr(
                      pl: 'Zmierzone ${item.symbol} (mm)',
                      en: 'Measured ${item.symbol} (mm)'),
              helper: en ? item.measureEn : item.measurePl,
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                context.tr(
                  pl: 'Ocena obecności — wybranie pozycji oznacza, że '
                      'niezgodność stwierdzono.',
                  en: 'Presence check — choosing this item means the '
                      'imperfection was found.',
                ),
                style: const TextStyle(color: kTextSec, fontSize: 12),
              ),
            ),
          if (assessment.anyShortOnly &&
              item.measure != Iso5817Measure.presence)
            _shortSwitch(context),
          const SizedBox(height: 6),
          _RequiredReadout(assessment: assessment, input: input, en: en),
          const SizedBox(height: 14),
          _VerdictBox(assessment: assessment, en: en),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('iso5817-share'),
            onPressed: assessment.outcome == Iso5817Outcome.incomplete
                ? null
                : () => _share(assessment),
            icon: const Icon(Icons.share_outlined),
            label: Text(context.tr(
                pl: 'Udostępnij wynik do protokołu',
                en: 'Share the result for the report')),
          ),
          const SizedBox(height: 24),
          _SectionTitle(context.tr(
            pl: 'Dopuszczalne wartości — poziom ${_level.letter}',
            en: 'Permitted values — level ${_level.letter}',
          )),
          const SizedBox(height: 4),
          Text(
            context.tr(
              pl: 'Dotknij pozycji, aby sprawdzić pomiar. „Krótkie” = suma '
                  'długości ≤ 25 mm na 100 mm spoiny (spoina < 100 mm: '
                  '≤ 25 % jej długości).',
              en: 'Tap an item to check a measurement. “Short” = total '
                  'length ≤ 25 mm per 100 mm of weld (weld < 100 mm: '
                  '≤ 25 % of its length).',
            ),
            style: const TextStyle(color: kTextMut, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 8),
          for (final i in iso5817ItemsFor(_kind))
            _ItemCard(
              key: ValueKey('iso5817-card-${i.id}'),
              item: i,
              input: input,
              level: _level,
              selected: i.id == item.id,
              en: en,
              onTap: () => _selectItem(i.id, scroll: true),
            ),
          const SizedBox(height: 10),
          Text(
            context.tr(
              pl: 'Źródło: EN ISO 5817:2014, tablica 1 (poz. 1.1–1.24, '
                  '3.1–3.2), referencje ISO 6520-1. Limity w mm zaokrąglone '
                  'w dół do 0,01 mm. Niezgodności wewnętrzne (RT/UT) i '
                  'zmęczeniowe wymagania z zał. C nie są tu oceniane.',
              en: 'Source: EN ISO 5817:2014, Table 1 (items 1.1–1.24, '
                  '3.1–3.2), ISO 6520-1 references. Limits in mm rounded down '
                  'to 0.01 mm. Internal imperfections (RT/UT) and the fatigue '
                  'requirements of Annex C are not assessed here.',
            ),
            style: const TextStyle(
                color: kTextMut, fontSize: 11, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _levelSelector(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            context.tr(pl: 'Poziom jakości', en: 'Quality level'),
            style: const TextStyle(color: kText, fontSize: 14),
          ),
        ),
        SegmentedButton<Iso5817Level>(
          key: const ValueKey('iso5817-level'),
          showSelectedIcon: false,
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(56, kMinTapTarget)),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          segments: [
            for (final l in Iso5817Level.values)
              ButtonSegment(
                value: l,
                label: Text(l.letter,
                    key: ValueKey('iso5817-level-${l.letter}'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
          ],
          selected: {_level},
          onSelectionChanged: (s) => _setLevel(s.first),
        ),
      ],
    );
  }

  Widget _kindSelector(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<Iso5817WeldKind>(
        key: const ValueKey('iso5817-kind'),
        showSelectedIcon: false,
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(0, kMinTapTarget)),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        segments: [
          ButtonSegment(
            value: Iso5817WeldKind.butt,
            label: Text(context.tr(pl: 'Czołowa', en: 'Butt')),
          ),
          ButtonSegment(
            value: Iso5817WeldKind.fillet,
            label: Text(context.tr(pl: 'Pachwinowa', en: 'Fillet')),
          ),
        ],
        selected: {_kind},
        onSelectionChanged: (s) => _setKind(s.first),
      ),
    );
  }

  Widget _itemDropdown(BuildContext context, Iso5817Item item, bool en) {
    return DropdownButtonFormField<String>(
      // Klucz zależny od wyboru: zmiana z listy kart / rodzaju spoiny
      // przebudowuje pole z nową wartością.
      key: ValueKey('iso5817-item-${_kind.name}-${item.id}'),
      initialValue: item.id,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: context.tr(pl: 'Niezgodność', en: 'Imperfection'),
      ),
      items: [
        for (final i in iso5817ItemsFor(_kind))
          DropdownMenuItem(
            value: i.id,
            child: Text(
              '${i.no} · ${en ? i.nameEn : i.namePl}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (id) {
        if (id != null) _selectItem(id);
      },
    );
  }

  Widget _shortSwitch(BuildContext context) {
    return SwitchListTile(
      key: const ValueKey('iso5817-short'),
      contentPadding: EdgeInsets.zero,
      value: _isShort,
      onChanged: (v) {
        Haptic.tap();
        setState(() => _isShort = v);
      },
      title: Text(
        context.tr(pl: 'Niezgodność krótka', en: 'Short imperfection'),
        style: const TextStyle(color: kText, fontSize: 14),
      ),
      subtitle: Text(
        context.tr(
          pl: 'Σ długości ≤ 25 mm na 100 mm spoiny (spoina < 100 mm: ≤ 25 % '
              'długości). Wyłącz dla niezgodności długiej / ciągłej.',
          en: 'Total length ≤ 25 mm per 100 mm of weld (weld < 100 mm: '
              '≤ 25 % of length). Switch off for a long / continuous one.',
        ),
        style: const TextStyle(color: kTextSec, fontSize: 12),
      ),
    );
  }

  Widget _numField({
    required Key key,
    required TextEditingController controller,
    required String label,
    String? helper,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: key,
        controller: controller,
        keyboardType: numberKeyboard(),
        inputFormatters: numberInputFormatters(),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper == null || helper.isEmpty ? null : helper,
          helperMaxLines: 2,
        ),
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

class _Notice extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _Notice({required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: kTextSec, fontSize: 12, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _DisclaimerBox extends StatelessWidget {
  const _DisclaimerBox();

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    return Container(
      key: const ValueKey('iso5817-disclaimer'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kWarn.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kWarn.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.gavel_outlined, color: kWarn, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              iso5817Disclaimer(en: en),
              style: const TextStyle(color: kText, fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// Limit wymaganego poziomu dla wybranej pozycji — wynik główny (bursztyn).
class _RequiredReadout extends StatelessWidget {
  final Iso5817Assessment assessment;
  final Iso5817Input input;
  final bool en;
  const _RequiredReadout(
      {required this.assessment, required this.input, required this.en});

  @override
  Widget build(BuildContext context) {
    final a = assessment;
    final limit = a.requiredLimit;
    final item = a.item;
    final rule = limit.rule;
    final ruleText = rule == null
        ? ''
        : iso5817RuleText(rule, en: en, symbol: item.symbol);
    final calc = iso5817LimitCalc(limit, input, en: en);
    final isValue = limit.status == Iso5817LimitStatus.value;
    final value = isValue ? iso5817Num(limit.value!, en: en) : '—';
    final unit = isValue
        ? (limit.isAngle
            ? context.tr(pl: '° minimum', en: '° minimum')
            : 'mm${limit.shortOnly ? context.tr(pl: ' · tylko krótkie', en: ' · short only') : ''}')
        : iso5817LimitValueText(limit, en: en);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Readout(
          key: const ValueKey('iso5817-limit'),
          label: context.tr(
            pl: 'Limit ${item.no} — poziom ${a.required.letter}',
            en: 'Limit ${item.no} — level ${a.required.letter}',
          ),
          value: value,
          unit: unit,
          hot: true,
        ),
        if (ruleText.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            calc.isEmpty ? ruleText : '$ruleText\n$calc',
            style: const TextStyle(color: kTextSec, fontSize: 12, height: 1.4),
          ),
        ],
      ],
    );
  }
}

Color _outcomeColor(Iso5817Outcome o) => switch (o) {
      Iso5817Outcome.pass => kPass,
      Iso5817Outcome.below => kWarn,
      Iso5817Outcome.fail => kFail,
      Iso5817Outcome.conditional => kWarn,
      Iso5817Outcome.incomplete => kTextSec,
    };

IconData _outcomeIcon(Iso5817Outcome o) => switch (o) {
      Iso5817Outcome.pass => Icons.check_circle_outline,
      Iso5817Outcome.below => Icons.warning_amber_rounded,
      Iso5817Outcome.fail => Icons.cancel_outlined,
      Iso5817Outcome.conditional => Icons.help_outline,
      Iso5817Outcome.incomplete => Icons.edit_outlined,
    };

class _VerdictBox extends StatelessWidget {
  final Iso5817Assessment assessment;
  final bool en;
  const _VerdictBox({required this.assessment, required this.en});

  @override
  Widget build(BuildContext context) {
    final a = assessment;
    final color = _outcomeColor(a.outcome);
    final headline = iso5817Headline(a, en: en);
    final subline = iso5817Subline(a, en: en);
    final item = a.item;
    final remark = en ? item.remarkEn : item.remarkPl;
    final note2023 = en ? item.note2023En : item.note2023Pl;
    return Container(
      key: const ValueKey('iso5817-verdict'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_outcomeIcon(a.outcome), color: color, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: CopyOnLongPress(
                  value: headline,
                  label: context.tr(pl: 'Wynik', en: 'Result'),
                  child: Text(
                    headline,
                    key: const ValueKey('iso5817-headline'),
                    style: TextStyle(
                        color: color,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.3),
                  ),
                ),
              ),
            ],
          ),
          if (subline.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(subline,
                key: const ValueKey('iso5817-subline'),
                style: const TextStyle(color: kText, fontSize: 13)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final level in Iso5817Level.values)
                _LevelChip(
                  level: level,
                  limit: a.limits[level]!,
                  meets: a.meets[level],
                  required: level == a.required,
                  en: en,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${item.no} · ${en ? item.nameEn : item.namePl} · '
            'ISO 6520-1: ${item.codes.join(', ')}',
            style: const TextStyle(color: kTextSec, fontSize: 12),
          ),
          if (remark.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(remark,
                style: const TextStyle(color: kTextMut, fontSize: 12)),
          ],
          if (note2023.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(note2023,
                style: const TextStyle(
                    color: kTextMut,
                    fontSize: 12,
                    fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  final Iso5817Level level;
  final Iso5817Limit limit;
  final bool? meets;
  final bool required;
  final bool en;
  const _LevelChip({
    required this.level,
    required this.limit,
    required this.meets,
    required this.required,
    required this.en,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (meets) {
      true => kPass,
      false => kFail,
      null => kTextMut,
    };
    final icon = switch (meets) {
      true => Icons.check,
      false => Icons.close,
      null => Icons.remove,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: required ? kText : kBorder, width: required ? 1.5 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            '${level.letter} ${iso5817LimitValueText(limit, en: en)}',
            style: TextStyle(
              color: required ? kText : kTextSec,
              fontSize: 13,
              fontWeight: required ? FontWeight.w700 : FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final Iso5817Item item;
  final Iso5817Input input;
  final Iso5817Level level;
  final bool selected;
  final bool en;
  final VoidCallback onTap;
  const _ItemCard({
    super.key,
    required this.item,
    required this.input,
    required this.level,
    required this.selected,
    required this.en,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final limits = iso5817Limits(item, input);
    final req = limits[level]!;
    final range = iso5817Range(input.t);
    final rule = range == null ? null : iso5817RuleFor(item, level, range);
    final remark = en ? item.remarkEn : item.remarkPl;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: kCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
              color: selected ? kArc : kBorder, width: selected ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.no,
                        style: const TextStyle(
                            color: kTextSec,
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(en ? item.nameEn : item.namePl,
                          style: const TextStyle(
                              color: kText,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      iso5817LimitValueText(req, en: en),
                      style: const TextStyle(
                        color: kText,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('ISO 6520-1: ${item.codes.join(', ')}',
                    style: const TextStyle(color: kTextMut, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    for (final l in Iso5817Level.values)
                      Text(
                        '${l.letter} ${iso5817LimitValueText(limits[l]!, en: en)}',
                        style: TextStyle(
                          color: l == level ? kText : kTextSec,
                          fontSize: 12,
                          fontWeight:
                              l == level ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                  ],
                ),
                if (rule != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    iso5817RuleText(rule, en: en, symbol: item.symbol),
                    style: const TextStyle(color: kTextSec, fontSize: 12),
                  ),
                ],
                if (remark.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(remark,
                      style: const TextStyle(color: kTextMut, fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
