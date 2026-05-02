import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../database/project_dao.dart';
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
          ? const Center(child: CircularProgressIndicator())
          : _projects.isEmpty
            ? Center(child: Text(context.tr(pl: 'Brak projektów. Kliknij + aby dodać.', en: 'No projects yet. Click + to add one.')))
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
                        await _segDao.deleteAllForProject(p.id);
                        await _dao.deleteById(p.id);
                        await _load();
                      },
                      child: ListTile(
                        leading: Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5A623).withOpacity(0.1),
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
