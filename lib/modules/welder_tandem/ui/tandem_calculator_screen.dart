import 'package:flutter/material.dart';

import '../../../i18n/app_language.dart';
import '../../../widgets/help_button.dart';
import '../../../database/tandem_amp_param_dao.dart';
import '../../../models/tandem_amp_param.dart';
import '../tandem_calc.dart';

class TandemCalculatorScreen extends StatefulWidget {
  final String position; // HORIZONTAL/VERTICAL
  const TandemCalculatorScreen({super.key, required this.position});

  @override
  State<TandemCalculatorScreen> createState() => _TandemCalculatorScreenState();
}

class _TandemCalculatorScreenState extends State<TandemCalculatorScreen> {
  final _dao = TandemAmpParamDao();
  late final TandemCalculator _calc = TandemCalculator(_dao);

  final _t1Ctrl = TextEditingController(text: '3');
  final _t2Ctrl = TextEditingController(text: '3');

  String _tempo = 'NORMAL';   // SLOW/NORMAL/FAST
  bool _saving = false;

  double _parse(String s) => double.tryParse(s.replaceAll(',', '.')) ?? 0;

  @override
  void dispose() {
    _t1Ctrl.dispose();
    _t2Ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.position == 'VERTICAL'
        ? context.tr(pl: 'Tandem PION – Kalkulator', en: 'Tandem VERTICAL — Calculator')
        : context.tr(pl: 'Tandem POZIOM – Kalkulator', en: 'Tandem HORIZONTAL — Calculator');
    final t1 = _parse(_t1Ctrl.text);
    final t2 = _parse(_t2Ctrl.text);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [HelpButton(help: kHelpTandemCalc)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr(pl: 'Wejście', en: 'Input'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _t1Ctrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: context.tr(pl: 'Ścianka t1 [mm]', en: 'Wall t1 [mm]')),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _t2Ctrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: context.tr(pl: 'Ścianka t2 [mm]', en: 'Wall t2 [mm]')),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('tempo_$_tempo'),
                    initialValue: _tempo,
                    items: [
                      DropdownMenuItem(value: 'SLOW', child: Text(context.tr(pl: 'wolne', en: 'slow'))),
                      DropdownMenuItem(value: 'NORMAL', child: Text(context.tr(pl: 'normalne', en: 'normal'))),
                      DropdownMenuItem(value: 'FAST', child: Text(context.tr(pl: 'szybkie', en: 'fast'))),
                    ],
                    onChanged: _saving ? null : (v) => setState(() => _tempo = v ?? 'NORMAL'),
                    decoration: InputDecoration(labelText: context.tr(pl: 'Tempo', en: 'Tempo')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<TandemCalcResult>(
            future: (t1 > 0 && t2 > 0)
                ? _calc.calculate(position: widget.position, t1Mm: t1, t2Mm: t2, tempo: _tempo)
                : Future.value(TandemCalcResult(
                    insideA: 0,
                    outsideA: 0,
                    status: '—',
                    note: context.tr(pl: 'Wpisz t1 i t2 > 0', en: 'Enter t1 and t2 > 0'),
                  )),
            builder: (context, snap) {
              final res = snap.data;
              if (res == null) {
                return Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(context.tr(pl: 'Liczenie...', en: 'Calculating...'))));
              }
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(context.tr(pl: 'Wynik', en: 'Result'), style: const TextStyle(fontWeight: FontWeight.w700)),
                          const Spacer(),
                          _Badge(text: res.status),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(context.tr(pl: 'Wewnętrzny (bez drutu): ${res.insideA} A', en: 'Inside (no wire): ${res.insideA} A')),
                      Text(context.tr(pl: 'Zewnętrzny (z drutem): ${res.outsideA} A', en: 'Outside (with wire): ${res.outsideA} A')),
                      const SizedBox(height: 8),
                      Text(res.note, style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 10),
                      if (res.status == 'ESTIMATE')
                        FilledButton.icon(
                          onPressed: _saving ? null : () => _saveMy(res, t1, t2),
                          icon: const Icon(Icons.save_outlined),
                          label: Text(context.tr(pl: 'Zapisz do moich parametrów', en: 'Save to my parameters')),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _saveMy(TandemCalcResult res, double t1, double t2) async {
    final messenger = ScaffoldMessenger.of(context);
    final lang = context.language;
    String trL({required String pl, required String en}) => lang == AppLanguage.en ? en : pl;

    setState(() => _saving = true);
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final p = TandemAmpParam(
        id: now.toString(),
        position: widget.position,
        t1Mm: t1,
        t2Mm: t2,
        insideAmps: res.insideA,
        outsideAmps: res.outsideA,
        tempo: _tempo,
        approved: false,
        note: trL(pl: 'Zapisane z kalkulatora (estymata)', en: 'Saved from calculator (estimate)'),
        createdAt: now,
        updatedAt: now,
      );
      await _dao.insert(p);
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(trL(pl: 'Zapisano do moich parametrów.', en: 'Saved to my parameters.'))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}
