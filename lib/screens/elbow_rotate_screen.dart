import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../widgets/nps_table_sheet.dart';

class ElbowRotateScreen extends StatefulWidget {
  const ElbowRotateScreen({super.key});

  @override
  State<ElbowRotateScreen> createState() => _ElbowRotateScreenState();
}

class _ElbowRotateScreenState extends State<ElbowRotateScreen> {
  final _circCtrl = TextEditingController();
  final _degCtrl = TextEditingController();
  double? _mm;

  double _parse(String s) => double.tryParse(s.replaceAll(',', '.')) ?? 0;

  void _calc() {
    final c = _parse(_circCtrl.text);
    final d = _parse(_degCtrl.text);
    if (c <= 0 || d <= 0) {
      setState(() => _mm = null);
      return;
    }
    setState(() => _mm = (c * d) / 360.0);
  }

  @override
  void dispose() {
    _circCtrl.dispose();
    _degCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Obrót kolanka', en: 'Elbow rotation')),
        actions: [
          IconButton(
            tooltip: context.tr(pl: 'Tabela DN-MM', en: 'DN-MM table'),
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: () => NpsTableSheet.open(context),
          ),
        ],
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
                  Text(
                    context.tr(pl: 'Wejście', en: 'Input'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _circCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.tr(pl: 'Obwód rury na wylocie kolanka', en: 'Pipe circumference at elbow outlet'),
                      helperText: context.tr(
                        pl: 'Zmierz po zewnętrznej stronie otworu wylotowego.',
                        en: 'Measure on the outside edge of the outlet.',
                      ),
                      suffixText: 'mm',
                    ),
                    onChanged: (_) => _calc(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _degCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.tr(pl: 'Stopnie obrotu', en: 'Rotation degrees'),
                      suffixText: '°',
                    ),
                    onChanged: (_) => _calc(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_mm != null)
            Card(
              child: ListTile(
                title: Text(
                  context.tr(
                    pl: 'Odmierz na obwodzie: ${_mm!.toStringAsFixed(1)} mm',
                    en: 'Mark on circumference: ${_mm!.toStringAsFixed(1)} mm',
                  ),
                ),
                subtitle: Text(
                  context.tr(
                    pl: 'Zaznacz na obwodzie i obróć kolanko o tę wartość.',
                    en: 'Mark it and rotate the elbow by that amount.',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
