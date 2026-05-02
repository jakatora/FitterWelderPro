import 'package:flutter/material.dart';

import '../../../i18n/app_language.dart';
import '../../../widgets/help_button.dart';
import '../../../database/tandem_amp_param_dao.dart';
import '../../../models/tandem_amp_param.dart';

class TandemLibraryScreen extends StatefulWidget {
  final String position;
  const TandemLibraryScreen({super.key, required this.position});

  @override
  State<TandemLibraryScreen> createState() => _TandemLibraryScreenState();
}

class _TandemLibraryScreenState extends State<TandemLibraryScreen> {
  final _dao = TandemAmpParamDao();

  String? _tempo; // filter

  Future<List<TandemAmpParam>> _load() => _dao.list(position: widget.position, approved: true, tempo: _tempo);

  @override
  Widget build(BuildContext context) {
    final title = widget.position == 'VERTICAL'
        ? context.tr(pl: 'Tandem PION – Biblioteka', en: 'Tandem VERTICAL — Library')
        : context.tr(pl: 'Tandem POZIOM – Biblioteka', en: 'Tandem HORIZONTAL — Library');
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [HelpButton(help: kHelpTandemLibrary)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String>(
              key: ValueKey('tempo_${_tempo ?? "ALL"}'),
              initialValue: _tempo,
              items: [
                DropdownMenuItem(value: null, child: Text(context.tr(pl: 'Tempo: wszystkie', en: 'Tempo: all'))),
                DropdownMenuItem(value: 'SLOW', child: Text(context.tr(pl: 'wolne', en: 'slow'))),
                DropdownMenuItem(value: 'NORMAL', child: Text(context.tr(pl: 'normalne', en: 'normal'))),
                DropdownMenuItem(value: 'FAST', child: Text(context.tr(pl: 'szybkie', en: 'fast'))),
              ],
              onChanged: (v) => setState(() => _tempo = v),
              decoration: InputDecoration(labelText: context.tr(pl: 'Tempo', en: 'Tempo')),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<TandemAmpParam>>(
              future: _load(),
              builder: (context, snap) {
                final data = snap.data ?? const <TandemAmpParam>[];
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (data.isEmpty) {
                  return Center(child: Text(context.tr(pl: 'Brak rekordów w bibliotece dla tych filtrów.', en: 'No records in the library for these filters.')));
                }
                return ListView.builder(
                  itemCount: data.length,
                  itemBuilder: (ctx, i) {
                    final p = data[i];
                    return ListTile(
                      title: Text('${p.t1Mm.toStringAsFixed(0)}/${p.t2Mm.toStringAsFixed(0)} mm  •  ${p.insideAmps}/${p.outsideAmps} A'),
                      subtitle: Text('${context.tr(pl: 'Tempo', en: 'Tempo')}: ${_tempoLabel(context, p.tempo)}'),
                    );
                  },
                );
              },
            ),
          ),
        ],
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
}
