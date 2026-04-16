import 'package:flutter/material.dart';

import '../../../i18n/app_language.dart';

import '../community_sync_service.dart';
import '../local_repo.dart';
import '../welder_pipe_param.dart';
import '../param_signature.dart';

enum WeldTempo { slow, normal, fast }

String tempoDb(WeldTempo t) {
  switch (t) {
    case WeldTempo.slow:
      return 'SLOW';
    case WeldTempo.normal:
      return 'NORMAL';
    case WeldTempo.fast:
      return 'FAST';
  }
}

WeldTempo dbToTempo(String? s) {
  switch ((s ?? 'NORMAL').toUpperCase()) {
    case 'SLOW':
      return WeldTempo.slow;
    case 'FAST':
      return WeldTempo.fast;
    default:
      return WeldTempo.normal;
  }
}

class WelderPipeParamEditScreen extends StatefulWidget {
  final WelderPipeParam? existing;
  const WelderPipeParamEditScreen({super.key, this.existing});

  @override
  State<WelderPipeParamEditScreen> createState() => _WelderPipeParamEditScreenState();
}

class _WelderPipeParamEditScreenState extends State<WelderPipeParamEditScreen> {
  final _formKey = GlobalKey<FormState>();

  final _repo = WelderPipeLocalRepo();
  final _sync = WelderPipeCommunitySyncService();

  bool _saving = false;
  bool _sendToCommunity = true;

  String _material = 'CARBON_STEEL';
  final _odCtrl = TextEditingController();
  final _wtCtrl = TextEditingController();

  final _ampsCtrl = TextEditingController();
  String _method = 'WTC';

  final _cupCtrl = TextEditingController();
  final _electrodeCtrl = TextEditingController();

  String _torchGas = 'ARGON';
  String _pipeGas = 'ARGON';

  bool _purgeEnabled = true;
  final _purgeFlowCtrl = TextEditingController();

  bool _wireEnabled = true;
  final _wireCtrl = TextEditingController();

  final _notesCtrl = TextEditingController();

  // NEW
  final _outletHolesCtrl = TextEditingController();
  WeldTempo _tempo = WeldTempo.normal;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _material = e.material;
      _odCtrl.text = e.odMm.toString();
      _wtCtrl.text = e.wtMm.toString();
      _ampsCtrl.text = e.amps.toString();
      _method = e.method;
      _cupCtrl.text = e.cupSize.toString();
      _electrodeCtrl.text = e.electrodeMm.toString();
      _torchGas = e.torchGas;
      _pipeGas = e.pipeGas;
      _purgeEnabled = e.purgeEnabled;
      _purgeFlowCtrl.text = e.purgeFlowLpm?.toString() ?? '';
      _wireEnabled = e.wireEnabled;
      _wireCtrl.text = e.wireMm?.toString() ?? '';
      _notesCtrl.text = e.notes ?? '';
      _outletHolesCtrl.text = e.outletHolesCount.toString();
      _tempo = dbToTempo(e.weldTempo);
    } else {
      _odCtrl.text = '60.3';
      _wtCtrl.text = '3.2';
      _ampsCtrl.text = '90';
      _cupCtrl.text = '8';
      _electrodeCtrl.text = '2.4';
      _purgeFlowCtrl.text = '6';
      _wireCtrl.text = '1.6';
      _outletHolesCtrl.text = '1';
      _tempo = WeldTempo.normal;
    }
  }

  @override
  void dispose() {
    _odCtrl.dispose();
    _wtCtrl.dispose();
    _ampsCtrl.dispose();
    _cupCtrl.dispose();
    _electrodeCtrl.dispose();
    _purgeFlowCtrl.dispose();
    _wireCtrl.dispose();
    _notesCtrl.dispose();
    _outletHolesCtrl.dispose();
    super.dispose();
  }

  void _snack(ScaffoldMessengerState messenger, String t) {
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(t)));
  }

  double _parse(String s) => double.parse(s.replaceAll(',', '.'));

  bool get _isCarbonSteel => _material.trim().toUpperCase() == 'CARBON_STEEL';

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final lang = context.language;
    String trL({required String pl, required String en}) => lang == AppLanguage.en ? en : pl;

    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final od = _parse(_odCtrl.text.trim());
      final wt = _parse(_wtCtrl.text.trim());
      final amps = _parse(_ampsCtrl.text.trim());
      final cup = _parse(_cupCtrl.text.trim());
      final electrode = _parse(_electrodeCtrl.text.trim());

      final purgeEnabled = _isCarbonSteel ? _purgeEnabled : true;
      final purgeFlow = purgeEnabled ? _parse(_purgeFlowCtrl.text.trim()) : null;

      final wireEnabled = _wireEnabled;
      final wireMm = wireEnabled ? _parse(_wireCtrl.text.trim()) : null;

      final payload = <String, dynamic>{
        'module': 'welder_pipe',
        'material': _material.trim().toUpperCase(),
        'od_mm': od,
        'wt_mm': wt,
        'amps': amps,
        'method': _method,
        'cup_size': cup,
        'electrode_mm': electrode,
        'torch_gas': _torchGas.trim().toUpperCase(),
        'pipe_gas': _pipeGas.trim().toUpperCase(),
        'purge_enabled': purgeEnabled,
        'purge_flow_lpm': purgeFlow,
        'wire_enabled': wireEnabled,
        'wire_mm': wireMm,
      };

      final sig = WelderPipeSignature.signature(payload);
      final now = DateTime.now();

      final param = WelderPipeParam(
        id: widget.existing?.id,
        material: payload['material'],
        odMm: od,
        wtMm: wt,
        amps: amps,
        method: _method,
        cupSize: cup,
        electrodeMm: electrode,
        torchGas: payload['torch_gas'] as String,
        pipeGas: payload['pipe_gas'] as String,
        outletHolesCount: int.tryParse(_outletHolesCtrl.text.trim()) ?? 1,
        weldTempo: tempoDb(_tempo),
        purgeEnabled: purgeEnabled,
        purgeFlowLpm: purgeFlow,
        wireEnabled: wireEnabled,
        wireMm: wireMm,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        signature: sig,
        createdAt: widget.existing?.createdAt ?? now,
        updatedAt: now,
      );

      await _repo.upsertMyParam(id: widget.existing?.id, param: param);

      if (_sendToCommunity) {
        await _sync.submitMyParamToCommunity(payload);
        await _sync.syncOutboxOnce();
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _snack(messenger, trL(pl: 'Nie udało się zapisać: $e', en: 'Failed to save: $e'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    final lang = context.language;
    String trL({required String pl, required String en}) => lang == AppLanguage.en ? en : pl;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? trL(pl: 'Edytuj parametry (rury)', en: 'Edit parameters (pipes)') : trL(pl: 'Dodaj parametry (rury)', en: 'Add parameters (pipes)'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('material_$_material'),
                initialValue: _material,
                items: [
                  DropdownMenuItem(value: 'CARBON_STEEL', child: Text(trL(pl: 'Czarna stal', en: 'Carbon steel'))),
                  DropdownMenuItem(value: 'SS316L', child: Text(trL(pl: 'Stal nierdzewna 316L', en: 'Stainless steel 316L'))),
                  const DropdownMenuItem(value: 'DUPLEX', child: Text('Duplex')),
                ],
                onChanged: _saving ? null : (v) => setState(() => _material = v ?? 'CARBON_STEEL'),
                decoration: InputDecoration(
                  labelText: trL(pl: 'Materiał', en: 'Material'),
                  prefixIcon: const Icon(Icons.category_outlined),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _odCtrl,
                      decoration: InputDecoration(labelText: trL(pl: 'Średnica OD (mm)', en: 'OD diameter (mm)'), prefixIcon: const Icon(Icons.straighten)),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => (v ?? '').trim().isEmpty ? trL(pl: 'Wymagane', en: 'Required') : null,
                      enabled: !_saving,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _wtCtrl,
                      decoration: InputDecoration(labelText: trL(pl: 'Ścianka WT (mm)', en: 'Wall WT (mm)'), prefixIcon: const Icon(Icons.straighten_outlined)),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => (v ?? '').trim().isEmpty ? trL(pl: 'Wymagane', en: 'Required') : null,
                      enabled: !_saving,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                key: ValueKey('method_$_method'),
                initialValue: _method,
                items: const [
                  DropdownMenuItem(value: 'WTC', child: Text('Walking the Cup')),
                  DropdownMenuItem(value: 'FREE_HAND', child: Text('Free Hand')),
                ],
                onChanged: _saving ? null : (v) => setState(() => _method = v ?? 'WTC'),
                decoration: InputDecoration(
                  labelText: trL(pl: 'Metoda', en: 'Method'),
                  prefixIcon: const Icon(Icons.handyman_outlined),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _ampsCtrl,
                decoration: const InputDecoration(labelText: 'AMP', prefixIcon: Icon(Icons.bolt_outlined)),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => (v ?? '').trim().isEmpty ? trL(pl: 'Wymagane', en: 'Required') : null,
                enabled: !_saving,
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cupCtrl,
                      decoration: InputDecoration(labelText: trL(pl: 'Porcelanka (rozmiar)', en: 'Cup (size)'), prefixIcon: const Icon(Icons.circle_outlined)),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => (v ?? '').trim().isEmpty ? trL(pl: 'Wymagane', en: 'Required') : null,
                      enabled: !_saving,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _electrodeCtrl,
                      decoration: InputDecoration(labelText: trL(pl: 'Elektroda (mm)', en: 'Electrode (mm)'), prefixIcon: const Icon(Icons.flash_on_outlined)),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => (v ?? '').trim().isEmpty ? trL(pl: 'Wymagane', en: 'Required') : null,
                      enabled: !_saving,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                key: ValueKey('torchGas_$_torchGas'),
                initialValue: _torchGas,
                items: const [
                  DropdownMenuItem(value: 'ARGON', child: Text('Argon')),
                  DropdownMenuItem(value: 'AR_HE', child: Text('Ar/He')),
                ],
                onChanged: _saving ? null : (v) => setState(() => _torchGas = v ?? 'ARGON'),
                decoration: InputDecoration(
                  labelText: trL(pl: 'Gaz na palnik', en: 'Torch gas'),
                  prefixIcon: const Icon(Icons.local_gas_station_outlined),
                ),
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                key: ValueKey('pipeGas_$_pipeGas'),
                initialValue: _pipeGas,
                items: const [
                  DropdownMenuItem(value: 'ARGON', child: Text('Argon')),
                  DropdownMenuItem(value: 'NITROGEN', child: Text('Nitrogen')),
                ],
                onChanged: _saving ? null : (v) => setState(() => _pipeGas = v ?? 'ARGON'),
                decoration: InputDecoration(
                  labelText: trL(pl: 'Gaz do rury', en: 'Pipe gas'),
                  prefixIcon: const Icon(Icons.air_outlined),
                ),
              ),
              const SizedBox(height: 12),

              if (_isCarbonSteel) ...[
                SwitchListTile(
                  value: _purgeEnabled,
                  onChanged: _saving ? null : (v) => setState(() => _purgeEnabled = v),
                  title: Text(trL(pl: 'Czarna stal: wpuszczasz gaz do środka?', en: 'Carbon steel: are you purging the inside?')),
                ),
                const SizedBox(height: 6),
              ],

              if (!_isCarbonSteel || _purgeEnabled) ...[
                TextFormField(
                  controller: _purgeFlowCtrl,
                  decoration: InputDecoration(
                    labelText: trL(pl: 'Ile gazu do rury (L/min)', en: 'Purge flow (L/min)'),
                    prefixIcon: const Icon(Icons.water_drop_outlined),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (_isCarbonSteel && !_purgeEnabled) return null;
                    return (v ?? '').trim().isEmpty ? trL(pl: 'Wymagane', en: 'Required') : null;
                  },
                  enabled: !_saving && (!_isCarbonSteel || _purgeEnabled),
                ),
                const SizedBox(height: 12),
              ],

              SwitchListTile(
                value: _wireEnabled,
                onChanged: _saving
                    ? null
                    : (v) {
                        setState(() {
                          _wireEnabled = v;
                          if (!v) _wireCtrl.text = '';
                        });
                      },
                title: Text(trL(pl: 'Spawasz z drutem?', en: 'Welding with wire?')),
                subtitle: Text(trL(pl: 'Wyłącz jeśli spawasz bez drutu', en: 'Turn off if you weld without wire')),
              ),

              if (_wireEnabled) ...[
                TextFormField(
                  controller: _wireCtrl,
                  decoration: InputDecoration(labelText: trL(pl: 'Drut (mm)', en: 'Wire (mm)'), prefixIcon: const Icon(Icons.linear_scale)),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) => _wireEnabled && (v ?? '').trim().isEmpty ? trL(pl: 'Wymagane', en: 'Required') : null,
                  enabled: !_saving,
                ),
                const SizedBox(height: 12),
              ],

              TextFormField(
                controller: _notesCtrl,
                decoration: InputDecoration(labelText: trL(pl: 'Notatki', en: 'Notes'), prefixIcon: const Icon(Icons.notes_outlined)),
                maxLines: 3,
                enabled: !_saving,
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _outletHolesCtrl,
                      decoration: InputDecoration(
                        labelText: trL(pl: 'Ilość otworów wylotowych', en: 'Outlet holes count'),
                        prefixIcon: const Icon(Icons.grid_3x3_outlined),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final x = int.tryParse((v ?? '').trim());
                        if (x == null || x <= 0) return trL(pl: 'Wpisz liczbę > 0', en: 'Enter a number > 0');
                        return null;
                      },
                      enabled: !_saving,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<WeldTempo>(
                      key: ValueKey('tempo_$_tempo'),
                      initialValue: _tempo,
                      items: [
                        DropdownMenuItem(value: WeldTempo.slow, child: Text(trL(pl: 'wolne', en: 'slow'))),
                        DropdownMenuItem(value: WeldTempo.normal, child: Text(trL(pl: 'normalne', en: 'normal'))),
                        DropdownMenuItem(value: WeldTempo.fast, child: Text(trL(pl: 'szybkie', en: 'fast'))),
                      ],
                      onChanged: _saving ? null : (v) => setState(() => _tempo = v ?? WeldTempo.normal),
                      decoration: InputDecoration(
                        labelText: trL(pl: 'Tempo spawania', en: 'Weld tempo'),
                        prefixIcon: const Icon(Icons.speed_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              SwitchListTile(
                value: _sendToCommunity,
                onChanged: _saving ? null : (v) => setState(() => _sendToCommunity = v),
                title: Text(trL(pl: 'Dodaj do puli 100/100 (społeczność)', en: 'Add to 100/100 pool (community)')),
                subtitle: Text(trL(pl: 'Jeśli 100 różnych osób doda identyczne – trafi do zatwierdzonych', en: 'If 100 different people add the same entry, it becomes approved')),
              ),
              const SizedBox(height: 12),

              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(trL(pl: 'Zapisz', en: 'Save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
