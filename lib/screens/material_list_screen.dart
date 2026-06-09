import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/component_library_dao.dart';
import '../database/segment_dao.dart';
import '../i18n/app_language.dart';
import '../models/material_item.dart';
import '../services/material_list_builder.dart';
import '../utils/clipboard_helper.dart';
import '../utils/haptic.dart';
import '../widgets/help_button.dart';

// P1-35: category-coded chip colors promoted to top-level const literals so
// the per-row build doesn't allocate a new Color each frame. Muted alphas keep
// the chip readable on the dark BOM background but still distinguishable
// through gloves + sunlight on the shop floor.
const Color _kPipeChipBg = Color(0x332D7BD7); // blue tint
const Color _kPipeChipFg = Color(0xFF7FB1FF);
const Color _kElbowChipBg = Color(0x33E08A2A); // orange tint
const Color _kElbowChipFg = Color(0xFFFFB066);
const Color _kTeeChipBg = Color(0x3328A050); // green tint
const Color _kTeeChipFg = Color(0xFF6FD592);
const Color _kValveChipBg = Color(0x33C94D4D); // red tint
const Color _kValveChipFg = Color(0xFFFF8B8B);
const Color _kDefaultChipBg = Color(0x33555F7A);
const Color _kDefaultChipFg = Color(0xFFB4BCD4);

// P1-35: tabular figures on every number in the BOM so "1.500" vs "12.345"
// columns align — dot/comma confusion is an order-of-magnitude error in the
// fabrication shop. Hoisted to const so itemBuilder doesn't rebuild the style.
const TextStyle _kTrailingStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w700,
  fontFeatures: [FontFeature.tabularFigures()],
);
const TextStyle _kMetaStyle = TextStyle(
  fontSize: 12,
  color: Colors.black54,
  fontFeatures: [FontFeature.tabularFigures()],
);

class MaterialListScreen extends StatefulWidget {
  final String projectId;
  const MaterialListScreen({super.key, required this.projectId});

  @override
  State<MaterialListScreen> createState() => _MaterialListScreenState();
}

class _MaterialListScreenState extends State<MaterialListScreen> {
  // Deep-link safety: BOM is reached via Navigator.push with projectId in the
  // constructor. If the OS kills the app while the welder is on this screen
  // (low memory, switching to camera for cert photos) and they reopen via a
  // future deep link / shortcut that lost the id, we still want them to land
  // back on the last BOM rather than an empty screen on the shop floor.
  static const String _kLastBomProjectIdPref = 'material_list.last_project_id';

  late final MaterialListBuilder _builder;
  bool _loading = true;
  // P1-10: when true the empty state is shown because we have no project id
  // (deep-link / restored route without args, no last-known pid in prefs) —
  // NOT because the project has zero segments. The empty-state UI branches on
  // this so the welder sees the actionable message instead of the "add
  // segments first" hint that would be a dead-end here.
  bool _missingPid = false;
  List<MaterialItem> _items = [];
  // P2-08: track whether the currently-rendered list came from a previous
  // (possibly stale) load and we failed to refresh. Tracked so the load
  // path can keep the last-known list on screen rather than blanking it
  // while we surface the "showing saved data — Ponów" SnackBar.
  // ignore: unused_field
  bool _staleCache = false;

  @override
  void initState() {
    super.initState();
    _builder = MaterialListBuilder(SegmentDao(), ComponentLibraryDao());
    _load();
  }

  /// Loads (or reloads) the BOM. When [isRefresh] is true the previous list
  /// is kept rendered while we work (P2-08 — pull-to-refresh shouldn't blank
  /// the shop-floor BOM the welder is reading from), and on success we fire a
  /// short "Zaktualizowano BOM (N pozycji)" SnackBar. On failure we keep the
  /// stale list, set [_staleCache] and surface the "showing saved data" toast.
  Future<void> _load({bool isRefresh = false}) async {
    if (!isRefresh) {
      setState(() => _loading = true);
    }
    try {
      var pid = widget.projectId;
      // Recover last-known BOM project if caller handed us an empty id (e.g.
      // route restored from OS state without args). Real navigation always
      // passes a non-empty id, so this branch is a safety net only.
      if (pid.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        pid = prefs.getString(_kLastBomProjectIdPref) ?? '';
      }
      // Track whether we tried to load with an empty pid so the empty-state UI
      // can distinguish "missing project id" from "no segments yet" (P1-10).
      _missingPid = pid.isEmpty;
      final items = pid.isEmpty
          ? <MaterialItem>[]
          : await _builder.buildForProject(pid);
      if (!mounted) return;
      // Persist on every successful, non-empty load so the next cold start has
      // a known-good fallback. Done after the build so we never persist a junk id.
      if (pid.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        await prefs.setString(_kLastBomProjectIdPref, pid);
        if (!mounted) return;
      }
      setState(() {
        _items = items;
        _loading = false;
        _staleCache = false;
      });
      // P2-08: on refresh confirm with a short toast — without it the welder
      // can't tell whether a pull-to-refresh actually re-ran the builder
      // (silent success on identical data == "is this thing broken?").
      if (isRefresh && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(context.tr(
                pl: 'Zaktualizowano BOM (${items.length} pozycji)',
                en: 'BOM refreshed (${items.length} items)',
              )),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } catch (e, st) {
      debugPrint('material_list _load failed: $e\n$st');
      if (!mounted) return;
      if (isRefresh) {
        // P2-08: keep the previously-rendered list visible and flag it as
        // stale. Welder still sees the last-known BOM (better than a blank
        // page mid-job) but the SnackBar tells them the refresh failed.
        setState(() {
          _loading = false;
          _staleCache = true;
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(context.tr(
                pl: 'Nie udało się odświeżyć — pokazuję zapisane dane.',
                en: 'Refresh failed — showing saved data.',
              )),
              duration: const Duration(seconds: 7),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: context.tr(pl: 'Ponów', en: 'Retry'),
                onPressed: () => _load(isRefresh: true),
              ),
            ),
          );
      } else {
        setState(() {
          _loading = false;
          _items = [];
          _staleCache = false;
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(context.tr(
                pl: 'Nie udało się wczytać listy materiałowej.',
                en: 'Failed to load material list.',
              )),
              duration: const Duration(seconds: 7),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: context.tr(pl: 'Ponów', en: 'Retry'),
                onPressed: _load,
              ),
            ),
          );
      }
    }
  }

  String _fmtLen(double mm) {
    // Guard against NaN/Infinity propagating from upstream aggregations —
    // on the shop floor "NaN m" is unreadable through gloves and noise.
    if (!mm.isFinite) return '— m';
    final m = mm / 1000.0;
    return '${m.toStringAsFixed(3)} m';
  }

  /// P1-35: dual-units helper. 1 in = 25.4 mm — the imperial figure is what
  /// a fitter actually reads off a tape measure on a US-spec spool, so we
  /// always surface it as a secondary value next to the metric.
  String _fmtLenDual(double mm) {
    if (!mm.isFinite) return '— m';
    final m = mm / 1000.0;
    final inches = mm / 25.4;
    // For lengths under 10 m show metres with 3 decimals + inches with 1.
    // For very long lengths the inches column would dominate the trailing
    // width — keep the same format anyway, tabular figures handle alignment.
    return '${m.toStringAsFixed(3)} m / ${inches.toStringAsFixed(1)} in';
  }

  @override
  Widget build(BuildContext context) {
    // P1-35: hoist the localised category label for PIPE so it isn't computed
    // per row per build. Other category codes (ELB90, TEE, etc.) are shop-
    // floor standard codes and stay as-is across PL/EN.
    final pipeLabel = context.tr(pl: 'RURA', en: 'PIPE');
    final szt = context.tr(pl: 'szt.', en: 'pcs');
    final sztSingularEn = context.tr(pl: 'szt.', en: 'pc');

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Lista materiałowa (BOM)', en: 'Material list (BOM)')),
        actions: [HelpButton(help: kHelpMaterialList)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _missingPid
                              ? Icons.folder_off_outlined
                              : Icons.inventory_2_outlined,
                          size: 56,
                          color: Colors.black38,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _missingPid
                              ? context.tr(
                                  pl: 'Brak projektu — otwórz BOM z poziomu konkretnego projektu.',
                                  en: 'No project selected — open BOM from a specific project.',
                                )
                              : context.tr(
                                  pl: 'Brak danych (dodaj segmenty).',
                                  en: 'No data yet. Add segments first.',
                                ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        // P1-10: "Wyczyść filtr" semantic — when we landed here because
                        // the stored last-known pid is stale (project was deleted) the
                        // welder needs a way to wipe that pref and back out. The Retry
                        // re-runs _load after clearing so they immediately get the
                        // "no project" branch and can pick a fresh one from the menu.
                        if (_missingPid)
                          TextButton.icon(
                            onPressed: () async {
                              final prefs = await SharedPreferences.getInstance();
                              if (!mounted) return;
                              await prefs.remove(_kLastBomProjectIdPref);
                              if (!mounted) return;
                              await _load();
                            },
                            icon: const Icon(Icons.refresh, size: 18),
                            label: Text(context.tr(
                              pl: 'Wyczyść filtr',
                              en: 'Clear filter',
                            )),
                          ),
                        const SizedBox(height: 16),
                        // First-time coaching: BOM is auto-built from segments, but a
                        // brand-new user lands here from the project menu without ever
                        // seeing the ISO notebook — show them where pipes/elbows come from.
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.lightbulb_outline, size: 14, color: Colors.amber),
                                  const SizedBox(width: 6),
                                  Text(
                                    context.tr(pl: 'Spróbuj tego', en: 'Try this'),
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                context.tr(
                                  pl: 'Otwórz ISO/Notatnik w projekcie i dodaj kilka rur (np. DN50, 6 m) oraz kolan. Wróć tu — lista materiałowa zbuduje się sama.',
                                  en: 'Open ISO/Notebook in this project and add a few pipes (e.g. DN50, 6 m) and elbows. Come back — the BOM builds itself.',
                                ),
                                style: const TextStyle(fontSize: 12, height: 1.3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              // P2-08: wrap the list in a RefreshIndicator so a gloved pull-down
              // gesture re-runs the builder. The empty-state column above is NOT
              // wrapped — pulling on empty would be confusing and the "Wyczyść
              // filtr" / "Try this" CTAs are the explicit recovery paths.
              : RefreshIndicator(
                  onRefresh: () => _load(isRefresh: true),
                  child: ListView.separated(
                    // Always-scrollable so the RefreshIndicator works even when
                    // the list is short enough to not overflow the viewport.
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 0),
                    itemBuilder: (context, i) {
                      final it = _items[i];
                      final qty = it.quantity ?? 0;
                      // EN singular: "1 pc" not "1 pcs"; PL "szt." is invariant.
                      final unit = qty == 1 ? sztSingularEn : szt;
                      // PIPE is the most common row — localise so PL welders see "RURA".
                      final isPipe = it.category == 'PIPE';
                      final catLabel = isPipe ? pipeLabel : it.category;
                      // Dual-unit trailing (P1-35): metric + imperial side-by-
                      // side for PIPE rows; piece-count for everything else.
                      final trailingText = isPipe
                          ? _fmtLen(it.totalLengthMm ?? 0)
                          : '$qty $unit';
                      final trailingDual = isPipe
                          ? _fmtLenDual(it.totalLengthMm ?? 0)
                          : null;
                      // P3-10: long-press copies "CAT - desc - trailing" so welder
                      // can paste a single BOM line straight into chat/SMS to the
                      // storeroom without re-typing through gloves.
                      final copyPayload =
                          '$catLabel - ${it.description} - $trailingText';
                      return _BomRow(
                        catLabel: catLabel,
                        category: it.category,
                        description: it.description,
                        trailingText: trailingText,
                        trailingDual: trailingDual,
                        qtyText: isPipe ? null : '$qty $unit',
                        copyPayload: copyPayload,
                      );
                    },
                  ),
                ),
    );
  }
}

/// P1-35: extracted const-friendly row so the itemBuilder doesn't rebuild the
/// chip + tabular-figure styles per scroll frame. Two-line layout:
///   row 1: [CAT chip]  description (2 lines, ellipsis)
///   row 2: qty · trailing · dual-unit note
/// Tabular figures on every numeric column so dot-vs-comma columns align —
/// the historical 12.345/1,500 confusion is an order-of-magnitude scrap risk.
class _BomRow extends StatelessWidget {
  final String catLabel;
  final String category;
  final String description;
  final String trailingText;
  final String? trailingDual;
  final String? qtyText;
  final String copyPayload;

  const _BomRow({
    required this.catLabel,
    required this.category,
    required this.description,
    required this.trailingText,
    required this.trailingDual,
    required this.qtyText,
    required this.copyPayload,
  });

  // Category → (bg, fg) chip color. PIPE blue / ELB orange / TEE green /
  // valve red / everything else neutral grey. Kept as a static fn rather
  // than a Map so the call-site stays const-friendly with no allocation.
  static (Color, Color) _chipColors(String cat) {
    if (cat == 'PIPE') return (_kPipeChipBg, _kPipeChipFg);
    if (cat.startsWith('ELB')) return (_kElbowChipBg, _kElbowChipFg);
    if (cat == 'TEE') return (_kTeeChipBg, _kTeeChipFg);
    if (cat.contains('VALVE') || cat.contains('VLV')) {
      return (_kValveChipBg, _kValveChipFg);
    }
    return (_kDefaultChipBg, _kDefaultChipFg);
  }

  @override
  Widget build(BuildContext context) {
    final (chipBg, chipFg) = _chipColors(category);

    // P1-09: Material+InkWell row with 48dp min-height tap target and haptic
    // on tap so gloved users get a confirmation that the tap landed even when
    // sunlight washes out the ripple.
    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Haptic.tap();
          },
          onLongPress: () => copyToClipboard(context, copyPayload),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Fixed-width category chip — keeps descriptions left-aligned
                  // across rows even when the code length differs (PIPE vs
                  // ELB90 vs TEE) so the welder's eye tracks a clean column.
                  Container(
                    width: 64,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: chipFg.withValues(alpha: 0.55)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      catLabel,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: chipFg,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title + meta column. Two lines: description on top
                  // (truncates at 2 lines), then a meta strip with qty +
                  // dual-unit note in muted tabular-figure type.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        if (qtyText != null || trailingDual != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            // Meta line: piece-count for non-pipe rows;
                            // dual-unit (mm / in) for pipes. Both render in
                            // tabular figures so columns align scroll-to-scroll.
                            qtyText ?? trailingDual ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _kMetaStyle,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Trailing — primary number, right-aligned, fixed width so
                  // PIPE "12.345 m" and "1.500 m" line up on the decimal.
                  SizedBox(
                    width: 92,
                    child: Text(
                      trailingText,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: _kTrailingStyle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
