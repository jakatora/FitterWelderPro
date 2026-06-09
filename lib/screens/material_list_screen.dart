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

  @override
  void initState() {
    super.initState();
    _builder = MaterialListBuilder(SegmentDao(), ComponentLibraryDao());
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
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
      });
    } catch (e, st) {
      debugPrint('material_list _load failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = [];
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

  String _fmtLen(double mm) {
    // Guard against NaN/Infinity propagating from upstream aggregations —
    // on the shop floor "NaN m" is unreadable through gloves and noise.
    if (!mm.isFinite) return '— m';
    final m = mm / 1000.0;
    return '${m.toStringAsFixed(3)} m';
  }

  @override
  Widget build(BuildContext context) {
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
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, i) {
                    final it = _items[i];
                    final qty = it.quantity ?? 0;
                    // EN singular: "1 pc" not "1 pcs"; PL "szt." is invariant.
                    final enUnit = qty == 1 ? 'pc' : 'pcs';
                    // PIPE is the most common row — localise so PL welders see "RURA".
                    // Other category codes (ELB90, TEE, etc.) are shop-floor standard codes.
                    final catLabel = it.category == 'PIPE'
                        ? context.tr(pl: 'RURA', en: 'PIPE')
                        : it.category;
                    final trailingText = it.category == 'PIPE'
                        ? _fmtLen(it.totalLengthMm ?? 0)
                        : context.tr(pl: '$qty szt.', en: '$qty $enUnit');
                    // P3-10: long-press copies "CAT - desc - trailing" so welder
                    // can paste a single BOM line straight into chat/SMS to the
                    // storeroom without re-typing through gloves.
                    final copyPayload =
                        '$catLabel - ${it.description} - $trailingText';
                    // P1-09: Material+InkWell row with 48dp min-height tap target
                    // and haptic on tap so gloved users get a confirmation that
                    // the tap landed even when sunlight washes out the ripple.
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Haptic.tap();
                        },
                        onLongPress: () =>
                            copyToClipboard(context, copyPayload),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                      '$catLabel  •  ${it.description}'),
                                ),
                                const SizedBox(width: 12),
                                Text(trailingText),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
