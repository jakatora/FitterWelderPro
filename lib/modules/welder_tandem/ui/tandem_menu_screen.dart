import 'package:flutter/material.dart';

import '../../../i18n/app_language.dart';
import 'tandem_calculator_screen.dart';
import 'tandem_library_screen.dart';
import 'tandem_my_params_screen.dart';

class TandemMenuScreen extends StatelessWidget {
  final String position; // 'HORIZONTAL' | 'VERTICAL'
  const TandemMenuScreen({super.key, required this.position});

  String _posName(BuildContext context) {
    return position == 'VERTICAL'
        ? context.tr(pl: 'Tandem PION', en: 'Tandem VERTICAL')
        : context.tr(pl: 'Tandem POZIOM', en: 'Tandem HORIZONTAL');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_posName(context))),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width >= 800 ? 3 : 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.1,
          children: [
            _Tile(
              icon: Icons.calculate_outlined,
              title: context.tr(pl: 'Kalkulator', en: 'Calculator'),
              subtitle: context.tr(pl: 'Dobór A (wew/zew)', en: 'Pick A (in/out)'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TandemCalculatorScreen(position: position))),
            ),
            _Tile(
              icon: Icons.library_books_outlined,
              title: context.tr(pl: 'Biblioteka', en: 'Library'),
              subtitle: context.tr(pl: 'Zatwierdzone AMP', en: 'Approved AMP'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TandemLibraryScreen(position: position))),
            ),
            _Tile(
              icon: Icons.person_outline,
              title: context.tr(pl: 'Moje parametry', en: 'My parameters'),
              subtitle: context.tr(pl: 'Dodaj/edytuj', en: 'Add/edit'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TandemMyParamsScreen(position: position))),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Tile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 44),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
