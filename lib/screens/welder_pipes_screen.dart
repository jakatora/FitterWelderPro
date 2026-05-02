import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../database/weld_param_dao.dart';
import '../database/approved_weld_param_dao.dart';
import '../i18n/app_language.dart';
import '../models/weld_param.dart';
import '../models/approved_weld_param.dart';
import '../widgets/help_button.dart';

enum WeldingMethod { tigWire, tigNoWire }

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
              Tab(text: _tr('Zatwierdzone', 'Approved')),
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
                    '${_methodLabelDb(p.method)} | ${p.baseMaterial} | Ø${p.diameterMm.toStringAsFixed(1)} × t${p.wallThicknessMm.toStringAsFixed(2)}',
                  ),
                  subtitle: Text(
                    '${(p.welderModel != null && p.welderModel!.trim().isNotEmpty) ? "${_tr('Spawarka', 'Welder')}: ${p.welderModel}\\n" : ""}'
                    '${_tr('Elektroda', 'Electrode')}: ${p.electrodeMm.toStringAsFixed(1)}  |  ${_tr('Palnik', 'Torch')}: ${p.torchGasLpm.toStringAsFixed(1)} L/min  |  Purge: ${p.purgeLpm.toStringAsFixed(1)} L/min\n'
                    '${_tr('Dysza', 'Nozzle')}: ${_nozzleText(p)}  |  ${_tr('Ampery', 'Amps')}: ${p.amps.toStringAsFixed(0)} A'
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

  String _methodLabelDb(String method) {
    switch (method) {
      case 'TIG_WIRE':
        return AppLanguageController.isEnglish ? 'TIG with filler' : 'TIG z drutem';
      case 'TIG_AUTOGEN':
        return AppLanguageController.isEnglish ? 'TIG without filler' : 'TIG bez drutu';
      default:
        return method;
    }
  }

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
      final x = double.tryParse((v ?? '').replaceAll(',', '.'));
      if (x == null || x <= 0) return _tr('Wpisz liczbę > 0', 'Enter a number > 0');
      return null;
    }

    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
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
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(labelText: _tr('Średnica rury OD [mm]', 'Pipe OD [mm]')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: wallCtrl,
                            validator: reqNum,
                            keyboardType: TextInputType.number,
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
                            validator: reqNum,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(labelText: _tr('Gaz na palnik [L/min]', 'Torch gas [L/min]')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: purgeCtrl,
                            validator: reqNum,
                            keyboardType: TextInputType.number,
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
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: _tr('Ampery [A]', 'Amps [A]')),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: outletHolesCtrl,
                      validator: reqInt0,
                      keyboardType: TextInputType.number,
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
                  diameterMm: double.parse(diameterCtrl.text.replaceAll(',', '.')),
                  wallThicknessMm: double.parse(wallCtrl.text.replaceAll(',', '.')),
                  electrodeMm: electrode,
                  torchGasLpm: double.parse(torchGasCtrl.text.replaceAll(',', '.')),
                  nozzleType: nozzleTypeCtrl.text.trim().isEmpty ? null : nozzleTypeCtrl.text.trim(),
                  nozzleSize: nozzleSizeCtrl.text.trim().isEmpty ? null : nozzleSizeCtrl.text.trim(),
                  purgeLpm: double.parse(purgeCtrl.text.replaceAll(',', '.')),
                  amps: double.parse(ampsCtrl.text.replaceAll(',', '.')),
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
        );
      },
    );

  }

  Future<bool?> _showViewEditDialog(BuildContext context, WeldParam existing) async {
    final formKey = GlobalKey<FormState>();

    String baseMaterial = existing.baseMaterial;
    WeldingMethod method = _dbToMethod(existing.method);
    double electrode = existing.electrodeMm;

    final diameterCtrl = TextEditingController(text: existing.diameterMm.toStringAsFixed(1));
    final wallCtrl = TextEditingController(text: existing.wallThicknessMm.toStringAsFixed(2));
    final welderModelCtrl = TextEditingController(text: existing.welderModel ?? '');
    final torchGasCtrl = TextEditingController(text: existing.torchGasLpm.toStringAsFixed(1));
    final nozzleTypeCtrl = TextEditingController(text: existing.nozzleType ?? '');
    final nozzleSizeCtrl = TextEditingController(text: existing.nozzleSize ?? '');
    final purgeCtrl = TextEditingController(text: existing.purgeLpm.toStringAsFixed(1));
    final ampsCtrl = TextEditingController(text: existing.amps.toStringAsFixed(0));
    final outletHolesCtrl = TextEditingController(text: (existing.outletHoles ?? 0).toString());
    String tempo = existing.tempo ?? 'NORMAL';
    final noteCtrl = TextEditingController(text: existing.note ?? '');

    String? reqInt0(String? v) {
      final x = int.tryParse((v ?? '').trim());
      if (x == null || x < 0) return _tr('Wpisz liczbę całkowitą ≥ 0', 'Enter an integer ≥ 0');
      return null;
    }

    String? reqNum(String? v) {
      final x = double.tryParse((v ?? '').replaceAll(',', '.'));
      if (x == null || x <= 0) return _tr('Wpisz liczbę > 0', 'Enter a number > 0');
      return null;
    }

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
                            ],
                            onChanged: (v) => baseMaterial = v ?? existing.baseMaterial,
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
                            onChanged: (v) => method = v ?? _dbToMethod(existing.method),
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
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(labelText: _tr('Średnica rury OD [mm]', 'Pipe OD [mm]')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: wallCtrl,
                            validator: reqNum,
                            keyboardType: TextInputType.number,
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
                      onChanged: (v) => electrode = v ?? existing.electrodeMm,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: torchGasCtrl,
                            validator: reqNum,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(labelText: _tr('Gaz na palnik [L/min]', 'Torch gas [L/min]')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: purgeCtrl,
                            validator: reqNum,
                            keyboardType: TextInputType.number,
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
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: _tr('Ampery [A]', 'Amps [A]')),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: outletHolesCtrl,
                      validator: reqInt0,
                      keyboardType: TextInputType.number,
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
                  method: _methodToDb(method),
                  baseMaterial: baseMaterial,
                  welderModel: welderModelCtrl.text.trim().isEmpty ? null : welderModelCtrl.text.trim(),
                  diameterMm: double.parse(diameterCtrl.text.replaceAll(',', '.')),
                  wallThicknessMm: double.parse(wallCtrl.text.replaceAll(',', '.')),
                  electrodeMm: electrode,
                  torchGasLpm: double.parse(torchGasCtrl.text.replaceAll(',', '.')),
                  nozzleType: nozzleTypeCtrl.text.trim().isEmpty ? null : nozzleTypeCtrl.text.trim(),
                  nozzleSize: nozzleSizeCtrl.text.trim().isEmpty ? null : nozzleSizeCtrl.text.trim(),
                  purgeLpm: double.parse(purgeCtrl.text.replaceAll(',', '.')),
                  amps: double.parse(ampsCtrl.text.replaceAll(',', '.')),
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

  WeldingMethod _dbToMethod(String method) {
    switch (method) {
      case 'MAG':
        // MAG nie jest dostępny w UI – mapujemy stare wpisy do TIG z drutem.
        return WeldingMethod.tigWire;
      case 'TIG_WIRE':
        return WeldingMethod.tigWire;
      case 'TIG_AUTOGEN':
        return WeldingMethod.tigNoWire;
      default:
        return widget.methodGetter();
    }
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
  final _dao = ApprovedWeldParamDao();
  String _material = 'SS';

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void dispose() {
    _diamCtrl.dispose();
    _tCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = double.tryParse(_diamCtrl.text.replaceAll(',', '.')) ?? 0;
    final t = double.tryParse(_tCtrl.text.replaceAll(',', '.')) ?? 0;

    final method = widget.methodGetter();
    final rec = _recommendAmps(method: method, tMm: t);
    final dbMethod = method == WeldingMethod.tigWire ? 'TIG_WIRE' : 'TIG_AUTOGEN';

    return FutureBuilder<List<ApprovedWeldParam>>(
      future: _dao.listAll(method: dbMethod, material: _material),
      builder: (context, snap) {
        final items = snap.data ?? const <ApprovedWeldParam>[];
        ApprovedWeldParam? exact;
        ApprovedWeldParam? nearest;
        double bestScore = double.infinity;
        for (final p in items) {
          final dDiff = (p.diameterMm - d).abs();
          final tDiff = (p.wallThicknessMm - t).abs();
          if (dDiff <= 0.11 && tDiff <= 0.02) {
            exact = p;
            break;
          }
          final score = tDiff * 100 + dDiff;
          if (score < bestScore) {
            bestScore = score;
            nearest = p;
          }
        }
        return ListView(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
          children: [
        Text(_tr('Kalkulator AMP (złoty środek - punkt startowy)', 'AMP calculator (golden middle - starting point)')),
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
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _tr('Średnica zewnętrzna rury OD [mm]', 'Pipe OD [mm]')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _tCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _tr('Grubość ścianki t [mm]', 'Wall thickness t [mm]')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_tr('Metoda', 'Method')}: ${_methodLabel(method)}'),
                Text('${_tr('Materiał', 'Material')}: $_material'),
                const SizedBox(height: 10),
                Text('OD: ${d.toStringAsFixed(1)} mm | t: ${t.toStringAsFixed(2)} mm'),
                const SizedBox(height: 10),
                if (exact != null) ...[
                  Text('${_tr('Zatwierdzony AMP', 'Approved AMP')}: ${exact.amps.toStringAsFixed(0)} A', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${_tr('Elektroda', 'Electrode')}: ${exact.electrodeMm.toStringAsFixed(1)} | ${_tr('Gaz', 'Gas')}: ${exact.torchGasLpm.toStringAsFixed(1)} L/min | Purge: ${exact.purgeLpm.toStringAsFixed(1)} L/min'),
                  const SizedBox(height: 8),
                  Text(_tr('Dopasowanie: dokładne', 'Match: exact'), style: const TextStyle(fontSize: 12)),
                ] else if (nearest != null) ...[
                  Text('${_tr('Najbliższy zatwierdzony AMP', 'Nearest approved AMP')}: ${nearest.amps.toStringAsFixed(0)} A', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${_tr('Dla', 'For')}: Ø${nearest.diameterMm.toStringAsFixed(1)} × t${nearest.wallThicknessMm.toStringAsFixed(2)}'),
                  Text('${_tr('Elektroda', 'Electrode')}: ${nearest.electrodeMm.toStringAsFixed(1)} | ${_tr('Gaz', 'Gas')}: ${nearest.torchGasLpm.toStringAsFixed(1)} L/min | Purge: ${nearest.purgeLpm.toStringAsFixed(1)} L/min'),
                  const SizedBox(height: 8),
                  Text('${_tr('Start z interpolacji', 'Interpolation start')}: ${rec.startA.toStringAsFixed(0)} A'),
                  Text('${_tr('Zakres startowy', 'Starting range')}: ${rec.minA.toStringAsFixed(0)}-${rec.maxA.toStringAsFixed(0)} A'),
                ] else ...[
                  Text('${_tr('Start prądu', 'Current start')}: ${rec.startA.toStringAsFixed(0)} A'),
                  Text('${_tr('Zakres startowy', 'Starting range')}: ${rec.minA.toStringAsFixed(0)}-${rec.maxA.toStringAsFixed(0)} A'),
                ],
                const SizedBox(height: 10),
                Text(
                  exact?.note?.isNotEmpty == true ? exact!.note! : rec.note,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                if (t >= 3.0) ...[
                  Text(_tr('Pamiętaj o fazowaniu rur.', 'Remember to bevel the pipes.'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ],
    );
      },
    );
  }

  String _methodLabel(WeldingMethod m) {
    switch (m) {
      case WeldingMethod.tigWire:
        return AppLanguageController.isEnglish ? 'TIG with filler' : 'TIG z drutem';
      case WeldingMethod.tigNoWire:
        return AppLanguageController.isEnglish ? 'TIG without filler' : 'TIG bez drutu';
    }
  }
}

class _AmpRecommendation {
  final double startA;
  final double minA;
  final double maxA;
  final String note;
  const _AmpRecommendation({required this.startA, required this.minA, required this.maxA, required this.note});
}

_AmpRecommendation _recommendAmps({required WeldingMethod method, required double tMm}) {
  // Punkt startowy (orientacyjnie) dla TIG na rurach ze stali nierdzewnej.
  // Docelowo: jeżeli w bibliotece są zatwierdzone dane użytkowników, bierzemy je.
  if (tMm <= 0) {
    return _AmpRecommendation(startA: 0, minA: 0, maxA: 0, note: AppLanguageController.isEnglish ? 'Enter t > 0.' : 'Wpisz t > 0.');
  }

  final table = _startTablePoints(method);
  final start = _interpFromTable(table, tMm).clamp(15.0, 260.0).toDouble();

  // Z forów najczęściej widać, że „widełki startowe” ~±10–15% są OK.
  // Dla autogenu dajemy nieco szerszy zakres (łatwo przepalić / łatwo „zimno”).
  final spread = (method == WeldingMethod.tigNoWire) ? 0.15 : 0.12;
  return _AmpRecommendation(
    startA: start,
    minA: start * (1 - spread),
    maxA: start * (1 + spread),
    note: method == WeldingMethod.tigNoWire
        ? (AppLanguageController.isEnglish ? 'TIG without filler: watch travel speed and fit-up. If the root sinks, check purge and venting.' : 'TIG bez drutu: pilnuj prędkości i dopasowania (fit-up). Jeśli robi „zapadniętą” grań – sprawdź purge i ujście (went).')
        : (AppLanguageController.isEnglish ? 'TIG with filler: if it feels cold, increase A or slow down. If you overheat it, reduce A or speed up.' : 'TIG z drutem: jeśli jest „zimno”, zwiększ A lub zwolnij. Jeśli przegrzewasz, zmniejsz A lub przyspiesz.'),
  );
}

List<MapEntry<double, double>> _startTablePoints(WeldingMethod method) {
  // t(mm) -> A
  switch (method) {
    case WeldingMethod.tigWire:
      return const [
        MapEntry(1.0, 30.0),
        MapEntry(1.5, 40.0),
        MapEntry(2.0, 55.0),
        MapEntry(2.5, 70.0),
        MapEntry(3.0, 80.0),
        MapEntry(4.0, 100.0),
      ];
    case WeldingMethod.tigNoWire:
      return const [
        MapEntry(1.0, 35.0),
        MapEntry(1.5, 45.0),
        MapEntry(2.0, 60.0),
        MapEntry(2.5, 75.0),
        MapEntry(3.0, 90.0),
        MapEntry(4.0, 110.0),
      ];
  }
}

double _interpFromTable(List<MapEntry<double, double>> pts, double tMm) {
  final sorted = [...pts]..sort((a, b) => a.key.compareTo(b.key));
  if (tMm <= sorted.first.key) return sorted.first.value;
  if (tMm >= sorted.last.key) return sorted.last.value;

  for (var i = 0; i < sorted.length - 1; i++) {
    final a = sorted[i];
    final b = sorted[i + 1];
    if (tMm >= a.key && tMm <= b.key) {
      final x0 = a.key;
      final y0 = a.value;
      final x1 = b.key;
      final y1 = b.value;
      final t = (tMm - x0) / (x1 - x0);
      return y0 + (y1 - y0) * t;
    }
  }
  return sorted.last.value;
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
  final _flowInCtrl = TextEditingController(text: '2'); // L/min (start – złoty środek)
  final _ventsCtrl = TextEditingController(text: '2'); // holes count
  final _ventDiaCtrl = TextEditingController(text: '2.4'); // mm (domyślnie: elektroda 2.4)

  // How many "volume changes" during pre-purge
  final _nChangesCtrl = TextEditingController(text: '6');
  bool _pharmaMode = false;

  // Timer
  Timer? _timer;
  int _remainingSeconds = 0;
  bool _timerRunning = false;

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
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final od = double.tryParse(_odCtrl.text.replaceAll(',', '.')) ?? 0;
    final t = double.tryParse(_tCtrl.text.replaceAll(',', '.')) ?? 0;
    final len = double.tryParse(_lenCtrl.text.replaceAll(',', '.')) ?? 0;
    final qIn = double.tryParse(_flowInCtrl.text.replaceAll(',', '.')) ?? 0; // L/min
    final nVents = int.tryParse(_ventsCtrl.text) ?? 0;
    final ventDiaMm = double.tryParse(_ventDiaCtrl.text.replaceAll(',', '.')) ?? 0;
    final nChanges = int.tryParse(_nChangesCtrl.text) ?? 0;

    // clamp() on num returns num; we need a double for volume calculations.
    final id = (od - 2 * t).clamp(0.0, double.infinity).toDouble();
    final volumeLiters = _pipeVolumeLiters(idMm: id, lenMm: len);
    final purgeMinutes = (qIn > 0 && nChanges > 0) ? (nChanges * volumeLiters / qIn) : 0.0;

    // Vent hole model (indicator): user drills vent holes (default: Ø2.4 mm).
    final safeVentDiaMm = ventDiaMm > 0 ? ventDiaMm : 2.4;
    final areaOne = math.pi * math.pow(safeVentDiaMm / 2, 2); // mm^2
    final totalArea = nVents * areaOne; // mm^2
    final qMm3PerSec = qIn * 1000000 / 60; // 1 L = 1e6 mm^3
    final ventVelocityMmPerSec = (totalArea > 0) ? (qMm3PerSec / totalArea) : double.infinity;

    // Złoty środek: rekomendacja Q na otwór skaluje się z polem otworu (utrzymujemy podobną "prędkość" na wylotach).
    // Bazą jest Ø1.2 mm: standard ~0.75 L/min / otwór, pharma ~1.00 L/min / otwór.
    const baseDiaMm = 1.2;
    final scale = math.pow(safeVentDiaMm / baseDiaMm, 2).toDouble();
    final qPerHoleRec = (_pharmaMode ? 1.0 : 0.75) * scale; // L/min na 1 otwór o średnicy safeVentDiaMm
    final qRec = (nVents > 0) ? (nVents * qPerHoleRec) : 0.0;
    final qRecMin = (nVents > 0) ? (nVents * ((_pharmaMode ? 0.8 : 0.5) * scale)) : 0.0;
    final qRecMax = (nVents > 0) ? (nVents * ((_pharmaMode ? 1.2 : 1.0) * scale)) : 0.0;

    final ventHint = _ventHint(qIn: qIn, nVents: nVents, ventVelocityMmPerSec: ventVelocityMmPerSec);
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
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _tr('Średnica zewnętrzna rury OD [mm]', 'Pipe OD [mm]')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _tCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _tr('Grubość ścianki t [mm]', 'Wall thickness t [mm]')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _lenCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _tr('Długość odcinka do purge L [mm]', 'Section length to purge L [mm]')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _flowInCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: _tr('Przepływ gazu do środka Q [L/min]', 'Internal gas flow Q [L/min]')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ventDiaCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: _tr('Średnica otworu wylotowego [mm]', 'Outlet hole diameter [mm]')),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _ventsCtrl,
                keyboardType: TextInputType.number,
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
                        // Ustawiamy złoty środek Q zależny od liczby wylotów.
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
              ? _tr('Start: ~${qPerHoleRec.toStringAsFixed(2)} L/min na 1 otwór Ø${safeVentDiaMm.toStringAsFixed(1)} -> Q ≈ ${qRec.toStringAsFixed(1)} L/min (zakres ${qRecMin.toStringAsFixed(1)}-${qRecMax.toStringAsFixed(1)}).', 'Start: ~${qPerHoleRec.toStringAsFixed(2)} L/min for 1 hole Ø${safeVentDiaMm.toStringAsFixed(1)} -> Q ≈ ${qRec.toStringAsFixed(1)} L/min (range ${qRecMin.toStringAsFixed(1)}-${qRecMax.toStringAsFixed(1)}).')
              : _tr('Podaj liczbę otworów wylotowych, aby wyliczyć złoty środek Q na otwór.', 'Enter the number of outlet holes to calculate the golden-middle Q per hole.'),
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nChangesCtrl,
                keyboardType: TextInputType.number,
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
                const SizedBox(height: 8),
                Text('${_tr('Wyloty', 'Outlets')}: $nVents×Ø1.2 mm | ${_tr('prędkość na wylotach (wskaźnik)', 'outlet velocity (indicator)')}: ${ventVelocityMmPerSec.isFinite ? (ventVelocityMmPerSec / 1000).toStringAsFixed(2) : '-'} m/s'),
                const SizedBox(height: 8),
                Text(ventHint, style: const TextStyle(fontSize: 12)),
                if (pharmaHint != null) ...[
                  const SizedBox(height: 8),
                  Text(pharmaHint, style: const TextStyle(fontSize: 12)),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: purgeMinutes.isFinite && purgeMinutes > 0 ? () => _startTimerFromMinutes(purgeMinutes) : null,
                        icon: const Icon(Icons.timer),
                        label: Text(_tr('Start minutnika (pre-purge)', 'Start timer (pre-purge)')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _TimerPanel(
                  isRunning: _timerRunning,
                  remainingSeconds: _remainingSeconds,
                  onPause: _timerRunning ? _pauseTimer : null,
                  onResume: (!_timerRunning && _remainingSeconds > 0) ? _resumeTimer : null,
                  onStop: (_timerRunning || _remainingSeconds > 0) ? _stopTimer : null,
                ),
                const SizedBox(height: 10),
                Text(
                  _tr('Wskazówka: po pre-purge zwykle zmniejsza się Q do "lekkiego dodatniego ciśnienia". Zbyt duże Q przy zbyt małym wylocie może powodować zapadniętą/grubą grań, a za małe Q - utlenienie ("krzaki").', 'Tip: after pre-purge, Q is usually reduced to a slight positive pressure. Too much Q with too small an outlet can cause a sunken/heavy root, and too little Q can cause oxidation.'),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
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

  String _ventHint({required double qIn, required int nVents, required double ventVelocityMmPerSec}) {
    if (qIn <= 0) return _tr('Wpisz przepływ Q > 0.', 'Enter flow Q > 0.');
    if (nVents <= 0) return _tr('Brak wylotu -> rośnie ciśnienie. Dodaj otwór(y) wylotowe.', 'No outlet -> pressure rises. Add outlet hole(s).');

    // Heurystyka (nie norma): bardzo duża prędkość na małych otworach zwykle oznacza dławienie wylotu.
    final vMs = ventVelocityMmPerSec / 1000.0;
    if (!vMs.isFinite) return _tr('Sprawdź dane (otwory/flow).', 'Check the data (holes/flow).');

    if (vMs > 6.0) {
      return _tr('Uwaga: duże obciążenie wylotu (wysoka prędkość na otworach). Ryzyko back-pressure -> dodaj więcej otworów lub zmniejsz Q.', 'Warning: high outlet load (high hole velocity). Risk of back-pressure -> add more holes or reduce Q.');
    }
    if (vMs > 3.0) {
      return _tr('OK, ale blisko granicy komfortu. Jeśli widzisz zapadniętą grań / "dmuchanie", dodaj otwory albo zmniejsz Q.', 'OK, but close to the comfort limit. If you see a sunken root or blowing, add holes or reduce Q.');
    }
    if (vMs < 0.5) {
      return _tr('Wylot bardzo "luźny" (dużo otworów lub mały Q). Ciśnienie będzie małe; jeśli pojawiają się "krzaki", zwiększ Q lub liczbę wymian N.', 'The outlet is very open (many holes or low Q). Pressure will be low; if oxidation appears, increase Q or the number of volume changes N.');
    }
    return _tr('Wylot wygląda rozsądnie (lekkie nadciśnienie powinno się dać utrzymać).', 'The outlet looks reasonable (slight positive pressure should be maintainable).');
  }

  void _startTimerFromMinutes(double minutes) {
    final seconds = (minutes * 60).ceil();
    setState(() {
      _remainingSeconds = seconds;
      _timerRunning = true;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_remainingSeconds <= 1) {
          _remainingSeconds = 0;
          _timerRunning = false;
          t.cancel();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('Pre-purge: czas minął.', 'Pre-purge: time is up.'))));
        } else {
          _remainingSeconds -= 1;
        }
      });
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    setState(() => _timerRunning = false);
  }

  void _resumeTimer() {
    if (_remainingSeconds <= 0) return;
    setState(() => _timerRunning = true);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_remainingSeconds <= 1) {
          _remainingSeconds = 0;
          _timerRunning = false;
          t.cancel();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr('Pre-purge: czas minął.', 'Pre-purge: time is up.'))));
        } else {
          _remainingSeconds -= 1;
        }
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    setState(() {
      _remainingSeconds = 0;
      _timerRunning = false;
    });
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

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  String _methodToDb(WeldingMethod m) {
    switch (m) {
      case WeldingMethod.tigWire:
        return 'TIG_WIRE';
      case WeldingMethod.tigNoWire:
        return 'TIG_AUTOGEN';
    }
  }

  String _methodLabelDb(String method) {
    switch (method) {
      case 'TIG_WIRE':
        return AppLanguageController.isEnglish ? 'TIG with filler' : 'TIG z drutem';
      case 'TIG_AUTOGEN':
        return AppLanguageController.isEnglish ? 'TIG without filler' : 'TIG bez drutu';
      default:
        return method;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dbMethod = _methodToDb(widget.methodGetter());

    return FutureBuilder<List<ApprovedWeldParam>>(
      future: _dao.listAll(method: dbMethod, material: _material),
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
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: _tr('Szukaj w zatwierdzonych AMP', 'Search approved AMP')),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (snap.connectionState != ConnectionState.done)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (snap.connectionState == ConnectionState.done && filtered.isEmpty)
              Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_tr('Brak zatwierdzonych parametrów dla tej metody.', 'No approved parameters for this method.')))),
            for (final p in filtered)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.verified),
                  title: Text('${_methodLabelDb(p.method)} | ${p.baseMaterial} | Ø${p.diameterMm.toStringAsFixed(1)} × t${p.wallThicknessMm.toStringAsFixed(2)}'),
                  subtitle: Text(
                    '${_tr('Elektroda', 'Electrode')}: ${p.electrodeMm.toStringAsFixed(1)} | ${_tr('Palnik', 'Torch')}: ${p.torchGasLpm.toStringAsFixed(1)} L/min | Purge: ${p.purgeLpm.toStringAsFixed(1)} L/min\n'
                    '${_tr('Ampery', 'Amps')}: ${p.amps.toStringAsFixed(0)} A'
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

class _TimerPanel extends StatelessWidget {
  final bool isRunning;
  final int remainingSeconds;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onStop;

  const _TimerPanel({
    required this.isRunning,
    required this.remainingSeconds,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final mm = (remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (remainingSeconds % 60).toString().padLeft(2, '0');

    return Row(
      children: [
        Expanded(
          child: Text(
            '${context.tr(pl: 'Minutnik', en: 'Timer')}: $mm:$ss',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: context.tr(pl: 'Pauza', en: 'Pause'),
          onPressed: onPause,
          icon: const Icon(Icons.pause),
        ),
        IconButton(
          tooltip: context.tr(pl: 'Wznów', en: 'Resume'),
          onPressed: onResume,
          icon: const Icon(Icons.play_arrow),
        ),
        IconButton(
          tooltip: context.tr(pl: 'Stop', en: 'Stop'),
          onPressed: onStop,
          icon: const Icon(Icons.stop),
        ),
      ],
    );
  }
}

class _ParamsLibraryTab extends StatefulWidget {
  final WeldingMethod Function() methodGetter;
  const _ParamsLibraryTab({required this.methodGetter});

  @override
  State<_ParamsLibraryTab> createState() => _ParamsLibraryTabState();
}

class _ParamsLibraryTabState extends State<_ParamsLibraryTab> {
  final _searchCtrl = TextEditingController();

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final method = widget.methodGetter();
    final q = _searchCtrl.text.trim().toLowerCase();

    // Placeholder list: you will add real records later.
    final all = <Map<String, String>>[
      {'title': _tr('Przykład - Ø60.3 t=2.0', 'Example - Ø60.3 t=2.0'), 'sub': _tr('A: 80-110 | gaz: 8-10 L/min | drut: 1.6', 'A: 80-110 | gas: 8-10 L/min | filler: 1.6')},
      {'title': _tr('Przykład - Ø114.3 t=3.0', 'Example - Ø114.3 t=3.0'), 'sub': _tr('A: 120-160 | gaz: 10-12 L/min | drut: 2.0', 'A: 120-160 | gas: 10-12 L/min | filler: 2.0')},
    ];

    final filtered = all.where((e) => q.isEmpty || e['title']!.toLowerCase().contains(q) || e['sub']!.toLowerCase().contains(q)).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            labelText: '${_tr('Szukaj parametrów', 'Search parameters')} (${_methodLabel(method)})',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_tr('Brak wyników (na razie to placeholder).', 'No results yet (placeholder for now).')))),
        for (final e in filtered)
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune),
              title: Text(e['title'] ?? ''),
              subtitle: Text(e['sub'] ?? ''),
            ),
          ),
      ],
    );
  }

  String _methodLabel(WeldingMethod m) {
    switch (m) {
      case WeldingMethod.tigWire:
        return AppLanguageController.isEnglish ? 'TIG with filler' : 'TIG z drutem';
      case WeldingMethod.tigNoWire:
        return AppLanguageController.isEnglish ? 'TIG without filler' : 'TIG bez drutu';
    }
  }
}
