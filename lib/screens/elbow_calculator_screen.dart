import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
class ElbowCalculatorScreen extends StatefulWidget {
  const ElbowCalculatorScreen({super.key});

  @override
  State<ElbowCalculatorScreen> createState() => _ElbowCalculatorScreenState();
}

class _ElbowCalculatorScreenState extends State<ElbowCalculatorScreen> {
  String _selectedAngle = '90';
  final _customAngleController = TextEditingController();

  final _odController = TextEditingController();
  final _clrController = TextEditingController();

  final _shortMarkController = TextEditingController();
  final _longMarkController = TextEditingController();
  final _deltaController = TextEditingController();

  double _parse(String v) => double.tryParse(v.replaceAll(',', '.')) ?? 0;

  void _calculate() {
    final od = _parse(_odController.text);
    final r = _parse(_clrController.text);

    final angleDeg = _selectedAngle == 'custom'
        ? _parse(_customAngleController.text)
        : _parse(_selectedAngle);

    if (od <= 0 || r <= 0 || angleDeg <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(pl: 'Wpisz OD, R (CLR) oraz kąt > 0', en: 'Enter OD, R (CLR) and an angle > 0'),
          ),
        ),
      );
      return;
    }

    final theta = angleDeg * math.pi / 180.0;
    final shortMark = theta * (r - od / 2.0);
    final longMark = theta * (r + od / 2.0);
    final delta = longMark - shortMark; // = θ_rad * OD

    _shortMarkController.text = shortMark.toStringAsFixed(1);
    _longMarkController.text = longMark.toStringAsFixed(1);
    _deltaController.text = delta.toStringAsFixed(1);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr(pl: 'Obliczono wymiary do zaznaczenia.', en: 'Marking dimensions calculated.'))),
    );
  }

  @override
  void dispose() {
    _customAngleController.dispose();
    _odController.dispose();
    _clrController.dispose();
    _shortMarkController.dispose();
    _longMarkController.dispose();
    _deltaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Cięcie kolanka – znaczniki', en: 'Elbow cut – markings')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr(pl: 'Docelowy kąt kolana (θ)', en: 'Target elbow angle (θ)'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildAngleButton('90', '90°'),
                const SizedBox(width: 8),
                _buildAngleButton('45', '45°'),
                const SizedBox(width: 8),
                _buildAngleButton('custom', context.tr(pl: 'Inny', en: 'Custom')),
              ],
            ),
            if (_selectedAngle == 'custom') ...[
              const SizedBox(height: 16),
              TextField(
                controller: _customAngleController,
                decoration: InputDecoration(
                  labelText: context.tr(pl: 'Kąt θ (stopnie)', en: 'Angle θ (degrees)'),
                  suffixText: '°',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
            const SizedBox(height: 24),

            TextField(
              controller: _odController,
              decoration: InputDecoration(
                labelText: context.tr(pl: 'OD rury (średnica zewnętrzna)', en: 'Pipe OD (outside diameter)'),
                suffixText: 'mm',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _clrController,
              decoration: InputDecoration(
                labelText: context.tr(pl: 'R (CLR) – promień do osi kolanka', en: 'R (CLR) – radius to elbow centerline'),
                helperText: context.tr(
                  pl: 'Jeśli nie wiesz: wpisz promień z tabeli kolanka (center-to-center).',
                  en: "If you don't know: use the elbow table radius (center-to-center).",
                ),
                suffixText: 'mm',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _calculate,
                icon: const Icon(Icons.calculate),
                label: Text(context.tr(pl: 'OBLICZ', en: 'CALCULATE')),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),

            const SizedBox(height: 24),
            Text(
              context.tr(pl: 'WYNIKI (do zaznaczenia)', en: 'RESULTS (markings)'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _shortMarkController,
              decoration: InputDecoration(
                labelText: context.tr(
                  pl: 'Krótszy bok (intrados) – zaznacz od czoła',
                  en: 'Short side (intrados) – mark from the face',
                ),
                suffixText: 'mm',
                border: const OutlineInputBorder(),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _longMarkController,
              decoration: InputDecoration(
                labelText: context.tr(
                  pl: 'Dłuższy bok (extrados) – zaznacz od czoła',
                  en: 'Long side (extrados) – mark from the face',
                ),
                suffixText: 'mm',
                border: const OutlineInputBorder(),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _deltaController,
              decoration: InputDecoration(
                labelText: context.tr(pl: 'Różnica długi-krótki (kontrola)', en: 'Long-short difference (check)'),
                suffixText: 'mm',
                border: const OutlineInputBorder(),
              ),
              readOnly: true,
            ),

            const SizedBox(height: 12),
            Text(
              context.tr(
                pl: 'Jak użyć: zaznacz wymiar na krótkim i długim boku kolanka, połącz punkty i tnij po linii.',
                en: 'How to use: mark both dimensions, connect the points and cut along the line.',
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAngleButton(String value, String label) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selectedAngle == value;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _selectedAngle = value);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? cs.primaryContainer : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? cs.primary : cs.outlineVariant,
              width: 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
