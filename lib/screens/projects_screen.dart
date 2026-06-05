import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../database/project_dao.dart';
import '../database/db.dart';
import '../widgets/empty_state.dart';
import '../widgets/help_button.dart';
import '../database/segment_dao.dart';
import '../models/project.dart';
import 'new_project_screen.dart';
import 'fitter_screen.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final _dao = ProjectDao();
  final _segDao = SegmentDao();
  List<Project> _projects = [];
  bool _loading = true;

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _dao.listAll();
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
              : ListView.separated(
                  itemCount: _projects.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, i) {
                    final p = _projects[i];
                    final name = p.name?.isNotEmpty == true
                        ? p.name!
                        : context.tr(pl: 'Projekt ${p.id.substring(0, 6)}', en: 'Project ${p.id.substring(0, 6)}');
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
                              pl: 'Usunąć "$name" wraz ze wszystkimi segmentami? Tej operacji nie można cofnąć.',
                              en: 'Delete "$name" and all its segments? This cannot be undone.',
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
                        // Snapshot raw rows BEFORE delete so the SnackBar Undo
                        // can re-insert project + segments verbatim. Without
                        // this the swipe is irreversible — a real loss on a
                        // gloved mis-swipe at the bench.
                        List<Map<String, Object?>> projectRows;
                        List<Map<String, Object?>> segmentRows;
                        try {
                          final db = await AppDatabase.get();
                          projectRows = await db.query('projects',
                              where: 'id = ?', whereArgs: [p.id], limit: 1);
                          segmentRows = await db.query('segments',
                              where: 'project_id = ?', whereArgs: [p.id]);
                          await _segDao.deleteAllForProject(p.id);
                          await _dao.deleteById(p.id);
                          await _load();
                        } catch (e) {
                          // DB constraint / lock / disk-full on the shop tablet
                          // would otherwise bubble to a red screen — surface as
                          // a SnackBar and reload so the row reappears.
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
                        messenger.showSnackBar(SnackBar(
                          content: Text(context.tr(
                            pl: 'Usunięto "$name"',
                            en: 'Deleted "$name"',
                          )),
                          duration: const Duration(seconds: 6),
                          action: SnackBarAction(
                            label: context.tr(pl: 'Cofnij', en: 'Undo'),
                            onPressed: () async {
                              final db2 = await AppDatabase.get();
                              if (projectRows.isNotEmpty) {
                                await db2.insert('projects',
                                    Map<String, Object?>.from(projectRows.first));
                              }
                              for (final r in segmentRows) {
                                await db2.insert(
                                    'segments', Map<String, Object?>.from(r));
                              }
                              await _load();
                            },
                          ),
                        ));
                      },
                      child: ListTile(
                        leading: Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5A623).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.assignment_outlined, size: 22, color: Color(0xFFF5A623)),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          context.tr(
                            pl: 'Ø${p.diameterMm.toStringAsFixed(1)} | t=${p.wallThicknessMm.toStringAsFixed(1)} | ${p.materialGroup}',
                            en: 'Ø${p.diameterMm.toStringAsFixed(1)} | t=${p.wallThicknessMm.toStringAsFixed(1)} | ${p.materialGroup}',
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => FitterScreen(projectId: p.id)),
                        ).then((_) => _load()),
                      ),
                    );
                  },
                ),
    );
  }
}
