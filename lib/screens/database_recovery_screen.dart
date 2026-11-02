import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../data/database_location_problem.dart';

/// Lets the user explicitly choose a database; no database is copied/deleted.
class DatabaseRecoveryScreen extends StatefulWidget {
  const DatabaseRecoveryScreen({
    super.key,
    required this.problem,
    required this.onSelect,
    this.pickFile,
  });

  final DatabaseLocationProblem problem;
  final Future<void> Function(String path, List<String> candidates) onSelect;
  final Future<String?> Function()? pickFile;

  @override
  State<DatabaseRecoveryScreen> createState() => _DatabaseRecoveryScreenState();
}

class _DatabaseRecoveryScreenState extends State<DatabaseRecoveryScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _browse() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = widget.pickFile != null
          ? await widget.pickFile!()
          : (await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['db'],
            ))
              ?.files
              .single
              .path;
      if (path == null || !mounted) return;
      if (p.basename(path).toLowerCase() != 'cutlist.db') {
        setState(() =>
            _error = 'Wybierz plik cutlist.db. / Select the cutlist.db file.');
        return;
      }
      setState(() => _busy = false);
      await _choose(p.dirname(path));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(String path) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wybrać tę bazę? / Select this database?'),
        content: SingleChildScrollView(
          child: SelectableText(
            '$path\n\nPozostałe bazy zostaną zachowane. Projekty z różnych baz '
            'nie zostaną połączone.\n\nThe other databases will be kept. '
            'Projects from different databases will not be merged.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Anuluj / Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Wybierz / Select')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final candidates = [...widget.problem.candidates];
      if (!candidates.any((candidate) => p.equals(candidate, path))) {
        candidates.add(path);
      }
      await widget.onSelect(path, candidates);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('FitterWelder Pro')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Wybierz bazę projektów / Select your project database',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            if (widget.problem.reason != null) ...[
              SelectableText(widget.problem.reason!),
              const SizedBox(height: 12),
            ],
            const Text('Wybierz lokalizację danych, której chcesz używać. '
                'Nie usuwamy pozostałych baz.\n\nChoose the data location to use. '
                'The other databases will be kept.'),
            if (widget.problem.missing != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                  'Niedostępna poprzednia lokalizacja / Previous location unavailable:\n${widget.problem.missing}'),
            ],
            for (final path in widget.problem.candidates) ...[
              const SizedBox(height: 16),
              SelectableText(path),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : () => _choose(path),
                child: const Text('Użyj tej bazy / Use this database'),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _busy ? null : _browse,
              child: const Text('Znajdź plik bazy / Find database file'),
            ),
            if (widget.problem.candidates.isEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                  'Wskaż plik cutlist.db albo przywróć dostęp do poprzedniego folderu. '
                  'Locate cutlist.db or restore access to the previous folder.'),
            ],
            if (_busy)
              const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: CircularProgressIndicator()),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: SelectableText(_error!)),
          ]),
        ),
      );
}
