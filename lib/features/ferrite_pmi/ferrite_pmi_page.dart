// Ferryt i PMI — protokoły pomiaru ferrytu (FN / %) i PMI (XRF): nowy
// protokół, historia (SharedPreferences, bez zmian schematu bazy), usuwanie
// z cofnięciem, udostępnianie tekstu.
//
// Logika i źródła: lib/domain/ferrite_pmi/. Edycja protokołu:
// ferrite_pmi_edit_page.dart.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/ferrite_pmi/ferrite.dart';
import '../../domain/ferrite_pmi/ferrite_pmi_protocol.dart';
import '../../domain/ferrite_pmi/ferrite_pmi_text.dart';
import '../../domain/ferrite_pmi/pmi.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../quotes/quote_widgets.dart' show QuoteNotice, QuoteSection;
import 'ferrite_pmi_edit_page.dart';
import 'ferrite_pmi_store.dart';
import '../../widgets/local_record_scope.dart';

class FerritePmiPage extends StatefulWidget {
  const FerritePmiPage({
    super.key,
    this.store = const FerritePmiStore(),
    this.now = DateTime.now,
    this.newId,
    this.shareText = ferritePmiDefaultShareText,
  });

  final FerritePmiStore store;
  final DateTime Function() now;

  /// Identyfikator nowego protokołu — wstrzykiwany w testach.
  final String Function()? newId;
  final FerritePmiShareText shareText;

  @override
  State<FerritePmiPage> createState() => _FerritePmiPageState();
}

enum _ItemAction { share, delete }

class _FerritePmiPageState extends State<FerritePmiPage> {
  List<FerritePmiProtocol>? _items;
  bool _loadFailed = false;
  FerritePmiLoad? _damage;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final load = await widget.store.loadReport();
      if (!mounted) return;
      setState(() {
        _items = load.protocols;
        _loadFailed = false;
        if (load.damaged) _damage = load;
      });
    } catch (e) {
      debugPrint('[ferrite_pmi] load failed: $e');
      if (!mounted) return;
      setState(() {
        _items = const [];
        _loadFailed = true;
      });
    }
  }

  String _id() => widget.newId?.call() ?? const Uuid().v4();

  void _snack(String text, {Key? key, SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(key: key, content: Text(text), action: action));
  }

  /// Historia pełna — nowego protokołu nie da się zapisać; mówimy to od
  /// razu, zamiast otwierać formularz, który się nie zapisze.
  bool _refuseWhenFull() {
    if ((_items?.length ?? 0) < FerritePmiStore.maxEntries) return false;
    _snack(
      key: const ValueKey('fp-store-full'),
      context.tr(
        pl: 'Historia pełna (${FerritePmiStore.maxEntries} protokołów) — '
            'udostępnij i usuń stare protokoły, żeby dodać nowy.',
        en: 'History full (${FerritePmiStore.maxEntries} records) — share '
            'and delete old records to add a new one.',
      ),
    );
    return true;
  }

  Future<void> _open(FerritePmiProtocol p) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LocalRecordScope(
          restartOnAccountChange: false,
          builder: (_, __) => FerritePmiEditPage(
                initial: p,
                store: widget.store,
                now: widget.now,
                shareText: widget.shareText,
              )),
    ));
    await _reload();
  }

  Future<void> _new() async {
    if (_refuseWhenFull()) return;
    await _open(FerritePmiProtocol.blank(id: _id(), now: widget.now()));
  }

  Future<void> _share(FerritePmiProtocol p) async {
    final en = context.language == AppLanguage.en;
    try {
      await widget.shareText(
          ferritePmiProtocolText(p, en: en, now: widget.now()),
          ferritePmiSubject(en: en));
    } catch (e) {
      if (!mounted) return;
      _snack(context.tr(
          pl: 'Nie udało się udostępnić: $e', en: 'Sharing failed: $e'));
    }
  }

  Future<void> _delete(FerritePmiProtocol p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title:
            Text(context.tr(pl: 'Usunąć protokół?', en: 'Delete this record?')),
        content: Text(_titleOf(p)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
          ),
          FilledButton(
            key: const ValueKey('fp-delete-confirm'),
            style: FilledButton.styleFrom(
                backgroundColor: kFail, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(context.tr(pl: 'Usuń', en: 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.store.delete(p.id);
    } catch (e) {
      // Błąd zapisu (np. brak miejsca) — komunikat zamiast wyjątku;
      // protokół zostaje w historii.
      debugPrint('[ferrite_pmi] delete failed: $e');
      if (!mounted) return;
      _snack(
        key: const ValueKey('fp-delete-failed'),
        context.tr(
            pl: 'Nie udało się usunąć protokołu — zapis w telefonie się nie '
                'powiódł. Protokół zostaje w historii.',
            en: 'Could not delete the record — saving on this phone failed. '
                'The record stays in the history.'),
      );
      await _reload();
      return;
    }
    await _reload();
    if (!mounted) return;
    _snack(
      key: const ValueKey('fp-deleted'),
      context.tr(pl: 'Protokół usunięty.', en: 'Record deleted.'),
      action: SnackBarAction(
        label: context.tr(pl: 'Cofnij', en: 'Undo'),
        // Przywrócenie zawsze dozwolone — także przy pełnej historii.
        onPressed: () => unawaited(_restore(p)),
      ),
    );
  }

  Future<void> _restore(FerritePmiProtocol p) async {
    try {
      await widget.store.restore(p);
    } catch (e) {
      debugPrint('[ferrite_pmi] restore failed: $e');
      if (!mounted) return;
      _snack(
        key: const ValueKey('fp-restore-failed'),
        context.tr(
            pl: 'Nie udało się przywrócić protokołu — zapis w telefonie się '
                'nie powiódł.',
            en: 'Could not restore the record — saving on this phone '
                'failed.'),
      );
    }
    if (mounted) await _reload();
  }

  String _titleOf(FerritePmiProtocol p) {
    final t = p.title.trim();
    if (t.isNotEmpty) return t;
    final firstPmi =
        p.filledPmi.map((e) => e.label.trim()).where((e) => e.isNotEmpty);
    if (firstPmi.isNotEmpty) return firstPmi.first;
    return context.tr(pl: '(bez oznaczenia)', en: '(no designation)');
  }

  @override
  Widget build(BuildContext context) {
    final en = context.language == AppLanguage.en;
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Ferryt i PMI', en: 'Ferrite and PMI')),
      ),
      body: ListView(
        key: const ValueKey('fp-list'),
        padding: EdgeInsets.fromLTRB(
            12, 12, 12, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          if (items != null && items.length >= FerritePmiStore.warnAt)
            QuoteNotice(
              key: const ValueKey('fp-store-warn'),
              color: items.length >= FerritePmiStore.maxEntries ? kFail : kWarn,
              icon: Icons.inventory_2_outlined,
              text: context.tr(
                pl: 'Historia: ${items.length}/${FerritePmiStore.maxEntries} '
                    'protokołów. Przy pełnej nowego protokołu nie da się '
                    'zapisać — udostępnij i usuń stare.',
                en: 'History: ${items.length}/${FerritePmiStore.maxEntries} '
                    'records. When full, a new record cannot be saved — '
                    'share and delete old ones.',
              ),
            ),
          if (_damage != null)
            QuoteNotice(
              key: const ValueKey('fp-load-damaged'),
              color: kFail,
              icon: Icons.report_gmailerrorred_outlined,
              text: _damage!.unreadable
                  ? context.tr(
                      pl: 'Zapisanej historii nie da się odczytać — kopia '
                          'surowego zapisu została w telefonie.',
                      en: 'The saved history could not be read — a raw copy '
                          'is kept on the phone.')
                  : context.tr(
                      pl: 'Część zapisu była nieczytelna: pominięto '
                          '${_damage!.droppedProtocols} protokołów i '
                          '${_damage!.droppedItems} elementów (miejsc, '
                          'odczytów, pozycji). Kopia surowego zapisu została '
                          'w telefonie.',
                      en: 'Part of the saved data was unreadable: '
                          '${_damage!.droppedProtocols} record(s) and '
                          '${_damage!.droppedItems} item(s) (locations, '
                          'readings, PMI items) skipped. A raw copy is kept '
                          'on the phone.'),
            ),
          QuoteNotice(
            icon: Icons.gavel_outlined,
            text: ferritePmiDisclaimer(en: en),
          ),
          QuoteSection(
            title: context.tr(pl: 'Nowy pomiar', en: 'New test'),
            subtitle: context.tr(
              pl: 'Ferryt: odczyty ferrytomierza w wielu miejscach wobec '
                  'zakresu ze specyfikacji. PMI: odczyty XRF wobec składu '
                  'gatunku wg EN albo ASTM.',
              en: 'Ferrite: ferritescope readings at several locations '
                  'against the specification range. PMI: XRF readings '
                  'against the grade composition per EN or ASTM.',
            ),
            children: [
              FilledButton.icon(
                key: const ValueKey('fp-new'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, kMinTapTarget)),
                onPressed: _new,
                icon: const Icon(Icons.add),
                label: Text(context.tr(pl: 'Nowy protokół', en: 'New record')),
              ),
            ],
          ),
          QuoteSection(
            title: context.tr(
                pl: 'Historia (${items?.length ?? 0})',
                en: 'History (${items?.length ?? 0})'),
            children: [
              if (items == null)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (items.isEmpty)
                Text(
                  _loadFailed
                      ? context.tr(
                          pl: 'Nie udało się wczytać historii.',
                          en: 'Could not load the history.')
                      : context.tr(
                          pl: 'Brak zapisanych protokołów.',
                          en: 'No saved records yet.'),
                  key: const ValueKey('fp-empty'),
                  style: const TextStyle(color: kTextSec, fontSize: 13.5),
                )
              else
                for (final (i, p) in items.indexed)
                  _HistoryTile(
                    key: ValueKey('fp-item-$i'),
                    index: i,
                    protocol: p,
                    title: _titleOf(p),
                    en: en,
                    onOpen: () => _open(p),
                    onAction: (a) => switch (a) {
                      _ItemAction.share => _share(p),
                      _ItemAction.delete => _delete(p),
                    },
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Kolor werdyktu: zielony tylko „w zakresie” / „zgodny”, czerwony tylko
/// „poza” / „niezgodny”, reszta — ostrzegawczy (nigdy zielony).
Color ferriteVerdictColor(FerriteVerdict v) => switch (v) {
      FerriteVerdict.pass => kPass,
      FerriteVerdict.fail => kFail,
      FerriteVerdict.none => kWarn,
    };

Color pmiVerdictColor(PmiVerdict v) => switch (v) {
      PmiVerdict.conforming || PmiVerdict.conformingNoCarbon => kPass,
      PmiVerdict.nonConforming => kFail,
      PmiVerdict.toVerify || PmiVerdict.none => kWarn,
    };

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    super.key,
    required this.index,
    required this.protocol,
    required this.title,
    required this.en,
    required this.onOpen,
    required this.onAction,
  });

  final int index;
  final FerritePmiProtocol protocol;
  final String title;
  final bool en;
  final VoidCallback onOpen;
  final Future<void> Function(_ItemAction a) onAction;

  @override
  Widget build(BuildContext context) {
    final p = protocol;
    final lines = <(String, Color)>[];
    if (p.hasFerrite) {
      final v = p.ferriteVerdict;
      lines.add((
        '${en ? 'Ferrite' : 'Ferryt'}: ${ferriteVerdictLabel(v, en: en)}',
        ferriteVerdictColor(v),
      ));
    }
    for (final item in p.filledPmi) {
      final r = item.evaluate();
      final what = item.label.trim().isNotEmpty
          ? item.label.trim()
          : (r.grade?.title ?? 'PMI');
      lines.add((
        'PMI $what: ${pmiVerdictLabel(r.verdict, en: en)}',
        pmiVerdictColor(r.verdict)
      ));
    }
    final worst = lines.any((l) => l.$2 == kFail)
        ? kFail
        : lines.isNotEmpty && lines.every((l) => l.$2 == kPass)
            ? kPass
            : kWarn;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: kBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('fp-open-$index'),
          onTap: onOpen,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
              child: Row(
                children: [
                  Icon(
                    worst == kPass
                        ? Icons.check_circle_outline
                        : worst == kFail
                            ? Icons.cancel_outlined
                            : Icons.help_outline,
                    color: worst,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: kText,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(p.date,
                            style: const TextStyle(
                                color: kTextSec, fontSize: 12.5)),
                        for (final (j, (text, color)) in lines.indexed)
                          Text(text,
                              key: ValueKey('fp-item-$index-line-$j'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: color,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  PopupMenuButton<_ItemAction>(
                    key: ValueKey('fp-menu-$index'),
                    tooltip: en ? 'More' : 'Więcej',
                    icon: const Icon(Icons.more_vert, color: kTextSec),
                    onSelected: onAction,
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        key: const ValueKey('fp-menu-share'),
                        value: _ItemAction.share,
                        child: Text(en ? 'Share text' : 'Udostępnij tekst'),
                      ),
                      PopupMenuItem(
                        key: const ValueKey('fp-menu-del'),
                        value: _ItemAction.delete,
                        child: Text(en ? 'Delete' : 'Usuń'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
