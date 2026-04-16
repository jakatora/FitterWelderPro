import 'package:flutter/material.dart';

import '../../../i18n/app_language.dart';
import '../../../database/tandem_amp_param_dao.dart';
import '../../../models/tandem_amp_param.dart';

class TandemMyParamsScreen extends StatefulWidget {
  final String position;
  const TandemMyParamsScreen({super.key, required this.position});

  @override
  State<TandemMyParamsScreen> createState() => _TandemMyParamsScreenState();
}

class _TandemMyParamsScreenState extends State<TandemMyParamsScreen> {
  final _dao = TandemAmpParamDao();

  Future<List<TandemAmpParam>> _load() => _dao.list(position: widget.position, approved: false);

  @override
  Widget build(BuildContext context) {
    final title = widget.position == 'VERTICAL'
        ? context.tr(pl: 'Tandem PION – Moje parametry', en: 'Tandem VERTICAL — My parameters')
        : context.tr(pl: 'Tandem POZIOM – Moje parametry', en: 'Tandem HORIZONTAL — My parameters');
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addEdit(),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<TandemAmpParam>>(
        future: _load(),
        builder: (context, snap) {
          final data = snap.data ?? const <TandemAmpParam>[];
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (data.isEmpty) {
            return Center(child: Text(context.tr(pl: 'Brak moich parametrów. Dodaj (+).', en: 'No saved parameters. Add (+).')));
          }
          return ListView.builder(
            itemCount: data.length,
            itemBuilder: (ctx, i) {
              final p = data[i];
              return ListTile(
                title: Text('${p.t1Mm.toStringAsFixed(0)}/${p.t2Mm.toStringAsFixed(0)} mm  •  ${p.insideAmps}/${p.outsideAmps} A'),
                subtitle: Text('${context.tr(pl: 'Tempo', en: 'Tempo')}: ${_tempoLabel(context, p.tempo)}${p.note != null ? "\n${p.note}" : ""}'),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _addEdit(existing: p)),
                    IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(p)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _tempoLabel(BuildContext context, String tempo) {
    switch (tempo) {
      case 'SLOW':
        return context.tr(pl: 'wolne', en: 'slow');
      case 'FAST':
        return context.tr(pl: 'szybkie', en: 'fast');
      case 'NORMAL':
      default:
        return context.tr(pl: 'normalne', en: 'normal');
    }
  }

  Future<void> _delete(TandemAmpParam p) async {
    final lang = context.language;
    String trL({required String pl, required String en}) => lang == AppLanguage.en ? en : pl;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(trL(pl: 'Usunąć?', en: 'Delete?')),
        content: Text(trL(pl: 'Usunąć ${p.t1Mm}/${p.t2Mm} mm  ${p.insideAmps}/${p.outsideAmps} A?', en: 'Delete ${p.t1Mm}/${p.t2Mm} mm  ${p.insideAmps}/${p.outsideAmps} A?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(trL(pl: 'Anuluj', en: 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(trL(pl: 'Usuń', en: 'Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    await _dao.deleteById(p.id);
    if (mounted) setState(() {});
  }

  Future<void> _addEdit({TandemAmpParam? existing}) async {
    final isEdit = existing != null;
    final formKey = GlobalKey<FormState>();

    final lang = context.language;
    String trL({required String pl, required String en}) => lang == AppLanguage.en ? en : pl;

    final t1Ctrl = TextEditingController(text: (existing?.t1Mm ?? 3).toString());
    final t2Ctrl = TextEditingController(text: (existing?.t2Mm ?? 3).toString());
    final inCtrl = TextEditingController(text: (existing?.insideAmps ?? 80).toString());
    final outCtrl = TextEditingController(text: (existing?.outsideAmps ?? 150).toString());
    String tempo = existing?.tempo ?? 'NORMAL';
    final noteCtrl = TextEditingController(text: existing?.note ?? '');

    String? vDouble(String? v) {
      final x = double.tryParse((v ?? '').replaceAll(',', '.'));
      if (x == null || x <= 0) return trL(pl: 'Wpisz > 0', en: 'Enter > 0');
      return null;
    }

    String? vInt(String? v) {
      final x = int.tryParse((v ?? '').trim());
      if (x == null || x <= 0) return trL(pl: 'Wpisz > 0', en: 'Enter > 0');
      return null;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? trL(pl: 'Edytuj', en: 'Edit') : trL(pl: 'Dodaj', en: 'Add')),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: TextFormField(controller: t1Ctrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: trL(pl: 't1 [mm]', en: 't1 [mm]')), validator: vDouble)),
                    const SizedBox(width: 12),
                    Expanded(child: TextFormField(controller: t2Ctrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: trL(pl: 't2 [mm]', en: 't2 [mm]')), validator: vDouble)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: TextFormField(controller: inCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: trL(pl: 'A wew', en: 'A in')), validator: vInt)),
                    const SizedBox(width: 12),
                    Expanded(child: TextFormField(controller: outCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: trL(pl: 'A zew', en: 'A out')), validator: vInt)),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: tempo,
                  items: [
                    DropdownMenuItem(value: 'SLOW', child: Text(trL(pl: 'wolne', en: 'slow'))),
                    DropdownMenuItem(value: 'NORMAL', child: Text(trL(pl: 'normalne', en: 'normal'))),
                    DropdownMenuItem(value: 'FAST', child: Text(trL(pl: 'szybkie', en: 'fast'))),
                  ],
                  onChanged: (v) => tempo = v ?? 'NORMAL',
                  decoration: InputDecoration(labelText: trL(pl: 'Tempo', en: 'Tempo')),
                ),
                const SizedBox(height: 10),
                TextFormField(controller: noteCtrl, decoration: InputDecoration(labelText: trL(pl: 'Notatka (opcjonalnie)', en: 'Note (optional)'))),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(trL(pl: 'Anuluj', en: 'Cancel'))),
          FilledButton(onPressed: () {
            if (!(formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(ctx, true);
          }, child: Text(trL(pl: 'Zapisz', en: 'Save'))),
        ],
      ),
    );

    if (ok != true) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final p = TandemAmpParam(
      id: existing?.id ?? now.toString(),
      position: widget.position,
      t1Mm: double.parse(t1Ctrl.text.replaceAll(',', '.')),
      t2Mm: double.parse(t2Ctrl.text.replaceAll(',', '.')),
      insideAmps: int.parse(inCtrl.text.trim()),
      outsideAmps: int.parse(outCtrl.text.trim()),
      tempo: tempo,
      approved: false,
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    await _dao.insert(p);
    if (mounted) setState(() {});
  }
}
