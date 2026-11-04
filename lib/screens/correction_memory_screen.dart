import 'package:flutter/material.dart';

import '../assistant/correction_memory.dart';
import '../i18n/app_language.dart';
import '../services/account_service.dart';

/// Local, account-scoped memory; never changes a technical fact for others.
class CorrectionMemoryScreen extends StatefulWidget {
  const CorrectionMemoryScreen({super.key, this.store});
  final CorrectionMemoryStore? store;

  @override
  State<CorrectionMemoryScreen> createState() => _CorrectionMemoryScreenState();
}

class _CorrectionMemoryScreenState extends State<CorrectionMemoryScreen> {
  late final _store = widget.store ?? CorrectionMemoryStore.instance;
  late AccountService _account = AccountService.instance;
  int _epoch = 0;
  bool _busy = true;
  bool _failed = false;
  List<RememberedCorrection> _records = const [];

  @override
  void initState() {
    super.initState();
    _account.addListener(_accountChanged);
    _reload();
  }

  void _accountChanged() {
    if (!mounted) return;
    setState(() {
      _records = const [];
      _busy = true;
      _failed = false;
    });
    _reload();
  }

  bool _syncAccount() {
    final current = AccountService.instance;
    if (identical(_account, current)) return false;
    _account.removeListener(_accountChanged);
    _account = current;
    _account.addListener(_accountChanged);
    _accountChanged();
    return true;
  }

  Future<void> _reload() async {
    final epoch = ++_epoch;
    try {
      final records = await _store.list();
      if (!mounted || epoch != _epoch || _syncAccount()) return;
      setState(() {
        _records = records;
        _busy = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || epoch != _epoch || _syncAccount()) return;
      setState(() {
        _records = const [];
        _busy = false;
        _failed = true;
      });
    }
  }

  Future<void> _forget(RememberedCorrection record) async {
    if (_syncAccount() || _busy) return;
    final epoch = _epoch;
    setState(() => _busy = true);
    try {
      await _store.forget(record);
      if (!mounted || epoch != _epoch || _syncAccount()) return;
      await _reload();
    } catch (_) {
      if (!mounted || epoch != _epoch || _syncAccount()) return;
      setState(() {
        _records = const [];
        _busy = false;
        _failed = true;
      });
    }
  }

  Future<void> _clearAll() async {
    if (_syncAccount() || _busy || _records.isEmpty) return;
    final epoch = _epoch;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr(
            pl: 'Usunąć wszystkie poprawki?', en: 'Delete all corrections?')),
        content: Text(context.tr(
          pl: 'Usuniesz pamięć asystenta dla bieżącego konta na tym urządzeniu.',
          en: 'This deletes assistant memory for the current account on this device.',
        )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.tr(pl: 'Anuluj', en: 'Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.tr(pl: 'Usuń wszystko', en: 'Delete all'))),
        ],
      ),
    );
    // A confirmation given for one account must never clear another account.
    if (confirmed != true ||
        !mounted ||
        epoch != _epoch ||
        _syncAccount() ||
        _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _store.clear();
      if (!mounted || epoch != _epoch || _syncAccount()) return;
      await _reload();
    } catch (_) {
      if (!mounted || epoch != _epoch || _syncAccount()) return;
      setState(() {
        _records = const [];
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  void dispose() {
    _epoch++;
    _account.removeListener(_accountChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(
                context.tr(pl: 'Pamięć asystenta', en: 'Assistant memory'))),
        body: _busy
            ? const Center(child: CircularProgressIndicator())
            : _failed
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(context.tr(
                        pl: 'Nie udało się odczytać lub zmienić pamięci.',
                        en: 'Could not read or change memory.')),
                    TextButton(
                        onPressed: () {
                          setState(() => _busy = true);
                          _reload();
                        },
                        child: Text(
                            context.tr(pl: 'Spróbuj ponownie', en: 'Retry'))),
                  ]))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(context.tr(
                          pl: 'Asystent może zapamiętać doprecyzowanie na tym urządzeniu, oddzielnie dla każdego konta. Przy podobnym pytaniu może wysłać je jako kontekst do AI. Możesz usunąć dowolny wpis.',
                          en: 'The assistant may save a clarification on this device separately for each account. It may send it as AI context for a related question. You can delete any entry.')),
                      const SizedBox(height: 16),
                      if (_records.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _clearAll,
                            icon: const Icon(Icons.delete_sweep_outlined),
                            label: Text(context.tr(
                                pl: 'Wyczyść pamięć', en: 'Clear memory')),
                          ),
                        ),
                      if (_records.isEmpty)
                        Text(context.tr(
                            pl: 'Brak zapamiętanych poprawek.',
                            en: 'No corrections saved.')),
                      for (final record in _records)
                        Card(
                            child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(context.tr(pl: 'Pytanie', en: 'Question'),
                                    style:
                                        Theme.of(context).textTheme.labelLarge),
                                SelectableText(record.question),
                                const SizedBox(height: 8),
                                Text(
                                    context.tr(
                                        pl: 'Poprawka', en: 'Correction'),
                                    style:
                                        Theme.of(context).textTheme.labelLarge),
                                SelectableText(record.correction),
                                Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                        onPressed: () => _forget(record),
                                        icon: const Icon(Icons.delete_outline),
                                        label: Text(context.tr(
                                            pl: 'Usuń poprawkę',
                                            en: 'Delete correction')))),
                              ]),
                        )),
                    ],
                  ),
      );
}
