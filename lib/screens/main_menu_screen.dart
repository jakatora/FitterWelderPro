import 'package:flutter/material.dart';

import '../i18n/app_language.dart';

import 'welder_pipes_screen.dart';
import 'welder_tanks_screen.dart';

class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Fitter Welder Pro', en: 'Fitter Welder Pro')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const SizedBox(height: 8),
            Text(
              context.tr(pl: 'Menu główne', en: 'Main menu'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _MenuTile(
              title: context.tr(pl: 'Moduł spawacza', en: 'Welder module'),
              subtitle: context.tr(pl: 'Pipes / Tanks', en: 'Pipes / Tanks'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WelderModuleScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class WelderModuleScreen extends StatelessWidget {
  const WelderModuleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr(pl: 'Moduł spawacza', en: 'Welder module'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            _MenuTile(
              title: context.tr(pl: 'Rury', en: 'Pipes'),
              subtitle: context.tr(pl: 'AMP, Purge, parametry', en: 'AMP, purge, parameters'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WelderPipesScreen())),
            ),
            _MenuTile(
              title: context.tr(pl: 'Zbiorniki', en: 'Tanks'),
              subtitle: context.tr(pl: 'Tandem TIG (2 osoby)', en: 'Tandem TIG (2 people)'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WelderTanksScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
