// Biblioteka WPS spawacza: lista, wyszukiwanie, import / eksport JSON jednej
// WPS (wymiana w brygadzie przez komunikator albo plik).
//
// To są WPS spawacza — wpisane z dokumentów jego zakładu. Nie mylić
// z zakładką „Zatwierdzone" w parametrach rur (dane startowe dostarczone
// z aplikacją, nie WPS zakładu).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../database/wps_dao.dart';
import '../../domain/qualification/weld_process.dart';
import '../../domain/welding/heat_input.dart';
import '../../domain/wps/wps_record.dart';
import '../../i18n/app_language.dart';
import '../../services/welder_qualification_service.dart';
import '../../theme/app_theme.dart';
import '../qualification/form_bits.dart';
import 'wps_edit_page.dart';

class WpsLibraryPage extends StatefulWidget {
  const WpsLibraryPage({super.key});

  @override
  State<WpsLibraryPage> createState() => _WpsLibraryPageState();
}

class _WpsLibraryPageState extends State<WpsLibraryPage> {
  final _dao = WpsDao();
  final _search = TextEditingController();
  List<WpsRecord> _all = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    List<WpsRecord> all = const [];
    var failed = false;
    try {
      all = await _dao.listAll();
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _all = all;
      _failed = failed;
      _loading = false;
    });
  }

  List<WpsRecord> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((w) {
      final hay = [
        w.wpsNo,
        w.revision,
        w.pqrRef,
        w.processes,
        w.materialGroup,
        w.filler,
        w.notes,
      ].join(' ').toLowerCase();
      return q.split(RegExp(r'\s+')).every(hay.contains);
    }).toList();
  }

  void _snack(String pl, String en) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.tr(pl: pl, en: en))));
  }

  Future<void> _openEditor([WpsRecord? wps]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => WpsEditPage(wps: wps)),
    );
    if (saved == true) await _load();
  }

  // ─── Import ───────────────────────────────────────────────────────────────

  Future<void> _importFromFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'txt'],
      withData: kIsWeb,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    String text;
    try {
      if (file.bytes != null) {
        // Bajty z pickera to UTF-8 — dekodujemy porządnie (polskie znaki).
        text = utf8.decode(file.bytes!, allowMalformed: true);
      } else if (file.path != null) {
        text = await File(file.path!).readAsString();
      } else {
        return;
      }
    } catch (_) {
      _snack('Nie udało się odczytać pliku.', 'Could not read the file.');
      return;
    }
    await _importText(text);
  }

  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      _snack('Schowek jest pusty.', 'The clipboard is empty.');
      return;
    }
    await _importText(text);
  }

  Future<void> _importText(String text) async {
    WpsRecord incoming;
    try {
      incoming = decodeWpsJson(text);
    } on WpsFormatException catch (e) {
      _snack(e.messagePl, e.messageEn);
      return;
    }
    final existing = await _dao.findByNumber(incoming.wpsNo,
        revision: incoming.revision);
    final now = DateTime.now().millisecondsSinceEpoch;
    var record = incoming.withIdentity(id: const Uuid().v4(), now: now);
    if (existing != null && existing.revision.trim() == incoming.revision.trim()) {
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: Text(context.tr(
              pl: 'Ta WPS już jest w bibliotece',
              en: 'This WPS is already in the library')),
          content: Text(context.tr(
            pl: '${existing.displayName} — zastąpić zapisaną wersję '
                'zaimportowaną, czy dodać jako kopię?',
            en: '${existing.displayName} — replace the saved one with the '
                'imported one, or add it as a copy?',
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dctx, 'copy'),
              child: Text(context.tr(pl: 'Dodaj kopię', en: 'Add a copy')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dctx, 'replace'),
              child: Text(context.tr(pl: 'Zastąp', en: 'Replace')),
            ),
          ],
        ),
      );
      if (choice == null) return;
      if (choice == 'replace') {
        // Ten sam wiersz: identyfikator, data dodania i załącznik zostają.
        record = WpsRecord.fromRow({
          ...incoming.toRow(),
          'id': existing.id,
          'attachment_path': existing.attachmentPath,
          'created_at': existing.createdAt,
          'updated_at': now,
        });
      }
    }
    try {
      await _dao.upsert(record);
    } catch (_) {
      _snack('Nie udało się zapisać WPS.', 'Could not save the WPS.');
      return;
    }
    _snack('Zaimportowano ${record.displayName}.',
        'Imported ${record.displayName}.');
    await _load();
  }

  // ─── Eksport ──────────────────────────────────────────────────────────────

  Future<void> _share(WpsRecord wps) async {
    final json = encodeWpsJson(wps, exportedAt: DateTime.now());
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: json));
      _snack('JSON WPS skopiowany do schowka.', 'WPS JSON copied.');
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, wpsExportFileName(wps)));
      await file.writeAsString(json, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'WPS ${wps.displayName}',
      );
    } catch (_) {
      _snack('Nie udało się udostępnić pliku.', 'Could not share the file.');
    }
  }

  Future<void> _copyJson(WpsRecord wps) async {
    await Clipboard.setData(
        ClipboardData(text: encodeWpsJson(wps, exportedAt: DateTime.now())));
    _snack('JSON WPS skopiowany — wklej go koledze w komunikatorze.',
        'WPS JSON copied — paste it to a colleague in a messenger.');
  }

  Future<void> _openAttachment(WpsRecord wps) async {
    final path = wps.attachmentPath;
    if (path == null || kIsWeb) return;
    if (!await File(path).exists()) {
      _snack('Plik WPS nie istnieje na tym telefonie.',
          'The WPS file is not on this phone.');
      return;
    }
    try {
      await Share.shareXFiles([XFile(path)], subject: 'WPS ${wps.displayName}');
    } catch (_) {
      _snack('Nie udało się otworzyć pliku.', 'Could not open the file.');
    }
  }

  Future<void> _delete(WpsRecord wps) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(context.tr(pl: 'Usunąć WPS?', en: 'Delete the WPS?')),
        content: Text(context.tr(
          pl: '${wps.displayName} zniknie z biblioteki. Spoiny w dzienniku, '
              'które ją wskazują, zachowają numer.',
          en: '${wps.displayName} will be removed from the library. Journal '
              'welds that refer to it keep the number.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kFail),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(context.tr(pl: 'Usuń', en: 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _dao.delete(wps.id);
    await WelderQualificationService.instance
        .deleteOwnedFile(wps.attachmentPath);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Biblioteka WPS', en: 'WPS library')),
        actions: [
          PopupMenuButton<String>(
            tooltip: context.tr(pl: 'Import', en: 'Import'),
            icon: const Icon(Icons.download_outlined),
            onSelected: (v) =>
                v == 'file' ? _importFromFile() : _importFromClipboard(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'file',
                child: Text(context.tr(
                    pl: 'Importuj z pliku JSON', en: 'Import from JSON file')),
              ),
              PopupMenuItem(
                value: 'clipboard',
                child: Text(context.tr(
                    pl: 'Wklej JSON ze schowka', en: 'Paste JSON from clipboard')),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _failed ? null : () => _openEditor(),
        icon: const Icon(Icons.add),
        label: Text(context.tr(pl: 'Dodaj WPS', en: 'Add WPS')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kArc))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Text(
                  context.tr(
                    pl: 'Twoje WPS przepisane z dokumentów zakładu: zakresy '
                        'parametrów, powiązany WPQR / PQR i plik WPS. '
                        'Udostępniaj pojedyncze WPS brygadzie jako JSON.',
                    en: 'Your WPSs copied from the company documents: '
                        'parameter ranges, the linked WPQR / PQR and the WPS '
                        'file. Share single WPSs with the crew as JSON.',
                  ),
                  style: const TextStyle(fontSize: 12, color: kTextSec),
                ),
                const SizedBox(height: 12),
                if (_failed)
                  Text(
                    context.tr(
                      pl: 'Nie udało się odczytać biblioteki z bazy.',
                      en: 'Could not read the library from the database.',
                    ),
                    style: const TextStyle(color: kFail),
                  ),
                if (_all.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: context.tr(
                            pl: 'Szukaj: numer, proces, grupa…',
                            en: 'Search: number, process, group…'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                if (_all.isEmpty && !_failed)
                  Text(
                    context.tr(
                      pl: 'Biblioteka jest pusta. Dodaj WPS ręcznie albo '
                          'zaimportuj plik od kolegi (ikona pobierania).',
                      en: 'The library is empty. Add a WPS by hand or import '
                          'a file from a colleague (download icon).',
                    ),
                    style: const TextStyle(color: kTextSec),
                  ),
                for (final w in visible)
                  _WpsCard(
                    key: ValueKey('wps-${w.id}'),
                    wps: w,
                    onEdit: () => _openEditor(w),
                    onShare: () => _share(w),
                    onCopy: () => _copyJson(w),
                    onDelete: () => _delete(w),
                    onOpenFile: w.attachmentPath == null || kIsWeb
                        ? null
                        : () => _openAttachment(w),
                  ),
              ],
            ),
    );
  }
}

class _WpsCard extends StatelessWidget {
  final WpsRecord wps;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final VoidCallback? onOpenFile;

  const _WpsCard({
    super.key,
    required this.wps,
    required this.onEdit,
    required this.onShare,
    required this.onCopy,
    required this.onDelete,
    required this.onOpenFile,
  });

  @override
  Widget build(BuildContext context) {
    final english = context.language == AppLanguage.en;
    final w = wps;
    final method = w.heatInputMethod == HeatInputStandard.en1011
        ? 'EN 1011-1 (k)'
        : 'ASME IX';
    final lines = <String>[
      [
        english ? w.standard.labelEn : w.standard.labelPl,
        if (w.pqrRef.trim().isNotEmpty)
          context.tr(pl: 'WPQR/PQR ${w.pqrRef.trim()}', en: 'WPQR/PQR ${w.pqrRef.trim()}'),
      ].join(' · '),
      [
        if (w.processes.trim().isNotEmpty) w.processes.trim(),
        if (w.materialGroup.trim().isNotEmpty)
          context.tr(pl: 'grupa ${w.materialGroup.trim()}', en: 'group ${w.materialGroup.trim()}'),
        if (w.thicknessMinMm != null || w.thicknessMaxMm != null)
          't ${describeRange(w.thicknessMinMm, w.thicknessMaxMm, 'mm')}',
        if (w.diameterMinMm != null || w.diameterMaxMm != null)
          'D ${describeRange(w.diameterMinMm, w.diameterMaxMm, 'mm')}',
        if (w.positions.trim().isNotEmpty) w.positions.trim(),
        if (w.jointKinds.isNotEmpty) encodeJointKinds(w.jointKinds),
      ].join(' · '),
      [
        if (w.filler.trim().isNotEmpty) w.filler.trim(),
        if (w.shieldingGas.trim().isNotEmpty)
          context.tr(pl: 'osłona ${w.shieldingGas.trim()}', en: 'shield ${w.shieldingGas.trim()}'),
        if (w.backingGas.trim().isNotEmpty)
          context.tr(pl: 'formowanie ${w.backingGas.trim()}', en: 'backing ${w.backingGas.trim()}'),
      ].join(' · '),
      [
        if (w.preheatMinC != null)
          context.tr(
              pl: 'podgrzewanie ≥ ${formatDecimalField(w.preheatMinC)} °C',
              en: 'preheat ≥ ${formatDecimalField(w.preheatMinC)} °C'),
        if (w.interpassMaxC != null)
          context.tr(
              pl: 'międzyściegowa ≤ ${formatDecimalField(w.interpassMaxC)} °C',
              en: 'interpass ≤ ${formatDecimalField(w.interpassMaxC)} °C'),
        if (w.heatInputMinKjMm != null || w.heatInputMaxKjMm != null)
          'Q ${describeRange(w.heatInputMinKjMm, w.heatInputMaxKjMm, 'kJ/mm')} ($method)',
        if (w.pwht.trim().isNotEmpty) 'PWHT: ${w.pwht.trim()}',
      ].join(' · '),
    ].where((l) => l.trim().isNotEmpty).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, color: kArc, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(w.displayName,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: context.tr(pl: 'Usuń', en: 'Delete'),
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: onDelete,
              ),
            ],
          ),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 8),
              child: Text(l, style: const TextStyle(fontSize: 12.5, color: kTextSec)),
            ),
          Wrap(
            spacing: 2,
            children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(context.tr(pl: 'Edytuj', en: 'Edit')),
              ),
              TextButton.icon(
                onPressed: onShare,
                icon: const Icon(Icons.share_outlined, size: 18),
                label: Text(context.tr(pl: 'Udostępnij', en: 'Share')),
              ),
              TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: Text(context.tr(pl: 'Kopiuj JSON', en: 'Copy JSON')),
              ),
              if (onOpenFile != null)
                TextButton.icon(
                  onPressed: onOpenFile,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: Text(context.tr(pl: 'Plik WPS', en: 'WPS file')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
