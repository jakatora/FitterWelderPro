import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/app_language.dart';
import '../services/material_catalog.dart';
import '../theme/app_theme.dart' show kTextMut;
import '../utils/haptic.dart';

const _kCard   = Color(0xFF141821);
const _kBorder = Color(0xFF2A3140);
const _kOrange = Color(0xFFFF8E1E);
const _kGreen  = Color(0xFF2ECC71);
const _kSec    = Color(0xFF9BA3C7);
const _kMuted  = kTextMut; // token motywu (kontrast ≥ 4,5:1)

class _Check {
  /// Stable identifier for persistence — must NEVER change once shipped,
  /// or saved ticks will silently disappear / drift to wrong items.
  /// Format: `<scope>-<short-slug>`, e.g. 'univ-fitup-gap', 'p10-interpass'.
  final String id;
  final String pl;
  final String en;
  const _Check(this.id, this.pl, this.en);
}

/// Pre-weld checklist for hygienic stainless tube — the run-through a welder
/// does before every joint. Ticks are saved for the current day so an app
/// restart mid-inspection does not lose them, but ticks restored from an
/// earlier session never count as "all set" until the welder confirms they
/// belong to the weld in front of them (audit 2026-09: one morning run used
/// to show "all set" for every later weld that day).
///
/// Material-specific extra checks. Pulled in when the welder picks a grade
/// from the catalog. Keeps the universal list short and adds only the items
/// that matter for the actual joint in front of them (P91 needs PWHT setup,
/// Duplex needs ferrite check, etc.). Keyed by ASME IX P-No string — P22
/// (5A) and P91 (15E) have different preheat and PWHT and must not share
/// one list.
const Map<String, List<_Check>> _pNumberExtras = {
  // P-No 1 — C-Mn steel
  '1': [
    _Check('p1-low-h-electrode',
           'Elektroda E7018 / drut ER70S-2 w zamkniętym piecu (low-H)',
           'E7018 / ER70S-2 from sealed oven (low-H)'),
    _Check('p1-bevel-clean',
           'Bevel 30° czysty, brak rdzy, kupon poradiowany jeśli >25 mm',
           'Bevel 30° clean, no rust, radiograph if >25 mm'),
  ],
  // P-No 4 — 1¼Cr-½Mo
  '4': [
    _Check('p4-preheat',
           'Preheat 150-200°C zmierzony pirometrem przed pierwszą ściegą',
           'Preheat 150-200°C verified with pyrometer before first pass'),
    _Check('p4-filler-b-grade',
           'Drut/elektroda zgodna z B-grade (ER80S-B2 / E8018-B2)',
           'Filler matches B-grade (ER80S-B2 / E8018-B2)'),
    _Check('p4-pwht-scheduled',
           'PWHT zaplanowany — termin i piec zarezerwowane',
           'PWHT scheduled — slot and furnace booked'),
  ],
  // P-No 5A — 2¼Cr-1Mo (P22). Values follow the catalog entry.
  '5A': [
    _Check('p5a-preheat',
           'Preheat 200–250 °C wg WPS, interpass max 300 °C — pirometr przed pierwszą ściegą',
           'Preheat 200–250 °C per WPS, interpass max 300 °C — pyrometer before first pass'),
    _Check('p5a-filler-cert',
           'Elektroda E9018-B3 (lub wg WPS) z certyfikatem HEAT',
           'E9018-B3 electrode (or per WPS) with HEAT certificate'),
    _Check('p5a-pwht',
           'PWHT 690–720 °C / 1 h na cal wg WPS — slot zarezerwowany',
           'PWHT 690–720 °C / 1 h per inch per WPS — slot booked'),
    _Check('p5a-no-cs-cross',
           'Brak kontaktu CS↔CrMo (uziemienie, narzędzia)',
           'No CS↔CrMo cross-contact (ground clamp, tools)'),
  ],
  // P-No 15E — 9Cr-1Mo-V (P91). Values follow the catalog entry.
  '15E': [
    _Check('p15e-critical-preheat',
           'PREHEAT KRYTYCZNY 200–250 °C, interpass 250–300 °C',
           'CRITICAL preheat 200–250 °C, interpass 250–300 °C'),
    _Check('p15e-filler-cert',
           'Elektroda E9015-B9 z certyfikatem HEAT',
           'E9015-B9 electrode with HEAT certificate'),
    _Check('p15e-pwht-mandatory',
           'PWHT 750–770 °C / 1 h na cal OBOWIĄZKOWE — slot zarezerwowany',
           'PWHT 750–770 °C / 1 h per inch MANDATORY — slot booked'),
    _Check('p15e-no-cs-cross',
           'Brak kontaktu CS↔CrMo (uziemienie, narzędzia)',
           'No CS↔CrMo cross-contact (ground clamp, tools)'),
  ],
  // P-No 8 — Austenitic SS
  '8': [
    _Check('p8-interpass-175',
           'Interpass <175°C — pirometr przed kolejną ściegą',
           'Interpass <175°C — pyrometer before next bead'),
    _Check('p8-l-grade-filler',
           'Drut L-grade (ER308L/ER316L) — niski C zapobiega sensitization',
           'L-grade filler (ER308L/ER316L) — low C prevents sensitization'),
    _Check('p8-argon-pure',
           'Argon czysty, brak N₂ w gazie formującym',
           'Argon pure, no N₂ in backing gas'),
    _Check('p8-passivation',
           'Pasywacja po spawaniu zaplanowana (kwas azotowy)',
           'Post-weld passivation scheduled (nitric acid)'),
  ],
  // P-No 10H — Duplex
  '10H': [
    _Check('p10-interpass-max',
           'Interpass MAX 150°C (2205) / 100°C (2507) — pirometr CO 2 ściegi',
           'Interpass MAX 150°C (2205) / 100°C (2507) — pyrometer every 2 passes'),
    _Check('p10-backing-gas-n2',
           'Gaz formujący Ar + 2% N₂ (utrzymanie austenitu)',
           'Backing gas Ar + 2% N₂ (austenite balance)'),
    _Check('p10-hi-window',
           'HI w oknie 0.5-2.5 kJ/mm — wyższy → σ-phase',
           'HI in 0.5-2.5 kJ/mm window — higher → σ-phase'),
    _Check('p10-ferrite-check',
           'Ferrite check po cooldown (target 30-60 FN)',
           'Ferrite check after cooldown (target 30-60 FN)'),
  ],
  // P-No 41-45 — Ni alloys
  '43': [
    _Check('p43-low-hi',
           'Niski HI <1.5 kJ/mm — narrow string beads',
           'Low HI <1.5 kJ/mm — narrow string beads'),
    _Check('p43-argon-pure',
           'Argon czysty (>99.99%), brak Helium na nierdzewce',
           'Pure argon (>99.99%), no Helium on SS'),
    _Check('p43-ercr-mo3-wire',
           'Drut ERNiCrMo-3 (625) z certyfikatu',
           'ERNiCrMo-3 (625) wire with cert'),
  ],
};

const List<_Check> _checks = [
  _Check('univ-fitup-gap',
         'Szczelina fit-up ≈ 0, rury współosiowe (brak przesunięcia lic)',
         'Fit-up gap ≈ 0, tubes aligned (no land mismatch)'),
  _Check('univ-tube-ends-clean',
         'Końce rur czyste — odtłuszczone, bez śladów markera',
         'Tube ends clean — degreased, no marker ink'),
  _Check('univ-backing-gas',
         'Gaz formujący podłączony, tamy/korki purge założone',
         'Backing gas connected, purge dams/plugs fitted'),
  _Check('univ-gas-flow',
         'Przepływ gazu osłonowego i formującego ustawiony',
         'Shielding and backing gas flow set'),
  _Check('univ-o2-limit',
         'O₂ w gazie formującym poniżej limitu (miernik)',
         'Backing-gas O₂ below the limit (meter checked)'),
  _Check('univ-pre-purge',
         'Pre-purge odczekany — powietrze wypłukane',
         'Pre-purge time elapsed — air flushed out'),
  _Check('univ-tungsten',
         'Elektroda wolframowa zaostrzona, czysta, właściwa średnica',
         'Tungsten electrode sharp, clean, correct diameter'),
  _Check('univ-wps-params',
         'Parametry maszyny zgodne z WPS / programem',
         'Machine parameters match the WPS / program'),
  _Check('univ-test-coupon',
         'Kupon próbny dnia wykonany i zaakceptowany',
         "Today's test coupon welded and accepted"),
  _Check('univ-weld-no',
         'Numer spoiny naniesiony, weld map zaktualizowana',
         'Weld number marked, weld map updated'),
  _Check('univ-tools-ss-only',
         'Narzędzia dedykowane do nierdzewki (brak kontaktu z żelazem)',
         'Stainless-only tools used (no iron cross-contamination)'),
];

/// Scans a preheatNote like "200–250 °C, interpass 250–300 °C" for °C numbers
/// and appends a "  (~390–480 °F)" tail. Best-effort — if no °C number is
/// found (notes like "Bez preheat.") returns an empty string so the tooltip
/// stays clean.
String _preheatFahrenheit(String note) {
  final matches = RegExp(r'(\d+)\s*°?\s*C').allMatches(note).toList();
  if (matches.isEmpty) return '';
  final fs = matches
      .map((m) => (int.parse(m.group(1)!) * 9 / 5 + 32).round())
      .toList();
  final tail = fs.length == 1
      ? '${fs.first} °F'
      : '${fs.reduce((a, b) => a < b ? a : b)}–${fs.reduce((a, b) => a > b ? a : b)} °F';
  return '  (~$tail)';
}

class PreWeldChecklistScreen extends StatefulWidget {
  const PreWeldChecklistScreen({super.key});

  @override
  State<PreWeldChecklistScreen> createState() => _PreWeldChecklistScreenState();
}

class _PreWeldChecklistScreenState extends State<PreWeldChecklistScreen> {
  /// P0-12: persistent set of check IDs (was: index-based int set). Indexed
  /// state silently drifted when material changed (P-No 8 → P-No 10
  /// reshuffled indices 11+ to point at Duplex-critical items pre-ticked
  /// against austenitic context — false-affirming a safety check). Stable
  /// IDs persist correctly across material changes AND across cold starts.
  final Set<String> _done = <String>{};
  MaterialSpec? _material;

  /// Ticks came back from SharedPreferences (an earlier session today) and
  /// the welder has not yet confirmed they belong to THIS weld. While true,
  /// a complete list never shows "all set".
  bool _restoredNeedsConfirm = false;

  static const _kDoneKeyPrefix = 'preweld_done_';
  static const _kMaterialKeyPrefix = 'preweld_material_';

  String get _todayKey {
    final n = DateTime.now();
    final ymd = '${n.year}-'
        '${n.month.toString().padLeft(2, "0")}-'
        '${n.day.toString().padLeft(2, "0")}';
    return ymd;
  }

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // P0-12: also sweep any preweld_* entries from previous days so the
      // device doesn't accumulate stale safety state. Auto-clears at
      // midnight is the implicit guarantee.
      final today = _todayKey;
      for (final k in prefs.getKeys()) {
        if (!k.startsWith(_kDoneKeyPrefix) &&
            !k.startsWith(_kMaterialKeyPrefix)) {
          continue;
        }
        final tail = k.substring(k.lastIndexOf('_') + 1);
        if (tail != today) {
          await prefs.remove(k);
        }
      }
      final savedIds = prefs.getStringList('$_kDoneKeyPrefix$today');
      final savedMaterialKey = prefs.getString('$_kMaterialKeyPrefix$today');
      if (!mounted) return;
      var droppedStale = false;
      setState(() {
        if (savedIds != null) {
          _done
            ..clear()
            ..addAll(savedIds);
        }
        if (savedMaterialKey != null) {
          _material = MaterialCatalog.findByKey(savedMaterialKey);
        }
        // A saved tick whose check is no longer on the list (renamed
        // catalog key, material that failed to restore) must not count
        // towards "all set" — that would false-affirm an unchecked item.
        final validIds = _all.map((c) => c.id).toSet();
        final before = _done.length;
        _done.removeWhere((id) => !validIds.contains(id));
        droppedStale = _done.length != before;
        _restoredNeedsConfirm = _done.isNotEmpty;
      });
      if (droppedStale) _persist();
    } catch (_) {
      // Best-effort hydrate — leave the state in its default empty form
      // if SharedPreferences is unavailable / corrupted.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('$_kDoneKeyPrefix$_todayKey', _done.toList());
      final mat = _material?.key;
      if (mat == null) {
        await prefs.remove('$_kMaterialKeyPrefix$_todayKey');
      } else {
        await prefs.setString('$_kMaterialKeyPrefix$_todayKey', mat);
      }
    } catch (_) {
      // Best-effort — the in-memory state still reflects what the welder
      // ticked. The toggle helper still triggers Haptic so the user
      // confirmation is visible even if persistence fails.
    }
  }

  /// Combined check list = universal items + extras for the picked grade's
  /// P-Number. Stable IDs make ticks survive material swaps; the indices
  /// here are only used for ListView builder traversal.
  List<_Check> get _all {
    final list = <_Check>[..._checks];
    if (_material != null) {
      final extras = _pNumberExtras[_material!.pNo];
      if (extras != null) list.addAll(extras);
    }
    return list;
  }

  /// Number of ticked items that are actually on the current list. Counting
  /// `_done.length` directly would let a stale ID stand in for an unchecked
  /// item and show "all set" too early.
  int _doneCountIn(List<_Check> list) =>
      list.where((c) => _done.contains(c.id)).length;

  void _toggle(_Check check) {
    setState(() {
      if (_done.contains(check.id)) {
        _done.remove(check.id);
      } else {
        _done.add(check.id);
        Haptic.tap();
      }
    });
    final list = _all;
    if (!_restoredNeedsConfirm && _doneCountIn(list) == list.length) {
      Haptic.saved();
    }
    _persist();
  }

  /// P0-14: Wipe behind a confirm dialog + Undo snackbar. Without this a
  /// phantom thumb tap during scroll was silently erasing 60-90 s of careful
  /// pre-weld inspection — welder could strike arc believing the checklist
  /// was completed when it had been blanked by the same gesture used to
  /// scroll. Safety-critical.
  Future<void> _confirmReset() async {
    final tickedCount = _done.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(context.tr(
          pl: 'Nowa spoina — wyzerować checklistę?',
          en: 'New weld — reset checklist?',
        )),
        content: Text(context.tr(
          pl: '$tickedCount pozycji jest zaznaczonych. '
              'Tej operacji nie można cofnąć po zamknięciu pasków.',
          en: '$tickedCount items are ticked. '
              'This cannot be undone once the SnackBar disappears.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.shade400,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(context.tr(pl: 'Wyczyść', en: 'Reset')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Haptic.error();
    _clearForNewWeld(
      message: context.tr(
        pl: 'Checklistę wyczyszczono ($tickedCount pozycji).',
        en: 'Checklist reset ($tickedCount items).',
      ),
    );
  }

  /// Clears every tick so the next joint starts from 0/N. Used by the
  /// confirmed reset, by "New weld" on the restored-ticks banner and by the
  /// "arc struck" button after "all set". Undo restores the previous state
  /// (including whether the ticks still needed confirmation).
  void _clearForNewWeld({required String message}) {
    final snapshot = Set<String>.from(_done);
    final wasUnconfirmed = _restoredNeedsConfirm;
    setState(() {
      _done.clear();
      _restoredNeedsConfirm = false;
    });
    _persist();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: context.tr(pl: 'Cofnij', en: 'Undo'),
          onPressed: () {
            if (!mounted) return;
            setState(() {
              _done
                ..clear()
                ..addAll(snapshot);
              _restoredNeedsConfirm = wasUnconfirmed;
            });
            _persist();
          },
        ),
      ));
  }

  void _confirmSameWeld() {
    setState(() => _restoredNeedsConfirm = false);
    final list = _all;
    if (_doneCountIn(list) == list.length) Haptic.saved();
  }

  void _setMaterial(MaterialSpec? m) {
    setState(() {
      _material = m;
      // P0-12: with stable IDs we drop ticks that no longer have a
      // matching check in the new list (e.g. P-No 10 extras gone after
      // switching to P-No 8). Indices used to silently re-bind to
      // whatever check now lives at that index — that's the false-affirm
      // bug the audit flagged.
      final validIds = _all.map((c) => c.id).toSet();
      _done.removeWhere((id) => !validIds.contains(id));
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final isPl = context.language == AppLanguage.pl;
    final list = _all;
    final doneCount = _doneCountIn(list);
    final complete = list.isNotEmpty && doneCount == list.length;
    // Ticks restored from an earlier session never count as "all set" until
    // the welder confirms they belong to this weld.
    final all = complete && !_restoredNeedsConfirm;
    final awaitingConfirm = _restoredNeedsConfirm && _done.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(
            pl: 'Checklista przed spawaniem',
            en: 'Pre-weld checklist')),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.clear_all),
            label: Text(context.tr(pl: 'Nowa spoina', en: 'New weld')),
            onPressed: _done.isEmpty ? null : _confirmReset,
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress strip
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: all
                  ? _kGreen.withValues(alpha: 0.12)
                  : _kCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: all ? _kGreen.withValues(alpha: 0.5) : _kBorder),
            ),
            child: Row(
              children: [
                Icon(all ? Icons.check_circle : Icons.checklist_rtl,
                    color: all ? _kGreen : _kOrange, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    all
                        ? context.tr(
                            pl: 'Gotowe — możesz zajarzać łuk.',
                            en: 'All set — you can strike the arc.')
                        : complete
                            ? context.tr(
                                pl: 'Potwierdź, że zaznaczenia dotyczą tej spoiny.',
                                en: 'Confirm the ticks apply to this weld.')
                            : context.tr(
                                pl: 'Sprawdź wszystkie punkty przed spoiną.',
                                en: 'Tick every item before welding.'),
                    style: TextStyle(
                        color: all ? _kGreen : (complete ? _kOrange : _kSec),
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Text('$doneCount/${list.length}',
                    style: TextStyle(
                        color: all ? _kGreen : _kOrange,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          if (awaitingConfirm)
            _RestoredTicksBanner(
              text: context.tr(
                pl: 'Zaznaczenia zapisane wcześniej dziś '
                    '($doneCount/${list.length}). Dotyczą spoiny, którą '
                    'zaraz zaczynasz?',
                en: 'Ticks saved earlier today ($doneCount/${list.length}). '
                    'Do they apply to the weld you are about to start?',
              ),
              sameLabel: context.tr(pl: 'Ta sama spoina', en: 'Same weld'),
              newLabel: context.tr(pl: 'Nowa spoina', en: 'New weld'),
              onSame: _confirmSameWeld,
              onNew: () => _clearForNewWeld(
                message: context.tr(
                  pl: 'Nowa spoina — lista wyczyszczona.',
                  en: 'New weld — checklist cleared.',
                ),
              ),
            ),
          if (all)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  icon: const Icon(Icons.restart_alt),
                  label: Text(context.tr(
                    pl: 'Łuk zajarzony — wyczyść dla następnej spoiny',
                    en: 'Arc struck — clear for next weld',
                  )),
                  onPressed: () => _clearForNewWeld(
                    message: context.tr(
                      pl: 'Lista wyczyszczona — gotowa na następną spoinę.',
                      en: 'Checklist cleared — ready for the next weld.',
                    ),
                  ),
                ),
              ),
            ),
          // Material picker — adds grade-specific checks (P91 needs PWHT slot,
          // Duplex needs ferrite check, etc.) on top of the universal list.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SizedBox(
              // Glove-friendly: 48dp min strip so material picker chips meet
              // the WCAG/MD3 touch target — these chips gate grade-specific
              // safety checks (P91 PWHT, Duplex ferrite) and must be tappable
              // through a thick welding glove without hunting.
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ChoiceChip(
                    label: Text(context.tr(pl: 'wszystkie', en: 'generic'),
                        style: const TextStyle(fontSize: 11)),
                    selected: _material == null,
                    onSelected: (_) => _setMaterial(null),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  const SizedBox(width: 6),
                  for (final m in MaterialCatalog.all) ...[
                    // Long-press hint surfaces preheat range in both °C and °F
                    // for welders cross-reading EU WPS against US ASME spec sheets
                    // without retyping into a converter.
                    Tooltip(
                      message: '${m.key}: ${isPl ? m.practicePl : m.practiceEn}'
                          '${_preheatFahrenheit(isPl ? m.practicePl : m.practiceEn)}',
                      child: ChoiceChip(
                        label: Text(m.key, style: const TextStyle(fontSize: 11)),
                        selected: _material?.key == m.key,
                        onSelected: (_) => _setMaterial(m),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final c = list[i];
                final done = _done.contains(c.id);
                final isExtra = i >= _checks.length;
                // Group divider before the first material-specific extra so the
                // jump from universal → grade-specific is visible at a glance.
                final showDivider = isExtra && i == _checks.length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showDivider && _material != null)
                      _SectionDivider(
                        label: context.tr(
                            pl: 'Specyficzne · ${_material!.key}',
                            en: 'Specific to ${_material!.key}'),
                      ),
                    GestureDetector(
                      onTap: () => _toggle(c),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: _kCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: done
                              ? _kGreen.withValues(alpha: 0.5)
                              : _kBorder),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          done
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: done ? _kGreen : _kMuted,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isExtra && _material != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Text(
                                    '${_material!.key} · P${_material!.pNo}',
                                    style: const TextStyle(
                                      // P3-08: bumped 9 → 11 pt min for
                                      // micro labels (outdoor readability +
                                      // WCAG-ish floor for inline P-No prefix
                                      // chip).
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: _kOrange,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              Text(
                                isPl ? c.pl : c.en,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: done
                                      ? _kMuted
                                      : const Color(0xFFE7ECF3),
                                  decoration: done
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when ticks were restored from an earlier session today: the welder
/// must say whether they belong to the weld in front of them before the
/// list can read "all set".
class _RestoredTicksBanner extends StatelessWidget {
  final String text;
  final String sameLabel;
  final String newLabel;
  final VoidCallback onSame;
  final VoidCallback onNew;
  const _RestoredTicksBanner({
    required this.text,
    required this.sameLabel,
    required this.newLabel,
    required this.onSame,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: _kOrange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kOrange.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.history, color: _kOrange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                      color: Color(0xFFE7ECF3), fontSize: 13, height: 1.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48)),
                  onPressed: onSame,
                  child: Text(sameLabel),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48)),
                  onPressed: onNew,
                  child: Text(newLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// P3-08: extracted divider widget used between the universal checklist
/// section and the material-specific section. Centralises the 1 dp rule +
/// 11 pt micro-label styling so the universal / specific transition reads
/// the same everywhere. Keeps min font 11 pt for outdoor readability —
/// previous 10 pt inline label fell below the floor the audit set for
/// micro labels on this safety-critical screen.
class _SectionDivider extends StatelessWidget {
  final String label;
  const _SectionDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: _kBorder)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: const TextStyle(
                // P3-08: 11 pt min for micro labels (was 10 pt — below floor).
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: _kOrange,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: _kBorder)),
        ],
      ),
    );
  }
}
