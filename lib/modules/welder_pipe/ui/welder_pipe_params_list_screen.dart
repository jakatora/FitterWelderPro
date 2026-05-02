import 'package:flutter/material.dart';

import '../../../i18n/app_language.dart';
import '../../../widgets/help_button.dart';

import '../local_repo.dart';
import '../welder_pipe_param.dart';
import 'welder_pipe_param_edit_screen.dart';

class WelderPipeParamsListScreen extends StatefulWidget {
  const WelderPipeParamsListScreen({super.key});

  @override
  State<WelderPipeParamsListScreen> createState() =>
      _WelderPipeParamsListScreenState();
}

class _WelderPipeParamsListScreenState extends State<WelderPipeParamsListScreen> {
  final _repo = WelderPipeLocalRepo();

  bool _loading = true;
  List<WelderPipeParam> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(ScaffoldMessengerState messenger, String t) {
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _load() async {
    final messenger = ScaffoldMessenger.of(context);
    final lang = context.language;
    String trL({required String pl, required String en}) => lang == AppLanguage.en ? en : pl;

    setState(() => _loading = true);
    try {
      final list = await _repo.listMyParams();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(messenger, trL(pl: 'Nie udało się wczytać parametrów.', en: 'Failed to load parameters.'));
    }
  }

  Future<void> _add() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const WelderPipeParamEditScreen()),
    );
    if (ok == true) _load();
  }

  Future<void> _edit(WelderPipeParam p) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => WelderPipeParamEditScreen(existing: p)),
    );
    if (ok == true) _load();
  }

  Future<void> _delete(WelderPipeParam p) async {
    final messenger = ScaffoldMessenger.of(context);
    final lang = context.language;
    String trL({required String pl, required String en}) => lang == AppLanguage.en ? en : pl;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(trL(pl: 'Usunąć zestaw?', en: 'Delete set?')),
        content: Text(trL(pl: 'Usunąć „${p.material} ${p.odMm}x${p.wtMm}”?', en: 'Delete “${p.material} ${p.odMm}x${p.wtMm}”?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(trL(pl: 'Anuluj', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(trL(pl: 'Usuń', en: 'Delete')),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _repo.deleteMyParam(p.id!);
      _snack(messenger, trL(pl: 'Usunięto.', en: 'Deleted.'));
      _load();
    } catch (_) {
      _snack(messenger, trL(pl: 'Nie udało się usunąć.', en: 'Failed to delete.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.language;
    String trL({required String pl, required String en}) => lang == AppLanguage.en ? en : pl;

    return Scaffold(
      appBar: AppBar(
        title: Text(trL(pl: 'Moje parametry – Welder (Rury)', en: 'My parameters — Welder (Pipes)')),
        actions: [HelpButton(help: kHelpWelderPipeParams)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(trL(pl: 'Dodaj', en: 'Add')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Text(trL(pl: 'Brak parametrów. Dodaj pierwszy zestaw.', en: 'No parameters yet. Add your first set.')),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final p = _items[i];
                        final subtitle = [
                          '${p.odMm} x ${p.wtMm} mm',
                          '${trL(pl: 'AMP', en: 'AMP')}: ${p.amps}',
                          p.method == 'WTC' ? 'Walking the Cup' : 'Free Hand',
                          '${trL(pl: 'Porc.', en: 'Cup')}: ${p.cupSize}',
                          '${trL(pl: 'Elekt.', en: 'Electrode')}: ${p.electrodeMm}',
                          '${trL(pl: 'Otwory', en: 'Outlets')}: ${p.outletHolesCount}',
                          '${trL(pl: 'Tempo', en: 'Tempo')}: ${p.weldTempo}',
                          p.wireEnabled ? trL(pl: 'Drut: ${p.wireMm} mm', en: 'Wire: ${p.wireMm} mm') : trL(pl: 'Bez drutu', en: 'No wire'),
                          p.purgeEnabled
                              ? trL(pl: 'Gaz: ${p.purgeFlowLpm ?? '-'} L/min', en: 'Gas: ${p.purgeFlowLpm ?? '-'} L/min')
                              : trL(pl: 'Bez gazu w rurze', en: 'No purge gas'),
                        ].join(' • ');

                        return Card(
                          child: ListTile(
                            leading:
                                const Icon(Icons.local_fire_department_outlined),
                            title: Text(p.material),
                            subtitle: Text(subtitle),
                            onTap: () => _edit(p),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(p),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
