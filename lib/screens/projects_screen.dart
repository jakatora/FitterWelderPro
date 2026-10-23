import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../database/project_dao.dart';
import '../widgets/empty_state.dart';
import '../widgets/help_button.dart';
import '../widgets/local_record_scope.dart';
import '../models/project.dart';
import 'new_project_screen.dart';
import 'fitter_screen.dart';

/// Projekty bieżącego konta; po zmianie konta lista startuje od nowa.
class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) => LocalRecordScope(
      builder: (_, session) =>
          _ProjectsList(dao: ProjectDao(captureOwner: session.captureOwner)));
}

class _ProjectsList extends StatefulWidget {
  const _ProjectsList({required this.dao});
  final ProjectDao dao;

  @override
  State<_ProjectsList> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<_ProjectsList> {
  ProjectDao get _dao => widget.dao;
  List<Project> _projects = [];
  bool _loading = true;

  /// Search over name, line, ISO, client and class (see
  /// [projectMatchesQuery]) — a foreman with forty jobs finds one by the
  /// line number written on the pipe, not by scrolling.
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final list = await _dao.listAll();
    if (!mounted) return;
    setState(() {
      _projects = list;
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Name, stock length, kerf and gap of an existing project. A changed gap
  /// recomputes every saved CUT of the project (see
  /// [ProjectDao.updateSettings]).
  Future<void> _editSettings(Project p) async {
    final result = await showProjectSettingsDialog(context, p, dao: _dao);
    if (result == null || !mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(projectSettingsSavedMessage(context, result)),
        duration: const Duration(seconds: 6),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Projekty', en: 'Projects')),
        actions: [
          HelpButton(help: kHelpProjects),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: context.tr(pl: 'Nowy projekt', en: 'New project'),
            onPressed: () async {
              final created = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NewProjectScreen()),
              );
              if (created == true) await _load();
            },
          )
        ],
      ),
      body: _loading
          // Skeleton placeholder reads like a list of greyed-out rows so
          // the user sees the screen shape immediately on tap; perceived
          // load time drops vs. a centred spinner over an empty viewport.
          ? ListView.builder(
              itemCount: 6,
              itemBuilder: (_, __) => Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 14,
                            width: double.infinity,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 10,
                            width: 140,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.6),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          : _projects.isEmpty
            ? EmptyState(
                icon: Icons.folder_open_outlined,
                title: context.tr(
                  pl: 'Brak projektów',
                  en: 'No projects yet',
                ),
                subtitle: context.tr(
                  pl: 'Dodaj pierwszy projekt, by zacząć tworzyć cut listy.',
                  en: 'Add your first project to start building cut lists.',
                ),
                actionLabel: context.tr(pl: 'Nowy projekt', en: 'New project'),
                onAction: () async {
                  final created = await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NewProjectScreen()),
                  );
                  if (created == true) await _load();
                },
              )
              : _buildList(context),
    );
  }

  Widget _buildList(BuildContext context) {
    final visible =
        _projects.where((p) => projectMatchesQuery(p, _query)).toList();
    final english = context.language == AppLanguage.en;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            key: const ValueKey('projects-search'),
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: context.tr(
                pl: 'Szukaj: nazwa, linia, ISO, klient',
                en: 'Search: name, line, ISO, client',
              ),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: context.tr(pl: 'Wyczyść', en: 'Clear'),
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                      }),
                    ),
            ),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      context.tr(
                        pl: 'Brak projektów pasujących do „$_query”.',
                        en: 'No projects match "$_query".',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, i) {
                    final p = visible[i];
                    final name = p.name?.isNotEmpty == true
                        ? p.name!
                        : context.tr(pl: 'Projekt ${p.id.substring(0, 6)}', en: 'Project ${p.id.substring(0, 6)}');
                    // Line / ISO under the name (schema v22): what the pipe
                    // and the drawing are marked with.
                    final ident = p.identity.shortSummary(english: english);
                    return Dismissible(
                      key: ValueKey(p.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: const Color(0xFFE74C3C),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete_outline, color: Colors.white, size: 26),
                      ),
                      confirmDismiss: (_) async {
                        return await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text(context.tr(pl: 'Usuń projekt', en: 'Delete project')),
                            content: Text(context.tr(
                              pl: 'Usunąć "$name" wraz ze wszystkimi segmentami, zdjęciami i numerami wytopów? Możesz użyć „Cofnij” przez 6 sekund.',
                              en: 'Delete "$name" with all segments, photos, and heat numbers? You can use Undo for 6 seconds.',
                            )),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(context.tr(pl: 'Anuluj', en: 'Cancel')),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE74C3C), foregroundColor: Colors.white),
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(context.tr(pl: 'Usuń', en: 'Delete')),
                              ),
                            ],
                          ),
                        ) ?? false;
                      },
                      onDismissed: (_) async {
                        // One transaction over segments, heat photos,
                        // component heats and the project itself. The screen
                        // used to run two separate deletes and snapshot the
                        // rows by hand: a failure between them left a project
                        // whose cut list had already been wiped, and heat
                        // rows plus their .jpg files were never touched at
                        // all, so every deleted project leaked orphans.
                        // deleteProjectCascade returns the snapshot Undo needs.
                        DeletedProject deleted;
                        try {
                          deleted = await _dao.deleteProjectCascade(p.id);
                          await _load();
                        } catch (e) {
                          // DB constraint / lock / disk-full on the shop tablet
                          // would otherwise bubble to a red screen — surface as
                          // a SnackBar and reload so the row reappears. The
                          // transaction rolled back, so the project is intact.
                          await _load();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(SnackBar(
                              content: Text(context.tr(
                                pl: 'Nie udało się usunąć "$name": $e',
                                en: 'Could not delete "$name": $e',
                              )),
                            ));
                          return;
                        }
                        if (!context.mounted) return;
                        final messenger = ScaffoldMessenger.of(context);
                        messenger.hideCurrentSnackBar();
                        final bar = messenger.showSnackBar(SnackBar(
                          content: Text(context.tr(
                            pl: 'Usunięto "$name"',
                            en: 'Deleted "$name"',
                          )),
                          duration: const Duration(seconds: 6),
                          action: SnackBarAction(
                            label: context.tr(pl: 'Cofnij', en: 'Undo'),
                            onPressed: () async {
                              try {
                                await _dao.restore(deleted);
                                await _load();
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(context.tr(
                                    pl: 'Nie udało się przywrócić "$name": $e',
                                    en: 'Could not restore "$name": $e',
                                  )),
                                ));
                              }
                            },
                          ),
                        ));
                        // The .jpg files outlive the rows until Undo is off
                        // the table: a re-insert can bring a heat_photos row
                        // back, nothing can bring back a deleted photo.
                        // SnackBarClosedReason.action == Undo was pressed;
                        // timeout / swipe / replaced-by-another-bar all mean
                        // the delete stands, so the files can go.
                        unawaited(bar.closed.then((reason) async {
                          if (reason == SnackBarClosedReason.action) return;
                          await _dao.purgePhotoFiles(deleted);
                        }));
                      },
                      child: ListTile(
                        leading: Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8E1E).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.assignment_outlined, size: 22, color: Color(0xFFFF8E1E)),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          [
                            if (ident.isNotEmpty) ident,
                            'Ø${p.diameterMm.toStringAsFixed(1)} | t=${p.wallThicknessMm.toStringAsFixed(1)} | ${p.materialGroup} | gap ${p.gapMm.toStringAsFixed(1)}',
                          ].join('\n'),
                        ),
                        isThreeLine: ident.isNotEmpty,
                        // Name, stock, kerf and gap used to be frozen at
                        // creation. A visible button (not only the long
                        // press) because a long press is undiscoverable in
                        // gloves.
                        trailing: IconButton(
                          icon: const Icon(Icons.tune),
                          tooltip: context.tr(
                              pl: 'Ustawienia projektu',
                              en: 'Project settings'),
                          onPressed: () => _editSettings(p),
                        ),
                        onLongPress: () => _editSettings(p),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => FitterScreen(projectId: p.id)),
                        ).then((_) {
                          if (mounted) _load();
                        }),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
