import 'package:flutter/material.dart';
import '../services/owned_prefs.dart';

import '../assistant/core/tool_bridge.dart';
import '../database/weld_journal_dao.dart';
import '../domain/weld_journal/coupon_entry.dart' show parseO2Ppm, formatO2Ppm;
import '../domain/weld_journal/weld_entry.dart';
import '../i18n/app_language.dart';
import '../services/material_catalog.dart';
import '../services/welder_identity.dart';
import '../theme/app_theme.dart' show kTextMut;
import '../utils/haptic.dart';
import '../widgets/number_field.dart';
import '../widgets/local_record_scope.dart';

const _kCard   = Color(0xFF141821);
const _kBorder = Color(0xFF2A3140);
const _kOrange = Color(0xFFFF8E1E);
const _kGreen  = Color(0xFF2ECC71);
const _kSec    = Color(0xFF9BA3C7);
const _kMuted  = kTextMut; // token motywu (kontrast ≥ 4,5:1)

/// Proces spawania — zestaw punktów zależy od niego (v25). MMA na stali
/// węglowej nie dostaje punktów gazu formującego, wolframu ani narzędzi do
/// nierdzewki: odhaczanie punktów, które nie dotyczą, uczy odhaczania bez
/// sprawdzania.
enum WeldingProcessKind {
  tigOrbital('tig-orb', 'TIG orbitalny', 'Orbital TIG'),
  tigManual('tig-man', 'TIG ręczny', 'Manual TIG'),
  mma('mma', 'MMA (111)', 'MMA / SMAW (111)'),
  mag('mag', 'MAG (135/136)', 'MAG / GMAW (135/136)');

  const WeldingProcessKind(this.id, this.labelPl, this.labelEn);
  final String id;
  final String labelPl;
  final String labelEn;

  bool get isTig => this == tigOrbital || this == tigManual;

  static WeldingProcessKind fromId(String? id) =>
      values.firstWhere((p) => p.id == id, orElse: () => tigOrbital);
}

/// Kiedy punkt uniwersalny ma sens.
enum _Scope {
  all,
  orbital,
  notOrbital,
  tig,

  /// Gaz formujący: TIG na nierdzewce / duplex / Ni / Cr-Mo z graniem TIG.
  backing,

  /// Sam gaz osłonowy (TIG bez formowania, MAG).
  shieldOnly,

  /// Nierdzewka / duplex / stopy Ni (albo materiał niewybrany — lista
  /// higieniczna).
  stainless,
  mma,
  mag,
}

bool _stainlessLike(MaterialSpec? m) =>
    m == null ||
    const {'8', '10H', '41', '42', '43', '44', '45'}.contains(m.pNo);

bool _needsBacking(WeldingProcessKind p, MaterialSpec? m) =>
    p.isTig && (_stainlessLike(m) || const {'5A', '15E'}.contains(m?.pNo));

bool _applies(_Scope s, WeldingProcessKind p, MaterialSpec? m) =>
    switch (s) {
      _Scope.all => true,
      _Scope.orbital => p == WeldingProcessKind.tigOrbital,
      _Scope.notOrbital => p != WeldingProcessKind.tigOrbital,
      _Scope.tig => p.isTig,
      _Scope.backing => _needsBacking(p, m),
      _Scope.shieldOnly =>
        (p.isTig || p == WeldingProcessKind.mag) && !_needsBacking(p, m),
      _Scope.stainless => _stainlessLike(m),
      _Scope.mma => p == WeldingProcessKind.mma,
      _Scope.mag => p == WeldingProcessKind.mag,
    };

class _Check {
  /// Stable identifier for persistence — must NEVER change once shipped,
  /// or saved ticks will silently disappear / drift to wrong items.
  /// Format: `<scope>-<short-slug>`, e.g. 'univ-fitup-gap', 'p10-interpass'.
  final String id;
  final String pl;
  final String en;
  final _Scope scope;
  const _Check(this.id, this.pl, this.en, [this.scope = _Scope.all]);
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
           'Elektrody zasadowe (np. E7018) z suszarki / piecyka wg producenta '
           '(low-H); drut TIG/MAG suchy i czysty',
           'Basic electrodes (e.g. E7018) from the drying / holding oven per '
           'the maker (low-H); TIG/MAG wire dry and clean'),
    _Check('p1-bevel-clean',
           'Ukos wg WPS (ISO 9692-1 zwykle 30°, rury ASME B16.25 37,5°), '
           'czysty, bez rdzy i zgorzeliny',
           'Bevel per WPS (ISO 9692-1 typically 30°, ASME B16.25 pipe '
           '37.5°), clean, no rust or mill scale'),
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
           'Gaz formujący zgodny z WPS (np. Ar I1 albo N₂ + H₂ — '
           'ISO 14175 N5), partia gazu sprawdzona',
           'Backing gas per WPS (e.g. Ar I1 or N₂ + H₂ — ISO 14175 N5), '
           'gas batch checked'),
    _Check('p8-passivation',
           'Trawienie / pasywacja po spawaniu zaplanowane wg specyfikacji '
           '(środek wg karty produktu — azotowy albo cytrynowy)',
           'Post-weld pickling / passivation scheduled per the specification '
           '(agent per the data sheet — nitric or citric)'),
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
           'Gaz osłonowy wg WPS (Ar ≥ 99,99 % albo mieszanka Ar/He — typowa '
           'dla stopów Ni)',
           'Shielding gas per WPS (Ar ≥ 99.99 % or an Ar/He mix — common for '
           'Ni alloys)'),
    _Check('p43-ercr-mo3-wire',
           'Drut ERNiCrMo-3 (625) z certyfikatu',
           'ERNiCrMo-3 (625) wire with cert'),
  ],
};

/// Punkty ogólne. Dla TIG orbitalnego bez wybranego materiału (lista
/// higieniczna, domyślna) to dokładnie 11 dawnych punktów; inne procesy
/// i materiały dostają tylko te, które ich dotyczą.
const List<_Check> _checks = [
  _Check('univ-fitup-gap',
         'Szczelina fit-up ≈ 0, rury współosiowe (brak przesunięcia lic)',
         'Fit-up gap ≈ 0, tubes aligned (no land mismatch)', _Scope.orbital),
  _Check('univ-fitup-wps',
         'Szczelina, ukos i przesunięcie lic (hi-lo) zgodne z WPS',
         'Root gap, bevel and hi-lo mismatch per WPS', _Scope.notOrbital),
  _Check('univ-tube-ends-clean',
         'Końce rur czyste — odtłuszczone, bez śladów markera',
         'Tube ends clean — degreased, no marker ink'),
  _Check('univ-backing-gas',
         'Gaz formujący podłączony, tamy/korki purge założone',
         'Backing gas connected, purge dams/plugs fitted', _Scope.backing),
  _Check('univ-gas-flow',
         'Przepływ gazu osłonowego i formującego ustawiony',
         'Shielding and backing gas flow set', _Scope.backing),
  _Check('univ-shield-flow',
         'Przepływ gazu osłonowego ustawiony, osłona od wiatru',
         'Shielding gas flow set, wind shield in place', _Scope.shieldOnly),
  _Check('univ-o2-limit',
         'O₂ w gazie formującym poniżej limitu (miernik)',
         'Backing-gas O₂ below the limit (meter checked)', _Scope.backing),
  _Check('univ-pre-purge',
         'Pre-purge odczekany — powietrze wypłukane',
         'Pre-purge time elapsed — air flushed out', _Scope.backing),
  _Check('univ-tungsten',
         'Elektroda wolframowa zaostrzona, czysta, właściwa średnica',
         'Tungsten electrode sharp, clean, correct diameter', _Scope.tig),
  _Check('mma-electrodes',
         'Elektrody wg WPS, wysuszone / z piecyka wg producenta, bez '
         'uszkodzonej otuliny',
         'Electrodes per WPS, dried / from the holding oven per the maker, '
         'no damaged coating', _Scope.mma),
  _Check('mag-torch',
         'Dysza i końcówka prądowa czyste, drut bez rdzy, podajnik OK',
         'Nozzle and contact tip clean, wire rust-free, feeder OK', _Scope.mag),
  _Check('univ-wps-params',
         'Parametry maszyny zgodne z WPS / programem',
         'Machine parameters match the WPS / program'),
  _Check('univ-test-coupon',
         'Kupon próbny dnia wykonany i zaakceptowany',
         "Today's test coupon welded and accepted", _Scope.orbital),
  _Check('univ-weld-no',
         'Numer spoiny naniesiony, weld map zaktualizowana',
         'Weld number marked, weld map updated'),
  _Check('univ-tools-ss-only',
         'Narzędzia dedykowane do nierdzewki (brak kontaktu z żelazem)',
         'Stainless-only tools used (no iron cross-contamination)',
         _Scope.stainless),
];

/// Dodatki dla P-No; stopy Ni 41–45 dzielą listę '43'.
List<_Check>? _extrasFor(String pNo) {
  final direct = _pNumberExtras[pNo];
  if (direct != null) return direct;
  if (const {'41', '42', '44', '45'}.contains(pNo)) return _pNumberExtras['43'];
  return null;
}

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

class PreWeldChecklistScreen extends StatelessWidget {
  const PreWeldChecklistScreen({super.key});

  @override
  Widget build(BuildContext context) => LocalRecordScope(
        builder: (_, session) => _PreWeldChecklistBody(session: session),
      );
}

class _PreWeldChecklistBody extends StatefulWidget {
  const _PreWeldChecklistBody({required this.session});
  final LocalRecordSession session;

  @override
  State<_PreWeldChecklistBody> createState() => _PreWeldChecklistScreenState();
}

class _PreWeldChecklistScreenState extends State<_PreWeldChecklistBody>
    with ToolHandleHost<_PreWeldChecklistBody>
    implements InputToolHandle {
  @override
  String get toolId => 'pre_weld_checklist';
  @override
  Set<String> get supportedFields => const {'process'};
  @override
  Map<String, Object?> get inputFields => Map.unmodifiable({
        'process': _process.id,
        'done': _done.length,
        'not_applicable': _na.length,
      });

  /// Asystent wybiera tylko proces (zestaw punktów). Odhaczanie zostaje
  /// spawaczowi — lista bezpieczeństwa nie jest wypełniana głosem.
  @override
  Future<Set<String>> apply(Map<String, Object?> fields) async {
    final p = WeldingProcessKind.values
        .where((k) => k.id == fields['process'])
        .firstOrNull;
    if (!mounted ||
        !widget.session.isCurrent ||
        fields.keys.any((k) => !supportedFields.contains(k)) ||
        p == null) {
      return fields.keys.toSet();
    }
    if (p != _process) _setProcess(p);
    return {};
  }

  /// P0-12: persistent set of check IDs (was: index-based int set). Indexed
  /// state silently drifted when material changed (P-No 8 → P-No 10
  /// reshuffled indices 11+ to point at Duplex-critical items pre-ticked
  /// against austenitic context — false-affirming a safety check). Stable
  /// IDs persist correctly across material changes AND across cold starts.
  final Set<String> _done = <String>{};

  /// Punkty oznaczone „nie dotyczy” — liczone osobno od sprawdzonych.
  final Set<String> _na = <String>{};
  MaterialSpec? _material;
  WeldingProcessKind _process = WeldingProcessKind.tigOrbital;

  /// Ticks came back from SharedPreferences (an earlier session today) and
  /// the welder has not yet confirmed they belong to THIS weld. While true,
  /// a complete list never shows "all set".
  bool _restoredNeedsConfirm = false;

  static const _kDoneKeyPrefix = 'preweld_done_';
  static const _kMaterialKeyPrefix = 'preweld_material_';
  static const _kNaKeyPrefix = 'preweld_na_';
  static const _kProcessKeyPrefix = 'preweld_process_';
  static const _kPrefixes = [
    _kDoneKeyPrefix,
    _kMaterialKeyPrefix,
    _kNaKeyPrefix,
    _kProcessKeyPrefix,
  ];

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
    // Gotowość po odczycie zapisu dnia — inaczej odczyt nadpisałby proces.
    _hydrate().whenComplete(() {
      if (mounted && widget.session.isCurrent) markReady();
    });
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await OwnedPrefs.instance(widget.session.captureOwner);
      // P0-12: also sweep any preweld_* entries from previous days so the
      // device doesn't accumulate stale safety state. Auto-clears at
      // midnight is the implicit guarantee.
      final today = _todayKey;
      for (final k in prefs.getKeys()) {
        if (!_kPrefixes.any(k.startsWith)) continue;
        final tail = k.substring(k.lastIndexOf('_') + 1);
        if (tail != today) {
          await prefs.remove(k);
        }
      }
      final savedIds = prefs.getStringList('$_kDoneKeyPrefix$today');
      final savedMaterialKey = prefs.getString('$_kMaterialKeyPrefix$today');
      final savedNa = prefs.getStringList('$_kNaKeyPrefix$today');
      final savedProcess = prefs.getString('$_kProcessKeyPrefix$today');
      if (!mounted || !widget.session.isCurrent) return;
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
        _process = WeldingProcessKind.fromId(savedProcess);
        if (savedNa != null) {
          _na
            ..clear()
            ..addAll(savedNa);
        }
        // A saved tick whose check is no longer on the list (renamed
        // catalog key, material that failed to restore) must not count
        // towards "all set" — that would false-affirm an unchecked item.
        final validIds = _all.map((c) => c.id).toSet();
        final before = _done.length;
        _done.removeWhere((id) => !validIds.contains(id));
        _na.removeWhere((id) => !validIds.contains(id));
        droppedStale = _done.length != before;
        _restoredNeedsConfirm = _done.isNotEmpty || _na.isNotEmpty;
      });
      if (droppedStale) _persist();
    } catch (_) {
      // Best-effort hydrate — leave the state in its default empty form
      // if SharedPreferences is unavailable / corrupted.
    }
  }

  Future<void> _persist() async {
    if (!widget.session.isCurrent) return;
    try {
      final prefs = await OwnedPrefs.instance(widget.session.captureOwner);
      await prefs.setStringList('$_kDoneKeyPrefix$_todayKey', _done.toList());
      await prefs.setStringList('$_kNaKeyPrefix$_todayKey', _na.toList());
      await prefs.setString('$_kProcessKeyPrefix$_todayKey', _process.id);
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
  List<_Check> get _universal => [
        for (final c in _checks)
          if (_applies(c.scope, _process, _material)) c,
      ];

  List<_Check> get _all {
    final list = <_Check>[..._universal];
    if (_material != null) {
      final extras = _extrasFor(_material!.pNo);
      if (extras != null) list.addAll(extras);
    }
    return list;
  }

  /// Number of ticked items that are actually on the current list. Counting
  /// `_done.length` directly would let a stale ID stand in for an unchecked
  /// item and show "all set" too early.
  int _doneCountIn(List<_Check> list) =>
      list.where((c) => _done.contains(c.id) && !_na.contains(c.id)).length;

  int _naCountIn(List<_Check> list) =>
      list.where((c) => _na.contains(c.id)).length;

  /// Wszystkie punkty listy sprawdzone albo „nie dotyczy”.
  bool _completeIn(List<_Check> list) =>
      list.isNotEmpty &&
      list.every((c) => _done.contains(c.id) || _na.contains(c.id));

  void _toggleNa(_Check check) {
    if (!widget.session.isCurrent) return;
    setState(() {
      if (_na.remove(check.id)) return;
      _na.add(check.id);
      _done.remove(check.id);
    });
    _persist();
  }

  void _setProcess(WeldingProcessKind p) {
    if (!widget.session.isCurrent) return;
    setState(() {
      _process = p;
      final validIds = _all.map((c) => c.id).toSet();
      _done.removeWhere((id) => !validIds.contains(id));
      _na.removeWhere((id) => !validIds.contains(id));
    });
    _persist();
  }

  void _toggle(_Check check) {
    if (!widget.session.isCurrent) return;
    setState(() {
      if (_done.contains(check.id)) {
        _done.remove(check.id);
      } else {
        _done.add(check.id);
        _na.remove(check.id);
        Haptic.tap();
      }
    });
    final list = _all;
    if (!_restoredNeedsConfirm && _completeIn(list)) {
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
    if (!widget.session.isCurrent) return;
    final tickedCount = _done.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => LocalRecordScope(
        restartOnAccountChange: false,
        originSession: widget.session,
        builder: (_, __) => AlertDialog(
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
      ),
    );
    if (ok != true || !mounted || !widget.session.isCurrent) return;
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
    if (!widget.session.isCurrent) return;
    final snapshot = Set<String>.from(_done);
    final naSnapshot = Set<String>.from(_na);
    final wasUnconfirmed = _restoredNeedsConfirm;
    setState(() {
      _done.clear();
      _na.clear();
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
            if (!mounted || !widget.session.isCurrent) return;
            setState(() {
              _done
                ..clear()
                ..addAll(snapshot);
              _na
                ..clear()
                ..addAll(naSnapshot);
              _restoredNeedsConfirm = wasUnconfirmed;
            });
            _persist();
          },
        ),
      ));
  }

  void _confirmSameWeld() {
    if (!widget.session.isCurrent) return;
    setState(() => _restoredNeedsConfirm = false);
    if (_completeIn(_all)) Haptic.saved();
  }

  /// Zapis wykonanej checklisty do spoiny w dzienniku — wpis historii
  /// `CHECKLIST` z odczytem O₂ i podgrzania (v25).
  Future<void> _saveToWeld() async {
    if (!widget.session.isCurrent) return;
    final list = _all;
    final en = AppLanguageController.isEnglish;
    final done = _doneCountIn(list);
    final na = [
      for (final c in list)
        if (_na.contains(c.id)) en ? c.en : c.pl,
    ];
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kCard,
      builder: (_) => LocalRecordScope(
        restartOnAccountChange: false,
        originSession: widget.session,
        builder: (_, __) => _SaveToWeldSheet(
          session: widget.session,
          summary: [
          en
              ? 'Pre-weld checklist: $done/${list.length - na.length} checked'
              : 'Checklista przed spawaniem: $done/${list.length - na.length} '
                  'sprawdzone',
          '${en ? 'process' : 'proces'} '
              '${en ? _process.labelEn : _process.labelPl}',
          if (_material != null)
            '${en ? 'material' : 'materiał'} ${_material!.key}',
          if (na.isNotEmpty)
            '${en ? 'n/a' : 'n/d'}: ${na.join('; ')}',
          ].join(' · '),
        ),
      ),
    );
    if (result == null || !mounted || !widget.session.isCurrent) return;
    final (weldId, text) = result;
    try {
      await WeldJournalDao(owner: widget.session.captureOwner).addChecklist(weldId, text,
          by: WelderIdentityService.instance.current?.stamp ?? '');
    } catch (e) {
      debugPrint('[checklist] save to weld failed: $e');
      if (!mounted || !widget.session.isCurrent) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr(
            pl: 'Nie udało się zapisać w dzienniku.',
            en: 'Could not save to the journal.')),
      ));
      return;
    }
    if (!mounted || !widget.session.isCurrent) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr(
          pl: 'Checklista zapisana w historii spoiny.',
          en: 'Checklist saved in the weld history.')),
    ));
  }

  void _setMaterial(MaterialSpec? m) {
    if (!widget.session.isCurrent) return;
    setState(() {
      _material = m;
      // P0-12: with stable IDs we drop ticks that no longer have a
      // matching check in the new list (e.g. P-No 10 extras gone after
      // switching to P-No 8). Indices used to silently re-bind to
      // whatever check now lives at that index — that's the false-affirm
      // bug the audit flagged.
      final validIds = _all.map((c) => c.id).toSet();
      _done.removeWhere((id) => !validIds.contains(id));
      _na.removeWhere((id) => !validIds.contains(id));
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final isPl = context.language == AppLanguage.pl;
    final list = _all;
    final universalCount = _universal.length;
    final doneCount = _doneCountIn(list);
    final naCount = _naCountIn(list);
    final complete = _completeIn(list);
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$doneCount/${list.length - naCount}',
                        style: TextStyle(
                            color: all ? _kGreen : _kOrange,
                            fontSize: 16,
                            fontWeight: FontWeight.w900)),
                    if (naCount > 0)
                      Text(
                          context.tr(
                              pl: 'n/d: $naCount', en: 'n/a: $naCount'),
                          style: const TextStyle(
                              color: _kSec, fontSize: 11)),
                  ],
                ),
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
                child: OutlinedButton.icon(
                  key: const ValueKey('checklist-save-to-weld'),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48)),
                  icon: const Icon(Icons.assignment_turned_in_outlined),
                  label: Text(context.tr(
                      pl: 'Zapisz w dzienniku spoiny…',
                      en: 'Save to the weld journal…')),
                  onPressed: _saveToWeld,
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
          // Process picker (v25) — the universal list follows the process.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final p in WeldingProcessKind.values) ...[
                    ChoiceChip(
                      key: ValueKey('checklist-process-${p.id}'),
                      label: Text(isPl ? p.labelPl : p.labelEn,
                          style: const TextStyle(fontSize: 13)),
                      selected: _process == p,
                      onSelected: (_) => _setProcess(p),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
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
                final na = _na.contains(c.id);
                final isExtra = i >= universalCount;
                // Group divider before the first material-specific extra so the
                // jump from universal → grade-specific is visible at a glance.
                final showDivider = isExtra && i == universalCount;
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
                          na
                              ? Icons.indeterminate_check_box_outlined
                              : done
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
                                  decoration: done || na
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // „Nie dotyczy” — osobno od „sprawdzone”.
                        SizedBox(
                          height: 40,
                          child: TextButton(
                            key: ValueKey('checklist-na-${c.id}'),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 40),
                              foregroundColor: na ? _kOrange : _kSec,
                            ),
                            onPressed: () => _toggleNa(c),
                            child: Text(context.tr(pl: 'n/d', en: 'n/a')),
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

/// Wybór spoiny z dziennika i odczyty O₂ / podgrzania do wpisu CHECKLIST.
class _SaveToWeldSheet extends StatefulWidget {
  final String summary;
  final LocalRecordSession session;
  const _SaveToWeldSheet({required this.summary, required this.session});

  @override
  State<_SaveToWeldSheet> createState() => _SaveToWeldSheetState();
}

class _SaveToWeldSheetState extends State<_SaveToWeldSheet> {
  final _o2 = TextEditingController();
  final _preheat = TextEditingController();
  late final Future<List<WeldEntry>> _welds =
      WeldJournalDao(owner: widget.session.captureOwner).listAll().then(
      (all) => all.where((e) => !e.isDeleted).toList()
        ..sort((a, b) => b.date.compareTo(a.date)));
  String? _picked;

  @override
  void dispose() {
    _o2.dispose();
    _preheat.dispose();
    super.dispose();
  }

  void _save() {
    if (!widget.session.isCurrent) return;
    final id = _picked;
    if (id == null) return;
    final en = AppLanguageController.isEnglish;
    final o2 = parseO2Ppm(_o2.text);
    final preheat = parseDecimal(_preheat.text);
    final text = [
      widget.summary,
      if (o2 != null) 'O₂ ${formatO2Ppm(o2)} ppm',
      if (preheat != null)
        '${en ? 'preheat' : 'podgrzanie'} ${_preheat.text.trim()} °C',
    ].join(' · ');
    Navigator.pop(context, (id, text));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr(
                pl: 'Zapisz checklistę do spoiny',
                en: 'Save the checklist to a weld'),
            style: const TextStyle(
                color: _kOrange, fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<WeldEntry>>(
            future: _welds,
            builder: (_, snap) {
              if (!snap.hasData) {
                return snap.hasError
                    ? Text(context.tr(
                        pl: 'Nie udało się wczytać dziennika.',
                        en: 'Failed to load the journal.'))
                    : const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator()),
                      );
              }
              final welds = snap.data!;
              if (welds.isEmpty) {
                return Text(context.tr(
                    pl: 'Dziennik jest pusty — najpierw dodaj spoinę.',
                    en: 'The journal is empty — add a weld first.'));
              }
              return DropdownButtonFormField<String>(
                key: const ValueKey('checklist-weld-pick'),
                initialValue: _picked,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: context.tr(pl: 'Spoina', en: 'Weld')),
                items: [
                  for (final w in welds.take(200))
                    DropdownMenuItem(
                      value: w.id,
                      child: Text(
                        [w.weldNo, w.projectName, w.date]
                            .where((s) => s.trim().isNotEmpty)
                            .join(' · '),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _picked = v),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _o2,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                decoration: InputDecoration(
                    labelText: context.tr(
                        pl: 'O₂ zmierzone (ppm)', en: 'Measured O₂ (ppm)')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _preheat,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                decoration: InputDecoration(
                    labelText: context.tr(
                        pl: 'Podgrzanie (°C)', en: 'Preheat (°C)')),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _picked == null ? null : _save,
            child: Text(context.tr(pl: 'Zapisz', en: 'Save')),
          ),
        ],
      ),
    );
  }
}
