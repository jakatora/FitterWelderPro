import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/heat_tint.dart';
import '../data/tungsten.dart';
import '../database/weld_param_dao.dart';
import '../services/weld_timer_service.dart';
import 'welder_tools_screen.dart' show startPurgeCountdown;
import '../database/approved_weld_param_dao.dart';
import '../domain/welder_pipes/purge_estimate.dart';
import '../domain/welder_pipes/tig_start_params.dart';
import '../i18n/app_language.dart';
import '../models/weld_param.dart';
import '../models/approved_weld_param.dart';
import '../widgets/help_button.dart';
import '../widgets/number_field.dart';

enum WeldingMethod { tigWire, tigNoWire }

/// Etykieta metody z kolumny `weld_params.method`. Ekran zapisuje TIG
/// (`TIG_WIRE` / `TIG_AUTOGEN`), asystent także `MAG`, `MMA` i `OTHER`;
/// nieznana wartość jest pokazywana tak, jak leży w bazie.
String weldParamMethodLabel(String method, {required bool en}) =>
    switch (method) {
      'TIG_WIRE' => en ? 'TIG with filler' : 'TIG z drutem',
      'TIG_AUTOGEN' => en ? 'TIG without filler' : 'TIG bez drutu',
      'MAG' => 'MIG/MAG',
      'MMA' => en ? 'Stick / MMA' : 'MMA (elektroda otulona)',
      'OTHER' => en ? 'Other process' : 'Inny proces',
      _ => method,
    };

/// Liczba z „Moich parametrów" albo „—", gdy jej nie podano. Kolumny są
/// NOT NULL, więc brak (np. średnica niepodyktowana asystentowi, gaz przy
/// MMA) leży w bazie jako 0 — „Ø0.0" wyglądało jak zmierzona wartość.
String weldParamValue(double v, int digits, {String unit = ''}) =>
    v > 0 ? '${v.toStringAsFixed(digits)}$unit' : '—';

/// Tekst pola edycji: pusty dla „nie podano" (0).
String _editText(double v, int digits) => v > 0 ? v.toStringAsFixed(digits) : '';

class WelderPipesScreen extends StatefulWidget {
  const WelderPipesScreen({super.key});

  @override
  State<WelderPipesScreen> createState() => _WelderPipesScreenState();
}

class _WelderPipesScreenState extends State<WelderPipesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;

  WeldingMethod _method = WeldingMethod.tigWire;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(_tr('Rury - Welder', 'Pipes - Welder')),
          actions: [HelpButton(help: kHelpWelderPipes)],
          bottom: TabBar(
            controller: _tab,
            tabs: [
              const Tab(text: 'AMP'),
              Tab(text: _tr('Gazy', 'Gases')),
              // Dane startowe dostarczone z aplikacją — nie zestawy WPS
              // zakładu (te są w Bibliotece WPS).
              Tab(text: _tr('Startowe', 'Starter')),
              Tab(text: _tr('Moje parametry', 'My parameters')),
            ],
          ),
        ),
      body: Column(
          children: [
            if (_tab.index != 1)
              Padding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, MediaQuery.viewPaddingOf(context).bottom),
                child: Row(
                  children: [
                    Text(_tr('Metoda:', 'Method:')),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<WeldingMethod>(
                        initialValue: _method,
                        items: [
                          DropdownMenuItem(value: WeldingMethod.tigWire, child: Text(_tr('TIG z drutem', 'TIG with filler'))),
                          DropdownMenuItem(value: WeldingMethod.tigNoWire, child: Text(_tr('TIG bez drutu', 'TIG without filler'))),
                        ],
                        onChanged: (v) => setState(() => _method = v ?? WeldingMethod.tigWire),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _AmpTab(methodGetter: () => _method),
                  _GasTab(methodGetter: () => _method),
                  _ApprovedAmpTab(methodGetter: () => _method),
                  _MyParamsTab(methodGetter: () => _method),
                ],
              ),
            ),
          ],
        ),
    );
  }
}

class _MyParamsTab extends StatefulWidget {
  final WeldingMethod Function() methodGetter;
  const _MyParamsTab({required this.methodGetter});

  @override
  State<_MyParamsTab> createState() => _MyParamsTabState();
}

class _MyParamsTabState extends State<_MyParamsTab> {
  final _dao = WeldParamDao();
  final _uuid = const Uuid();
  late Future<List<WeldParam>> _future;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _future = _dao.listAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await _showAddDialog(context);
          if (created == true) {
            setState(() => _refresh());
          }
        },
        icon: const Icon(Icons.add),
        label: Text(_tr('Dodaj', 'Add')),
      ),
      body: FutureBuilder<List<WeldParam>>(
        future: _future,
        builder: (context, snap) {
          final items = snap.data ?? const <WeldParam>[];

          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          // Error UI: DB read can fail (locked file, schema migration, etc.).
          // Without this branch the welder would just see "No saved entries"
          // and lose their data with no recovery path on a noisy shop floor.
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 12),
                    Text(
                      _tr('Nie udało się wczytać zapisanych parametrów.', 'Could not load saved parameters.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => setState(() => _refresh()),
                      icon: const Icon(Icons.refresh),
                      label: Text(_tr('Spróbuj ponownie', 'Retry')),
                    ),
                  ],
                ),
              ),
            );
          }

          if (items.isEmpty) {
            return Center(
              child: Text(_tr('Brak zapisanych pozycji. Dodaj swoje parametry (plus).', 'No saved entries. Add your own parameters (plus button).')),
            );
          }

          return ListView.separated(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final p = items[i];
              return Card(
                child: ListTile(
                  title: Text(
                    '${_methodLabelDb(p.method)} | ${p.baseMaterial} | Ø${weldParamValue(p.diameterMm, 1)} × t${weldParamValue(p.wallThicknessMm, 2)}',
                  ),
                  subtitle: Text(
                    '${(p.welderModel != null && p.welderModel!.trim().isNotEmpty) ? "${_tr('Spawarka', 'Welder')}: ${p.welderModel}\n" : ""}'
                    '${_tr('Elektroda', 'Electrode')}: ${weldParamValue(p.electrodeMm, 1)}  |  ${_tr('Palnik', 'Torch')}: ${weldParamValue(p.torchGasLpm, 1, unit: ' L/min')}  |  Purge: ${weldParamValue(p.purgeLpm, 1, unit: ' L/min')}\n'
                    '${_tr('Dysza', 'Nozzle')}: ${_nozzleText(p)}  |  ${_tr('Ampery', 'Amps')}: ${weldParamValue(p.amps, 0, unit: ' A')}'
                    '${(p.note != null && p.note!.trim().isNotEmpty) ? "\n${_tr('Notatka', 'Note')}: ${p.note}" : ""}',
                  ),
                  isThreeLine: true,
                  onTap: () async {
                    final changed = await _showViewEditDialog(context, p);
                    if (changed == true) {
                      setState(() => _refresh());
                    }
                  },
                  trailing: IconButton(
                    tooltip: _tr('Usuń', 'Delete'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dctx) => AlertDialog(
                          title: Text(_tr('Usunąć zapisane parametry?', 'Delete saved parameters?')),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dctx, false),
                              child: Text(_tr('Anuluj', 'Cancel')),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(dctx, true),
                              child: Text(_tr('Usuń', 'Delete')),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                      await _dao.deleteById(p.id);
                      setState(() => _refresh());
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _nozzleText(WeldParam p) {
    final t = (p.nozzleType ?? '').trim();
    final s = (p.nozzleSize ?? '').trim();
    if (t.isEmpty && s.isEmpty) return '-';
    if (t.isEmpty) return s;
    if (s.isEmpty) return t;
    return '$t $s';
  }

  String _methodLabelDb(String method) =>
      weldParamMethodLabel(method, en: AppLanguageController.isEnglish);

  String _methodToDb(WeldingMethod m) {
    switch (m) {
      case WeldingMethod.tigWire:
        return 'TIG_WIRE';
      case WeldingMethod.tigNoWire:
        return 'TIG_AUTOGEN';
    }
  }

  Future<bool?> _showAddDialog(BuildContext context) async {
    final formKey = GlobalKey<FormState>();

    String baseMaterial = 'SS';
    WeldingMethod method = widget.methodGetter();
    double electrode = 1.6;

    final diameterCtrl = TextEditingController(text: '60.3');
    final wallCtrl = TextEditingController(text: '2.0');
    final welderModelCtrl = TextEditingController(text: '');
    final torchGasCtrl = TextEditingController(text: '8');
    final nozzleTypeCtrl = TextEditingController(text: '');
    final nozzleSizeCtrl = TextEditingController(text: '');
    final purgeCtrl = TextEditingController(text: '2');
    final ampsCtrl = TextEditingController(text: '55');
    final noteCtrl = TextEditingController(text: '');
    final outletHolesCtrl = TextEditingController(text: '0');
    String tempo = 'NORMAL';

    String? reqInt0(String? v) {
      final x = int.tryParse((v ?? '').trim());
      if (x == null || x < 0) return _tr('Wpisz liczbę całkowitą ≥ 0', 'Enter an integer ≥ 0');
      return null;
    }

    String? reqNum(String? v) {
      final x = parseDecimal(v);
      if (x == null || x <= 0) return _tr('Wpisz liczbę > 0', 'Enter a number > 0');
      return null;
    }

    // Gazy opcjonalne — te same reguły co w edycji wpisu.
    String? optNum(String? v) => (v ?? '').trim().isEmpty ? null : reqNum(v);

    // Snapshot of the defaults so an accidental back-gesture only prompts when
    // the welder has actually typed something — gloves on a phone make
    // re-entering the whole form a punishment.
    final initialSnapshot = <String>[
      diameterCtrl.text, wallCtrl.text, welderModelCtrl.text,
      torchGasCtrl.text, nozzleTypeCtrl.text, nozzleSizeCtrl.text,
      purgeCtrl.text, ampsCtrl.text, noteCtrl.text, outletHolesCtrl.text,
    ];
    bool isDirty() {
      final now = <String>[
        diameterCtrl.text, wallCtrl.text, welderModelCtrl.text,
        torchGasCtrl.text, nozzleTypeCtrl.text, nozzleSizeCtrl.text,
        purgeCtrl.text, ampsCtrl.text, noteCtrl.text, outletHolesCtrl.text,
      ];
      for (var i = 0; i < now.length; i++) {
        if (now[i] != initialSnapshot[i]) return true;
      }
      return false;
    }

    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return PopScope(
          canPop: !isDirty(),
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final discard = await showDialog<bool>(
              context: ctx,
              builder: (dctx) => AlertDialog(
                title: Text(_tr('Porzucić zmiany?', 'Discard changes?')),
                content: Text(_tr(
                  'Wpisane parametry zostaną utracone.',
                  'The parameters you entered will be lost.',
                )),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dctx, false),
                    child: Text(_tr('Wróć do edycji', 'Keep editing')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dctx, true),
                    child: Text(_tr('Porzuć', 'Discard')),
                  ),
                ],
              ),
            );
            if (discard == true && ctx.mounted) Navigator.pop(ctx, false);
          },
          child: AlertDialog(
          title: Text(_tr('Moje parametry - dodaj', 'My parameters - add')),
          content: SizedBox(
            width: 520,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: baseMaterial,
                            decoration: InputDecoration(labelText: _tr('Materiał spawany', 'Welded material')),
                            items: [
                              DropdownMenuItem(value: 'SS', child: Text(_tr('SS (nierdzewna)', 'SS (stainless)'))),
                              DropdownMenuItem(value: 'CS', child: Text(_tr('CS (czarna)', 'CS (carbon steel)'))),
                            ],
                            onChanged: (v) => baseMaterial = v ?? 'SS',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<WeldingMethod>(
                            initialValue: method,
                            decoration: InputDecoration(labelText: _tr('Metoda', 'Method')),
                            items: [
                              DropdownMenuItem(value: WeldingMethod.tigWire, child: Text(_tr('TIG z drutem', 'TIG with filler'))),
                              DropdownMenuItem(value: WeldingMethod.tigNoWire, child: Text(_tr('TIG bez drutu', 'TIG without filler'))),
                            ],
                            onChanged: (v) => method = v ?? widget.methodGetter(),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: diameterCtrl,
                            validator: reqNum,
                            keyboardType: numberKeyboard(),
                            inputFormatters: numberInputFormatters(),
                            decoration: InputDecoration(labelText: _tr('Średnica rury OD [mm]', 'Pipe OD [mm]')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: wallCtrl,
                            validator: reqNum,
                            keyboardType: numberKeyboard(),
                            inputFormatters: numberInputFormatters(),
                            decoration: InputDecoration(labelText: _tr('Grubość ścianki t [mm]', 'Wall thickness t [mm]')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<double>(
                      initialValue: electrode,
                      decoration: InputDecoration(labelText: _tr('Rozmiar elektrody [mm]', 'Electrode size [mm]')),
                      items: const [
                        DropdownMenuItem(value: 1.0, child: Text('1.0')),
                        DropdownMenuItem(value: 1.6, child: Text('1.6')),
                        DropdownMenuItem(value: 2.4, child: Text('2.4')),
                        DropdownMenuItem(value: 3.2, child: Text('3.2')),
                        DropdownMenuItem(value: 4.0, child: Text('4.0')),
                      ],
                      onChanged: (v) => electrode = v ?? 1.6,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: torchGasCtrl,
                            validator: optNum,
                            keyboardType: numberKeyboard(),
                            inputFormatters: numberInputFormatters(),
                            decoration: InputDecoration(labelText: _tr('Gaz na palnik [L/min]', 'Torch gas [L/min]')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: purgeCtrl,
                            validator: optNum,
                            keyboardType: numberKeyboard(),
                            inputFormatters: numberInputFormatters(),
                            decoration: InputDecoration(labelText: _tr('Gaz do środka (purge) [L/min]', 'Internal gas (purge) [L/min]')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: welderModelCtrl,
                      decoration: InputDecoration(labelText: _tr('Model spawarki (opcjonalnie)', 'Welder model (optional)')),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: nozzleTypeCtrl,
                            decoration: InputDecoration(labelText: _tr('Rodzaj dyszy (np. standard/gas lens)', 'Nozzle type (e.g. standard/gas lens)')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: nozzleSizeCtrl,
                            decoration: InputDecoration(labelText: _tr('Rozmiar dyszy (np. #8)', 'Nozzle size (e.g. #8)')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: ampsCtrl,
                      validator: reqNum,
                      keyboardType: numberKeyboard(),
                      inputFormatters: numberInputFormatters(),
                      decoration: InputDecoration(labelText: _tr('Ampery [A]', 'Amps [A]')),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: outletHolesCtrl,
                      validator: reqInt0,
                      keyboardType: numberKeyboard(decimal: false),
                      inputFormatters: numberInputFormatters(decimal: false),
                      decoration: InputDecoration(
                        labelText: _tr('Ilość otworów wylotowych', 'Number of outlet holes'),
                        helperText: _tr('Opcjonalnie (np. dla purge)', 'Optional (for example for purge)'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: tempo,
                      items: [
                        DropdownMenuItem(value: 'SLOW', child: Text(_tr('Tempo: wolne', 'Pace: slow'))),
                        DropdownMenuItem(value: 'NORMAL', child: Text(_tr('Tempo: normalne', 'Pace: normal'))),
                        DropdownMenuItem(value: 'FAST', child: Text(_tr('Tempo: szybkie', 'Pace: fast'))),
                      ],
                      onChanged: (v) => tempo = v ?? 'NORMAL',
                      decoration: InputDecoration(labelText: _tr('Tempo spawania', 'Welding pace')),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(labelText: _tr('Notatka (opcjonalnie)', 'Note (optional)')),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_tr('Anuluj', 'Cancel'))),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;

                final now = DateTime.now().millisecondsSinceEpoch;
                final p = WeldParam(
                  id: _uuid.v4(),
                  method: _methodToDb(method),
                  baseMaterial: baseMaterial,
                  welderModel: welderModelCtrl.text.trim().isEmpty ? null : welderModelCtrl.text.trim(),
                  diameterMm: parseDecimal(diameterCtrl.text)!,
                  wallThicknessMm: parseDecimal(wallCtrl.text)!,
                  electrodeMm: electrode,
                  // Puste = nie podano (0), jak w edycji — CS bez formowania
                  // nie wymaga wpisywania „0”.
                  torchGasLpm: parseDecimal(torchGasCtrl.text) ?? 0,
                  nozzleType: nozzleTypeCtrl.text.trim().isEmpty ? null : nozzleTypeCtrl.text.trim(),
                  nozzleSize: nozzleSizeCtrl.text.trim().isEmpty ? null : nozzleSizeCtrl.text.trim(),
                  purgeLpm: parseDecimal(purgeCtrl.text) ?? 0,
                  amps: parseDecimal(ampsCtrl.text)!,
                  outletHoles: int.parse(outletHolesCtrl.text.trim()),
                  tempo: tempo,
                  note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                  createdAt: now,
                  updatedAt: now,
                );

                await _dao.insert(p);
                if (context.mounted) Navigator.pop(ctx, true);
              },
              child: Text(_tr('Zapisz', 'Save')),
            ),
          ],
        ),
        );
      },
    );

  }

  Future<bool?> _showViewEditDialog(BuildContext context, WeldParam existing) async {
    final formKey = GlobalKey<FormState>();

    String baseMaterial = existing.baseMaterial;
    // The stored method, kept as it is: a MAG / MMA / OTHER entry (from the
    // assistant) must not turn into TIG just because it was opened here.
    String methodDb = existing.method;
    double electrode = existing.electrodeMm;
    const tigMethods = ['TIG_WIRE', 'TIG_AUTOGEN'];
    const materials = ['SS', 'CS'];
    const electrodes = [1.0, 1.6, 2.4, 3.2, 4.0];

    final diameterCtrl = TextEditingController(text: _editText(existing.diameterMm, 1));
    final wallCtrl = TextEditingController(text: _editText(existing.wallThicknessMm, 2));
    final welderModelCtrl = TextEditingController(text: existing.welderModel ?? '');
    final torchGasCtrl = TextEditingController(text: _editText(existing.torchGasLpm, 1));
    final nozzleTypeCtrl = TextEditingController(text: existing.nozzleType ?? '');
    final nozzleSizeCtrl = TextEditingController(text: existing.nozzleSize ?? '');
    final purgeCtrl = TextEditingController(text: _editText(existing.purgeLpm, 1));
    final ampsCtrl = TextEditingController(text: _editText(existing.amps, 0));
    final outletHolesCtrl = TextEditingController(text: (existing.outletHoles ?? 0).toString());
    String tempo = existing.tempo ?? 'NORMAL';
    final noteCtrl = TextEditingController(text: existing.note ?? '');

    String? reqInt0(String? v) {
      final x = int.tryParse((v ?? '').trim());
      if (x == null || x < 0) return _tr('Wpisz liczbę całkowitą ≥ 0', 'Enter an integer ≥ 0');
      return null;
    }

    String? reqNum(String? v) {
      final x = parseDecimal(v);
      if (x == null || x <= 0) return _tr('Wpisz liczbę > 0', 'Enter a number > 0');
      return null;
    }

    // Gas flows may be "not given" (e.g. MMA has none): empty = 0 = „—".
    String? optNum(String? v) => (v ?? '').trim().isEmpty ? null : reqNum(v);
    double optValue(String text) =>
        text.trim().isEmpty ? 0 : (parseDecimal(text) ?? 0);

    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(_tr('Moje parametry - podgląd/edycja', 'My parameters - view/edit')),
          content: SizedBox(
            width: 520,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: baseMaterial,
                            decoration: InputDecoration(labelText: _tr('Materiał spawany', 'Welded material')),
                            items: [
                              DropdownMenuItem(value: 'SS', child: Text(_tr('SS (nierdzewna)', 'SS (stainless)'))),
                              DropdownMenuItem(value: 'CS', child: Text(_tr('CS (czarna)', 'CS (carbon steel)'))),
                              // DUPLEX / AL / OTHER from the assistant.
                              if (!materials.contains(existing.baseMaterial))
                                DropdownMenuItem(value: existing.baseMaterial, child: Text(existing.baseMaterial)),
                            ],
                            onChanged: (v) => baseMaterial = v ?? existing.baseMaterial,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: methodDb,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: _tr('Metoda', 'Method')),
                            items: [
                              for (final m in [
                                ...tigMethods,
                                if (!tigMethods.contains(existing.method)) existing.method,
                              ])
                                DropdownMenuItem(
                                  value: m,
                                  child: Text(_methodLabelDb(m), overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (v) => methodDb = v ?? existing.method,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: diameterCtrl,
                            validator: reqNum,
                            keyboardType: numberKeyboard(),
                            inputFormatters: numberInputFormatters(),
                            decoration: InputDecoration(labelText: _tr('Średnica rury OD [mm]', 'Pipe OD [mm]')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: wallCtrl,
                            validator: reqNum,
                            keyboardType: numberKeyboard(),
                            inputFormatters: numberInputFormatters(),
                            decoration: InputDecoration(labelText: _tr('Grubość ścianki t [mm]', 'Wall thickness t [mm]')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<double>(
                      initialValue: electrode,
                      decoration: InputDecoration(labelText: _tr('Rozmiar elektrody [mm]', 'Electrode size [mm]')),
                      items: [
                        // A value outside the list (0 = not given) stays
                        // selectable instead of failing the dropdown.
                        if (!electrodes.contains(existing.electrodeMm))
                          DropdownMenuItem(
                            value: existing.electrodeMm,
                            child: Text(weldParamValue(existing.electrodeMm, 1)),
                          ),
                        for (final e in electrodes)
                          DropdownMenuItem(value: e, child: Text(e.toStringAsFixed(1))),
                      ],
                      onChanged: (v) => electrode = v ?? existing.electrodeMm,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: torchGasCtrl,
                            validator: optNum,
                            keyboardType: numberKeyboard(),
                            inputFormatters: numberInputFormatters(),
                            decoration: InputDecoration(labelText: _tr('Gaz na palnik [L/min]', 'Torch gas [L/min]')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: purgeCtrl,
                            validator: optNum,
                            keyboardType: numberKeyboard(),
                            inputFormatters: numberInputFormatters(),
                            decoration: InputDecoration(labelText: _tr('Gaz do środka (purge) [L/min]', 'Internal gas (purge) [L/min]')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: welderModelCtrl,
                      decoration: InputDecoration(labelText: _tr('Model spawarki (opcjonalnie)', 'Welder model (optional)')),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: nozzleTypeCtrl,
                            decoration: InputDecoration(labelText: _tr('Rodzaj dyszy (np. standard/gas lens)', 'Nozzle type (e.g. standard/gas lens)')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: nozzleSizeCtrl,
                            decoration: InputDecoration(labelText: _tr('Rozmiar dyszy (np. #8)', 'Nozzle size (e.g. #8)')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: ampsCtrl,
                      validator: reqNum,
                      keyboardType: numberKeyboard(),
                      inputFormatters: numberInputFormatters(),
                      decoration: InputDecoration(labelText: _tr('Ampery [A]', 'Amps [A]')),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: outletHolesCtrl,
                      validator: reqInt0,
                      keyboardType: numberKeyboard(decimal: false),
                      inputFormatters: numberInputFormatters(decimal: false),
                      decoration: InputDecoration(
                        labelText: _tr('Ilość otworów wylotowych', 'Number of outlet holes'),
                        helperText: _tr('Opcjonalnie (np. dla purge)', 'Optional (for example for purge)'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: tempo,
                      items: [
                        DropdownMenuItem(value: 'SLOW', child: Text(_tr('Tempo: wolne', 'Pace: slow'))),
                        DropdownMenuItem(value: 'NORMAL', child: Text(_tr('Tempo: normalne', 'Pace: normal'))),
                        DropdownMenuItem(value: 'FAST', child: Text(_tr('Tempo: szybkie', 'Pace: fast'))),
                      ],
                      onChanged: (v) => tempo = v ?? 'NORMAL',
                      decoration: InputDecoration(labelText: _tr('Tempo spawania', 'Welding pace')),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(labelText: _tr('Notatka (opcjonalnie)', 'Note (optional)')),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_tr('Zamknij', 'Close'))),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;

                final now = DateTime.now().millisecondsSinceEpoch;
                final updated = WeldParam(
                  id: existing.id,
                  method: methodDb,
                  baseMaterial: baseMaterial,
                  welderModel: welderModelCtrl.text.trim().isEmpty ? null : welderModelCtrl.text.trim(),
                  diameterMm: parseDecimal(diameterCtrl.text)!,
                  wallThicknessMm: parseDecimal(wallCtrl.text)!,
                  electrodeMm: electrode,
                  torchGasLpm: optValue(torchGasCtrl.text),
                  nozzleType: nozzleTypeCtrl.text.trim().isEmpty ? null : nozzleTypeCtrl.text.trim(),
                  nozzleSize: nozzleSizeCtrl.text.trim().isEmpty ? null : nozzleSizeCtrl.text.trim(),
                  purgeLpm: optValue(purgeCtrl.text),
                  amps: parseDecimal(ampsCtrl.text)!,
                  outletHoles: int.parse(outletHolesCtrl.text.trim()),
                  tempo: tempo,
                  note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                  createdAt: existing.createdAt,
                  updatedAt: now,
                );

                await _dao.update(updated);
                if (context.mounted) Navigator.pop(ctx, true);
              },
              child: Text(_tr('Zapisz zmiany', 'Save changes')),
            ),
          ],
        );
      },
    );
  }
}

class _AmpTab extends StatefulWidget {
  final WeldingMethod Function() methodGetter;
  const _AmpTab({required this.methodGetter});

  @override
  State<_AmpTab> createState() => _AmpTabState();
}

class _AmpTabState extends State<_AmpTab> {
  final _diamCtrl = TextEditingController(text: '60.3');
  final _tCtrl = TextEditingController(text: '2.0');
  String _material = 'SS';

  /// Punkty startowe (lista „Startowe”) — jedyne źródło prądu kalkulatora.
  List<PipeStartPoint>? _points;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() {
    super.initState();
    loadPipeStartPoints().then((p) {
      if (mounted) setState(() => _points = p);
    }).catchError((Object e) {
      debugPrint('[welder_pipes] start points load failed: $e');
      if (mounted) setState(() => _points = const []);
    });
  }

  @override
  void dispose() {
    _diamCtrl.dispose();
    _tCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = parseDecimal(_diamCtrl.text) ?? 0;
    final t = parseDecimal(_tCtrl.text) ?? 0;
    final method = widget.methodGetter();

    // The calculator is for single-pass manual TIG. Above t = 3 mm the joint
    // needs a bevel and multi-pass technique, which lives in its own tools.
    final overThick = t > 3.0;
    final current = _points == null
        ? null
        : pipeStartCurrent(
            points: _points!,
            material: _material,
            method: _methodToDb(method),
            odMm: d,
            wallMm: t,
          );
    final calc = current == null || !current.hasResult
        ? null
        : _AmpCalcResult.from(method: method, startA: current.amps!, t: t);

    return ListView(
      padding: EdgeInsets.fromLTRB(
          12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        Text(_tr('Kalkulator AMP — TIG ręczny, jednoprzejściowy',
            'AMP calculator — manual TIG, single-pass')),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _material,
          decoration: InputDecoration(labelText: _tr('Materiał spawany', 'Welded material')),
          items: [
            DropdownMenuItem(value: 'SS', child: Text(_tr('SS (nierdzewna)', 'SS (stainless)'))),
            DropdownMenuItem(value: 'CS', child: Text(_tr('CS (czarna)', 'CS (carbon steel)'))),
            const DropdownMenuItem(value: 'DUPLEX', child: Text('Duplex')),
            DropdownMenuItem(value: 'AL', child: Text(_tr('Aluminium', 'Aluminum'))),
          ],
          onChanged: (v) => setState(() => _material = v ?? 'SS'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _diamCtrl,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(labelText: _tr('Średnica zewnętrzna rury OD [mm]', 'Pipe OD [mm]')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _tCtrl,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
            labelText: _tr('Grubość ścianki t [mm]', 'Wall thickness t [mm]'),
            helperText: _tr('Maks. 3 mm — powyżej fazowanie + multi-pass',
                'Max. 3 mm — beyond that, bevel + multi-pass'),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),

        if (overThick)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _tr(
                          'Ścianka > 3 mm: ten kalkulator jest dla pojedynczego '
                          'przejścia. Dla grubszej ścianki sfazuj rurę i spawaj '
                          'wielowarstwowo (root + fill + cap). Zobacz: Fitter → Fazowanie.',
                          'Wall > 3 mm: this calculator is for a single pass. '
                          'For thicker walls bevel the pipe and weld multi-pass '
                          '(root + fill + cap). See: Fitter → Bevel.'),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontSize: 13,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (t <= 0 || d <= 0)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                _tr('Wpisz OD rury i grubość ścianki, żeby zobaczyć parametry.',
                    'Enter pipe OD and wall thickness to see the parameters.'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          )
        else if (_points == null)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator()))
        else if (calc == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                _tr(
                    'Brak danych startowych dla $_material, ${_methodLabel(method)}, '
                        'Ø${d.toStringAsFixed(1)} × ${t.toStringAsFixed(2)} mm. Aplikacja '
                        'nie zgaduje prądu poza danymi — ustal go na próbce; wiąże WPS.',
                    'No starting data for $_material, ${_methodLabel(method)}, '
                        'Ø${d.toStringAsFixed(1)} × ${t.toStringAsFixed(2)} mm. The app '
                        'does not guess the current outside the data — set it on a test '
                        'piece; the WPS is binding.'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_tr('Metoda', 'Method')}: ${_methodLabel(method)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('OD: ${d.toStringAsFixed(1)} mm · '
                      't: ${t.toStringAsFixed(2)} mm · '
                      '$_material'),
                  const Divider(height: 22),

                  _ParamLine(
                    label: _tr('Zakres prądu', 'Current range'),
                    value: '${calc.minA.toStringAsFixed(0)}–'
                        '${calc.maxA.toStringAsFixed(0)} A',
                    primary: true,
                  ),
                  _ParamLine(
                    label: _tr('Punkt startowy', 'Starting point'),
                    value: '${calc.centerA.toStringAsFixed(0)} A',
                  ),
                  Text(_currentSourceNote(current!),
                      style: const TextStyle(fontSize: 11)),
                  _ParamLine(
                    label: _tr('Elektroda wolframowa', 'Tungsten electrode'),
                    value: 'Ø ${calc.electrodeMm.toStringAsFixed(1)} mm  '
                        '(WL20 / WC20)',
                  ),
                  if (method == WeldingMethod.tigWire)
                    _ParamLine(
                      label: _tr('Drut wypełniający', 'Filler wire'),
                      value: 'Ø ${calc.fillerMm.toStringAsFixed(1)} mm  '
                          '(${_material == "SS" ? "ER316L / ER308L" : _material == "CS" ? "ER70S-2" : _material == "DUPLEX" ? "ER2209" : "ER4043"})',
                    ),
                  _ParamLine(
                    label: _tr('Gaz osłonowy (palnik)', 'Shielding gas (torch)'),
                    value: '${calc.torchGas.min}–${calc.torchGas.max} L/min  (Ar)',
                  ),
                  _ParamLine(
                    label: _tr('Gaz formujący — przedmuch',
                        'Backing gas — pre-purge'),
                    value: '${_fmtLpm(kPrePurgeFlowLpmMin)}–'
                        '${_fmtLpm(kPrePurgeFlowLpmMax)} L/min',
                  ),
                  _ParamLine(
                    label: _tr('Gaz formujący — podczas spawania',
                        'Backing gas — while welding'),
                    value: '≤ ${_fmtLpm(kWeldingPurgeFlowLpmMax)} L/min',
                  ),
                  const SizedBox(height: 8),
                  Text(_ampNote(method), style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  Text(_purgeFlowAdvice(context),
                      style: const TextStyle(fontSize: 12)),
                  if (_material == 'AL') ...[
                    const SizedBox(height: 8),
                    Text(
                      _aluminiumNote(),
                      style: const TextStyle(
                          fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        Text(
          _tr('Wynik pomocniczy — wiąże WPS / specyfikacja projektu.',
              'Guidance only — the WPS / project specification is binding.'),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  /// Aluminium (AC) electrode note. Codes and tip colours come from
  /// kTungstenTypes (ISO 6848: WP green, WZ8 white), so this text cannot
  /// drift from the Tungsten screen.
  String _aluminiumNote() {
    final english = context.language == AppLanguage.en;
    String colour(String code) {
      final t = tungstenTypeByCode(code);
      return t == null ? '' : tungstenTipColor(t, english: english);
    }

    return _tr(
        '⚠ Aluminium: TIG na prądzie zmiennym (AC), elektroda WP — czysty '
            'wolfram (kolor: ${colour('WP')}) lub WZ8 — cyrkonowa (kolor: '
            '${colour('WZ8')}). Średnica elektrody powyżej pochodzi z tabeli '
            'DC− — dla AC sprawdź tabelę producenta elektrod. Wartości to punkt '
            'wyjścia — kalkulator zoptymalizowany pod stal.',
        '⚠ Aluminium: TIG on AC, WP pure tungsten (${colour('WP')}) or WZ8 '
            'zirconiated (${colour('WZ8')}) electrode. The electrode size above '
            'comes from the DC− table — for AC check the electrode maker\'s '
            'table. The numbers are a starting point — the calculator is tuned '
            'for steel.');
  }

  String _methodLabel(WeldingMethod m) {
    switch (m) {
      case WeldingMethod.tigWire:
        return AppLanguageController.isEnglish ? 'TIG with filler' : 'TIG z drutem';
      case WeldingMethod.tigNoWire:
        return AppLanguageController.isEnglish ? 'TIG without filler' : 'TIG bez drutu';
    }
  }

  String _methodToDb(WeldingMethod m) => pipeMethodDb(m);

  /// Skąd prąd — ta sama liczba co na liście „Startowe” dla tej rury.
  String _currentSourceNote(PipeCurrent c) {
    switch (c.source) {
      case PipeCurrentSource.exact:
        final p = c.point!;
        return _tr(
            'Z listy „Startowe”: Ø${p.odMm.toStringAsFixed(1)} × ${p.wallMm.toStringAsFixed(2)} mm → ${p.amps.toStringAsFixed(0)} A.',
            'From “Starter”: Ø${p.odMm.toStringAsFixed(1)} × ${p.wallMm.toStringAsFixed(2)} mm → ${p.amps.toStringAsFixed(0)} A.');
      case PipeCurrentSource.interpolated:
        return _tr('Interpolacja między punktami z listy „Startowe”.',
            'Interpolated between points of the “Starter” list.');
      case PipeCurrentSource.scaledByWall:
        return _tr(
            'Z najbliższej ścianki na liście „Startowe”, proporcjonalnie do grubości — sprawdź na próbce.',
            'From the nearest wall on the “Starter” list, scaled by thickness — check on a test piece.');
      case PipeCurrentSource.fromStainless:
        return _tr(
            'Brak punktów dla stali węglowej — prąd nierdzewnej tej rury / 0,9 (nierdzewna ≈ 10 % mniej prądu).',
            'No carbon-steel points — the stainless current of this pipe / 0.9 (stainless ≈ 10 % less current).');
      case PipeCurrentSource.none:
        return '';
    }
  }

  String _ampNote(WeldingMethod method) => method == WeldingMethod.tigNoWire
      ? _tr(
          'TIG bez drutu: pilnuj prędkości i dopasowania (fit-up). Jeśli robi „zapadniętą” grań – sprawdź purge i ujście (went). Niższa wartość zakresu = grań, wyższa = lico.',
          'TIG without filler: watch travel speed and fit-up. If the root sinks, check purge and venting. Lower end of the range = root, upper = cap.')
      : _tr(
          'TIG z drutem: niższa wartość zakresu = grań, wyższa = wypełnienie / lico. Jeśli „zimno” – podnieś A lub zwolnij; jeśli przegrzewasz – zmniejsz A lub przyspiesz.',
          'TIG with filler: lower end of the range = root pass, upper end = fill / cap. If it feels cold raise A or slow down; if you overheat reduce A or speed up.');
}

/// `weld_params` / `approved_weld_params` method code.
String pipeMethodDb(WeldingMethod m) =>
    m == WeldingMethod.tigWire ? 'TIG_WIRE' : 'TIG_AUTOGEN';

/// Punkty startowe z bazy (lista „Startowe”) jako dane domeny.
Future<List<PipeStartPoint>> loadPipeStartPoints() async => [
      for (final p in await ApprovedWeldParamDao().listAll())
        PipeStartPoint(
          material: p.baseMaterial,
          method: p.method,
          odMm: p.diameterMm,
          wallMm: p.wallThicknessMm,
          amps: p.amps,
        ),
    ];

/// Single-row "calculator output". The start current comes from the
/// starting points (lib/domain/welder_pipes/tig_start_params.dart); the
/// electrode and torch gas come from the same tables as the Tungsten screen.
class _AmpCalcResult {
  final double centerA, minA, maxA;
  final double electrodeMm;
  final double fillerMm; // 0 when no filler is used
  final ({int min, int max}) torchGas;
  const _AmpCalcResult({
    required this.centerA,
    required this.minA,
    required this.maxA,
    required this.electrodeMm,
    required this.fillerMm,
    required this.torchGas,
  });

  factory _AmpCalcResult.from({
    required WeldingMethod method,
    required double startA,
    required double t,
  }) {
    // Range a welder slides between for root vs cap.
    final spread = (method == WeldingMethod.tigNoWire) ? 0.18 : 0.15;
    final electrode = pipeElectrodeMm(startA);

    // Filler rod sized to wall thickness; only meaningful for TIG-with-wire.
    final filler = (method == WeldingMethod.tigWire)
        ? (t <= 2.0 ? 1.6 : t <= 3.0 ? 2.0 : 2.4)
        : 0.0;

    return _AmpCalcResult(
      centerA: startA,
      minA: startA * (1 - spread),
      maxA: startA * (1 + spread),
      electrodeMm: electrode,
      fillerMm: filler,
      torchGas: pipeTorchGasLpm(electrode),
    );
  }
}

class _ParamLine extends StatelessWidget {
  final String label;
  final String value;
  final bool primary;
  const _ParamLine({
    required this.label,
    required this.value,
    this.primary = false,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, color: cs.onSurface.withValues(alpha: 0.75))),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: primary ? 18 : 14,
                  fontWeight: primary ? FontWeight.w900 : FontWeight.w700,
                  color: primary ? cs.primary : cs.onSurface,
                  letterSpacing: primary ? -0.3 : 0)),
        ],
      ),
    );
  }
}

String _fmtLpm(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// ppm for display: one decimal below 100 ppm, whole numbers above.
String _fmtPpm(double v) =>
    v < 100 ? v.toStringAsFixed(1) : v.toStringAsFixed(0);

/// 210000 → "210 000".
String _groupThousands(double v) => v
    .toStringAsFixed(0)
    .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');

/// Backing-gas flow advice — one text for both the AMP and the Gases tab so
/// they can never disagree. Figures: HFT WP-269 (see purge_estimate.dart).
String _purgeFlowAdvice(BuildContext context) {
  final pre = '${_fmtLpm(kPrePurgeFlowLpmMin)}–'
      '${_fmtLpm(kPrePurgeFlowLpmMax)} L/min';
  final weld = '${_fmtLpm(kWeldingPurgeFlowLpmMax)} L/min';
  return context.tr(
    pl: 'Gaz formujący (purge): przedmuch przed spawaniem większym przepływem '
        '(typowo $pre, ok. 5 wymian objętości), aż analizator O₂ pokaże '
        'wymagany poziom. Na czas spawania zmniejsz do ok. $weld lub mniej — '
        'gaz ma być ledwo wyczuwalny na wylocie (lekkie nadciśnienie). Za duży '
        'przepływ → wklęsła grań; za mały → utlenienie.',
    en: 'Backing gas (purge): pre-purge with the higher flow (typically $pre, '
        'about 5 volume changes) until the O₂ analyser shows the required '
        'level. For welding reduce to about $weld or less — the gas should be '
        'barely perceptible at the outlet (slight positive pressure). Too much '
        'flow → concave root; too little → oxidation.',
  );
}

class _GasTab extends StatefulWidget {
  final WeldingMethod Function() methodGetter;
  const _GasTab({required this.methodGetter});

  @override
  State<_GasTab> createState() => _GasTabState();
}

class _GasTabState extends State<_GasTab> {
  // Purge (inside pipe) inputs
  final _odCtrl = TextEditingController(text: '60.3');
  final _tCtrl = TextEditingController(text: '2.0');
  final _lenCtrl = TextEditingController(text: '300'); // mm
  final _flowInCtrl = TextEditingController(text: '2'); // L/min
  final _ventsCtrl = TextEditingController(text: '2'); // holes count
  final _ventDiaCtrl = TextEditingController(text: '2.4'); // mm (domyślnie: elektroda 2.4)

  // How many "volume changes" during pre-purge
  final _nChangesCtrl = TextEditingController(text: '6');
  bool _pharmaMode = false;

  /// Odliczanie purge żyje w WeldTimerService (alarm: wibracja, dźwięk,
  /// pełny ekran, powiadomienie w tle) — nie ginie przy zmianie zakładki
  /// ani wyjściu z ekranu (dawniej lokalny Timer + SnackBar).
  final WeldTimerService _weldTimer = WeldTimerService.instance;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void dispose() {
    _odCtrl.dispose();
    _tCtrl.dispose();
    _lenCtrl.dispose();
    _flowInCtrl.dispose();
    _ventsCtrl.dispose();
    _ventDiaCtrl.dispose();
    _nChangesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final od = parseDecimal(_odCtrl.text) ?? 0;
    final t = parseDecimal(_tCtrl.text) ?? 0;
    final len = parseDecimal(_lenCtrl.text) ?? 0;
    final qIn = parseDecimal(_flowInCtrl.text) ?? 0; // L/min
    final nVents = int.tryParse(_ventsCtrl.text) ?? 0;
    final ventDiaMm = parseDecimal(_ventDiaCtrl.text) ?? 0;
    final nChanges = int.tryParse(_nChangesCtrl.text) ?? 0;

    // clamp() on num returns num; we need a double for volume calculations.
    final id = (od - 2 * t).clamp(0.0, double.infinity).toDouble();
    final volumeLiters = _pipeVolumeLiters(idMm: id, lenMm: len);
    final purgeMinutes = (qIn > 0 && nChanges > 0) ? (nChanges * volumeLiters / qIn) : 0.0;

    // O₂ left after N volume changes — same exponential model as the O₂ tab
    // in Welder tools (C = C₀·e^(−N)), compared with the AWS D18.2 samples.
    final estPpm = nChanges > 0
        ? residualO2PpmAfterVolumeChanges(nChanges.toDouble())
        : null;
    final estLevel = estPpm == null ? null : heatTintLevelForO2Ppm(estPpm);

    // Vent hole model (indicator): user drills vent holes (default: Ø2.4 mm).
    final safeVentDiaMm = ventDiaMm > 0 ? ventDiaMm : 2.4;
    final ventVelocity =
        ventVelocityMs(flowLpm: qIn, holes: nVents, holeDiaMm: safeVentDiaMm);

    // Złoty środek: Q dające docelową prędkość na wylotach w środku pasma
    // „rozsądnego” — te same progi co ostrzeżenie niżej, więc przycisk nigdy
    // nie ustawia Q, przed którym ten sam ekran ostrzega.
    final qRec = flowForVentVelocityLpm(
        velocityMs: kVentVelocityTargetMs, holes: nVents, holeDiaMm: safeVentDiaMm);
    final qRecMin = flowForVentVelocityLpm(
        velocityMs: 1.0, holes: nVents, holeDiaMm: safeVentDiaMm);
    final qRecMax = flowForVentVelocityLpm(
        velocityMs: kVentVelocityComfortMs, holes: nVents, holeDiaMm: safeVentDiaMm);

    final ventHint = _ventHint(qIn: qIn, nVents: nVents, vMs: ventVelocity);
    final pharmaHint = _pharmaMode
      ? _tr('Tryb Pharma: celuje w brak przebarwień od środka - zwykle wymaga bardziej rygorystycznego purge (więcej "wymian objętości") i dobrej szczelności.', 'Pharma mode: aims for no discoloration on the inside and usually requires stricter purge conditions (more volume changes) and good sealing.')
        : null;

    return ListView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        Text(_tr('Purge rury (usuwanie powietrza z wnętrza)', 'Pipe purge (removing air from inside)')),
        const SizedBox(height: 8),
        TextField(
          controller: _odCtrl,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(labelText: _tr('Średnica zewnętrzna rury OD [mm]', 'Pipe OD [mm]')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _tCtrl,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(labelText: _tr('Grubość ścianki t [mm]', 'Wall thickness t [mm]')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _lenCtrl,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(labelText: _tr('Długość odcinka do purge L [mm]', 'Section length to purge L [mm]')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _flowInCtrl,
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
          decoration: InputDecoration(
            labelText: _tr('Przepływ gazu do środka Q [L/min]', 'Internal gas flow Q [L/min]'),
            helperText: _tr('Czas przedmuchu liczony dla tego Q', 'Pre-purge time is calculated for this Q'),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ventDiaCtrl,
                keyboardType: numberKeyboard(),
                inputFormatters: numberInputFormatters(),
                decoration: InputDecoration(labelText: _tr('Średnica otworu wylotowego [mm]', 'Outlet hole diameter [mm]')),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _ventsCtrl,
                keyboardType: numberKeyboard(decimal: false),
                inputFormatters: numberInputFormatters(decimal: false),
                decoration: InputDecoration(labelText: _tr('Liczba otworów (szt.)', 'Number of holes (pcs)')),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (nVents > 0)
                    ? () {
                        _flowInCtrl.text = qRec.toStringAsFixed(1);
                        setState(() {});
                      }
                    : null,
                icon: const Icon(Icons.auto_fix_high),
                label: Text(_tr('Ustaw Q (złoty środek)', 'Set Q (golden middle)')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          nVents > 0
              ? _tr('Złoty środek: ~${kVentVelocityTargetMs.toStringAsFixed(0)} m/s na $nVents×Ø${safeVentDiaMm.toStringAsFixed(1)} → Q ≈ ${qRec.toStringAsFixed(1)} L/min (1–${kVentVelocityComfortMs.toStringAsFixed(0)} m/s: ${qRecMin.toStringAsFixed(1)}–${qRecMax.toStringAsFixed(1)} L/min). Heurystyka, nie norma. Większy przepływ przedmuchu wymaga więcej lub większych otworów.',
                  'Golden middle: ~${kVentVelocityTargetMs.toStringAsFixed(0)} m/s through $nVents×Ø${safeVentDiaMm.toStringAsFixed(1)} → Q ≈ ${qRec.toStringAsFixed(1)} L/min (1–${kVentVelocityComfortMs.toStringAsFixed(0)} m/s: ${qRecMin.toStringAsFixed(1)}–${qRecMax.toStringAsFixed(1)} L/min). A heuristic, not a code. A higher pre-purge flow needs more or larger holes.')
              : _tr('Podaj liczbę otworów wylotowych, aby wyliczyć złoty środek Q.', 'Enter the number of outlet holes to calculate the golden-middle Q.'),
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nChangesCtrl,
                keyboardType: numberKeyboard(decimal: false),
                inputFormatters: numberInputFormatters(decimal: false),
                decoration: InputDecoration(labelText: _tr('Wymiany objętości N', 'Volume changes N')),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(_tr('Pharma (bez koloru)', 'Pharma (no discoloration)')),
                value: _pharmaMode,
                onChanged: (v) {
                  setState(() {
                    _pharmaMode = v;
                    // Sensowny default: większa liczba wymian objętości.
                    _nChangesCtrl.text = v ? '10' : '6';
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('OD: ${od.toStringAsFixed(1)} mm | t: ${t.toStringAsFixed(2)} mm | ID: ${id.toStringAsFixed(1)} mm'),
                Text('${_tr('Długość', 'Length')}: ${len.toStringAsFixed(0)} mm | ${_tr('Objętość', 'Volume')}: ${volumeLiters.isFinite ? volumeLiters.toStringAsFixed(3) : '-'} L'),
                const SizedBox(height: 10),
                Text('Pre-purge: N·V/Q = ${purgeMinutes.isFinite ? purgeMinutes.toStringAsFixed(2) : '-'} min'),
                if (estPpm != null && estLevel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _tr(
                        'Szac. O₂ po N = $nChanges wymianach: ≈ ${_fmtPpm(estPpm)} ppm '
                            '(model pesymistyczny — pełne wymieszanie, C₀·e^(−N), C₀ = ${_groupThousands(kPurgeAirO2Ppm)} ppm) — '
                            'najbliższy wzorzec AWS D18.2: poziom ${estLevel.level} '
                            '(${estLevel.o2Ppm.toStringAsFixed(0)} ppm).',
                        'Est. O₂ after N = $nChanges volume changes: ≈ ${_fmtPpm(estPpm)} ppm '
                            '(pessimistic model — perfect mixing, C₀·e^(−N), C₀ = ${_groupThousands(kPurgeAirO2Ppm)} ppm) — '
                            'nearest AWS D18.2 sample: level ${estLevel.level} '
                            '(${estLevel.o2Ppm.toStringAsFixed(0)} ppm).'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _tr('Czas orientacyjny — zweryfikuj analizatorem O₂.',
                      'Time is indicative — verify with an O₂ analyser.'),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text('${_tr('Wyloty', 'Outlets')}: $nVents×Ø${safeVentDiaMm.toStringAsFixed(1)} mm | ${_tr('prędkość na wylotach (wskaźnik)', 'outlet velocity (indicator)')}: ${ventVelocity.isFinite ? ventVelocity.toStringAsFixed(2) : '-'} m/s'),
                const SizedBox(height: 8),
                Text(ventHint, style: const TextStyle(fontSize: 12)),
                if (pharmaHint != null) ...[
                  const SizedBox(height: 8),
                  Text(pharmaHint, style: const TextStyle(fontSize: 12)),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: purgeMinutes.isFinite && purgeMinutes > 0
                        ? () => startPurgeCountdown(
                              context,
                              Duration(milliseconds: (purgeMinutes * 60000).round()),
                              service: _weldTimer,
                            )
                        : null,
                    icon: const Icon(Icons.timer),
                    label: Text(_tr('Start minutnika (pre-purge)', 'Start timer (pre-purge)')),
                  ),
                ),
                const SizedBox(height: 8),
                ListenableBuilder(
                  listenable: _weldTimer,
                  builder: (context, _) {
                    if (_weldTimer.mode != WeldTimerMode.purge ||
                        !(_weldTimer.running || _weldTimer.hasProgress || _weldTimer.finished)) {
                      return const SizedBox.shrink();
                    }
                    final left = _weldTimer.remaining ?? Duration.zero;
                    final mm = left.inMinutes.toString().padLeft(2, '0');
                    final ss = (left.inSeconds % 60).toString().padLeft(2, '0');
                    return Text(
                      _weldTimer.finished
                          ? _tr('Purge: czas minął.', 'Purge: time is up.')
                          : '${_tr('Minutnik purge', 'Purge timer')}: $mm:$ss'
                              '${_weldTimer.running ? '' : _tr(' (pauza — zakładka Timer)', ' (paused — Timer tab)')}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  _purgeFlowAdvice(context),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _tr('Wynik pomocniczy — wiąże WPS / specyfikacja projektu.',
              'Guidance only — the WPS / project specification is binding.'),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  double _pipeVolumeLiters({required double idMm, required double lenMm}) {
    if (idMm <= 0 || lenMm <= 0) return 0;
    final r = idMm / 2;
    final vMm3 = math.pi * r * r * lenMm;
    return vMm3 / 1000000.0;
  }

  String _ventHint({required double qIn, required int nVents, required double vMs}) {
    if (qIn <= 0) return _tr('Wpisz przepływ Q > 0.', 'Enter flow Q > 0.');
    if (nVents <= 0) return _tr('Brak wylotu -> rośnie ciśnienie. Dodaj otwór(y) wylotowe.', 'No outlet -> pressure rises. Add outlet hole(s).');

    // Heurystyka (nie norma): bardzo duża prędkość na małych otworach zwykle
    // oznacza dławienie wylotu. Progi wspólne ze „złotym środkiem”.
    if (!vMs.isFinite) return _tr('Sprawdź dane (otwory/flow).', 'Check the data (holes/flow).');

    if (vMs > kVentVelocityBackPressureMs) {
      return _tr('Uwaga: duże obciążenie wylotu (wysoka prędkość na otworach). Ryzyko back-pressure -> dodaj więcej otworów lub zmniejsz Q.', 'Warning: high outlet load (high hole velocity). Risk of back-pressure -> add more holes or reduce Q.');
    }
    if (vMs > kVentVelocityComfortMs) {
      return _tr('OK, ale blisko granicy komfortu. Jeśli widzisz zapadniętą grań / "dmuchanie", dodaj otwory albo zmniejsz Q.', 'OK, but close to the comfort limit. If you see a sunken root or blowing, add holes or reduce Q.');
    }
    if (vMs < kVentVelocityLowMs) {
      return _tr('Wylot bardzo "luźny" (dużo otworów lub mały Q). Ciśnienie będzie małe; jeśli pojawiają się "krzaki", zwiększ Q lub liczbę wymian N.', 'The outlet is very open (many holes or low Q). Pressure will be low; if oxidation appears, increase Q or the number of volume changes N.');
    }
    return _tr('Wylot wygląda rozsądnie (lekkie nadciśnienie powinno się dać utrzymać).', 'The outlet looks reasonable (slight positive pressure should be maintainable).');
  }
}

// ------------------------------
// Zatwierdzone AMP (read-only)
// ------------------------------
class _ApprovedAmpTab extends StatefulWidget {
  final WeldingMethod Function() methodGetter;
  const _ApprovedAmpTab({required this.methodGetter});

  @override
  State<_ApprovedAmpTab> createState() => _ApprovedAmpTabState();
}

class _ApprovedAmpTabState extends State<_ApprovedAmpTab> {
  final _dao = ApprovedWeldParamDao();
  final _q = TextEditingController();
  String _material = 'SS';
  String? _futureKey;
  Future<List<ApprovedWeldParam>>? _future;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  String _methodToDb(WeldingMethod m) => pipeMethodDb(m);

  String _methodLabelDb(String method) =>
      weldParamMethodLabel(method, en: AppLanguageController.isEnglish);

  /// Elektroda i gaz palnika z prądu wpisu — te same funkcje co kalkulator
  /// AMP i ekran Wolfram (kolumny elektrody/gazu z seedu bywały sprzeczne
  /// z tabelą wolframu, np. Ø2,4 przy 55 A). Formowanie — ta sama porada
  /// dwufazowa co w AMP i Gazach (HFT WP-269), nie 10–18 L/min z seedu.
  String _rowDetails(ApprovedWeldParam p) {
    final e = pipeElectrodeMm(p.amps);
    final g = pipeTorchGasLpm(e);
    final pre = '${_fmtLpm(kPrePurgeFlowLpmMin)}–${_fmtLpm(kPrePurgeFlowLpmMax)}';
    final weld = _fmtLpm(kWeldingPurgeFlowLpmMax);
    return '${_tr('Ampery', 'Amps')}: ${p.amps.toStringAsFixed(0)} A\n'
        '${_tr('Elektroda', 'Electrode')}: Ø${e.toStringAsFixed(1)} | '
        '${_tr('Palnik', 'Torch')}: ${g.min}–${g.max} L/min\n'
        '${_tr('Formowanie: przedmuch $pre, w trakcie ≤ $weld L/min', 'Backing gas: pre-purge $pre, while welding ≤ $weld L/min')}'
        '${p.wallThicknessMm > 3.0 ? '\n${_tr('Ścianka > 3 mm: złącze wieloprzejściowe — prąd ściegu wg WPS.', 'Wall > 3 mm: multi-pass joint — the pass current per WPS.')}' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final dbMethod = _methodToDb(widget.methodGetter());
    // Jedno zapytanie na (metoda, materiał) — nie przy każdym znaku
    // w wyszukiwarce (future tworzony w build kręcił się bez końca).
    final key = '$dbMethod|$_material';
    if (key != _futureKey) {
      _futureKey = key;
      _future = _dao.listAll(method: dbMethod, material: _material);
    }

    return FutureBuilder<List<ApprovedWeldParam>>(
      future: _future,
      builder: (context, snap) {
        final items = snap.data ?? const <ApprovedWeldParam>[];
        final query = _q.text.trim().toLowerCase();
        final filtered = items.where((p) {
          if (query.isEmpty) return true;
          final hay = '${p.baseMaterial} ${p.method} ${p.diameterMm} ${p.wallThicknessMm} ${p.electrodeMm} ${p.torchGasLpm} ${p.purgeLpm} ${p.amps} ${p.note ?? ''}'.toLowerCase();
          return hay.contains(query);
        }).toList();

        return ListView(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _material,
              decoration: InputDecoration(labelText: _tr('Materiał', 'Material')),
              items: [
                DropdownMenuItem(value: 'SS', child: Text(_tr('SS (nierdzewna)', 'SS (stainless)'))),
                DropdownMenuItem(value: 'CS', child: Text(_tr('CS (czarna)', 'CS (carbon steel)'))),
                const DropdownMenuItem(value: 'DUPLEX', child: Text('Duplex')),
                DropdownMenuItem(value: 'AL', child: Text(_tr('Aluminium', 'Aluminum'))),
              ],
              onChanged: (v) => setState(() => _material = v ?? 'SS'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _q,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: _tr('Szukaj w startowych AMP', 'Search starter AMP')),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text(
              _tr('Wartości startowe dostarczone z aplikacją, nie WPS — wiąże WPS / specyfikacja projektu.',
                  'Starting values shipped with the app, not a WPS — the WPS / project specification is binding.'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (snap.connectionState != ConnectionState.done)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (snap.connectionState == ConnectionState.done && filtered.isEmpty)
              Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_tr('Brak parametrów startowych dla tej metody.', 'No starter parameters for this method.')))),
            for (final p in filtered)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.tune),
                  title: Text('${_methodLabelDb(p.method)} | ${p.baseMaterial} | Ø${p.diameterMm.toStringAsFixed(1)} × t${p.wallThicknessMm.toStringAsFixed(2)}'),
                  subtitle: Text(
                    '${_rowDetails(p)}'
                    '${(p.note ?? '').trim().isNotEmpty ? "\n${_tr('Notatka', 'Note')}: ${p.note}" : ""}',
                  ),
                  isThreeLine: true,
                ),
              ),
          ],
        );
      },
    );
  }
}
