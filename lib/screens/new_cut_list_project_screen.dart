import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/project.dart';
import '../database/project_dao.dart';
import '../i18n/app_language.dart';
import 'segment_builder_screen.dart';

class NewCutListProjectScreen extends StatefulWidget {
  const NewCutListProjectScreen({super.key});

  @override
  State<NewCutListProjectScreen> createState() =>
      _NewCutListProjectScreenState();
}

class _NewCutListProjectScreenState extends State<NewCutListProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final ProjectDao _projectDao = ProjectDao();

  final TextEditingController _nameController = TextEditingController();
  String _selectedMaterial = 'SS';
  final TextEditingController _odController =
      TextEditingController(text: '48.3');
  final TextEditingController _tController = TextEditingController(text: '2.0');
  final TextEditingController _stockLenController =
      TextEditingController(text: '6000');
  final TextEditingController _kerfController =
      TextEditingController(text: '1.5');

  bool _isLoading = false;
  String? _errorMessage;

  final List<String> _materials = ['SS', 'CS'];
  final List<String> _commonOD = [
    '21.3',
    '26.9',
    '33.7',
    '42.4',
    '48.3',
    '60.3',
    '76.1',
    '88.9',
    '114.3',
    '168.3',
    '219.1',
    '273.0',
    '323.9',
    '355.6',
    '406.4'
  ];

  Future<void> _createProject() async {
    // Clear previous error
    setState(() => _errorMessage = null);

    // Validate form
    if (!_formKey.currentState!.validate()) {
      setState(() =>
          _errorMessage = context.tr(pl: 'Popraw błędy w formularzu', en: 'Please fix the errors in the form'));
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = context.tr(pl: 'Wpisz nazwę projektu', en: 'Enter a project name'));
      return;
    }

    final od = double.tryParse(_odController.text.replaceAll(',', '.')) ?? 0;
    final t = double.tryParse(_tController.text.replaceAll(',', '.')) ?? 0;
    final stockLen =
        double.tryParse(_stockLenController.text.replaceAll(',', '.')) ?? 6000;
    final kerf =
        double.tryParse(_kerfController.text.replaceAll(',', '.')) ?? 1.5;


    // Final validation before save
    if (od <= 0 || t <= 0) {
      setState(() =>
          _errorMessage = context.tr(pl: 'Średnica i grubość muszą być większe od 0', en: 'Diameter and thickness must be greater than 0'));
      return;
    }

    // Set loading state
    setState(() => _isLoading = true);

    try {
      final projectId = const Uuid().v4();
      final now = DateTime.now().millisecondsSinceEpoch;
      
      final project = Project(
        id: projectId,
        name: name,
        materialGroup: _selectedMaterial,
        diameterMm: od,
        wallThicknessMm: t,
        currentDiameterMm: od,
        stockLengthMm: stockLen,
        sawKerfMm: kerf,
        gapMm: 0.0,
        createdAt: now,
        updatedAt: now,
      );

      await _projectDao.insert(project);

      if (mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr(pl: 'Projekt "$name" utworzony!', en: 'Project "$name" created!')),
            backgroundColor: const Color(0xFF1A8A9B),
          ),
        );
        // Load the project and navigate to segment builder
        _projectDao.getById(projectId).then((project) {
          if (project != null && mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (ctx) => SegmentBuilderScreen(
                  materialGroup: project.materialGroup,
                  currentDiameter: project.currentDiameterMm,
                  wallThickness: project.wallThicknessMm,
                  gapMm: project.gapMm,
                ),
              ),
            );
          } else if (mounted) {
            Navigator.pop(context, projectId);
          }
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = context.tr(pl: 'Błąd podczas tworzenia projektu: ${e.toString()}', en: 'Error creating project: ${e.toString()}');
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _odController.dispose();
    _tController.dispose();
    _stockLenController.dispose();
    _kerfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Nowy projekt', en: 'New project')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Project name
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: context.tr(pl: 'Nazwa projektu *', en: 'Project name *'),
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return context.tr(pl: 'Wpisz nazwę projektu', en: 'Enter a project name');
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Material
            DropdownButtonFormField<String>(
              initialValue: _selectedMaterial,
              key: ValueKey('material_$_selectedMaterial'),
              decoration: InputDecoration(
                labelText: context.tr(pl: 'Materiał', en: 'Material'),
                border: const OutlineInputBorder(),
              ),
              items: _materials.map((material) {
                return DropdownMenuItem(
                  value: material,
                  child: Text(
                    material == 'SS'
                        ? context.tr(pl: 'Stal nierdzewna (SS)', en: 'Stainless steel (SS)')
                        : context.tr(pl: 'Stal węglowa (CS)', en: 'Carbon steel (CS)'),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedMaterial = value!);
              },
            ),
            const SizedBox(height: 16),

            // OD selection
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _odController,
                    decoration: InputDecoration(
                      labelText: context.tr(pl: 'Średnica OD (mm) *', en: 'OD diameter (mm) *'),
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null ||
                          double.tryParse(value.replaceAll(',', '.')) == null ||
                          double.tryParse(value.replaceAll(',', '.'))! <= 0) {
                        return context.tr(pl: 'Wpisz poprawną średnicę', en: 'Enter a valid diameter');
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.list),
                    onSelected: (value) {
                      _odController.text = value;
                    },
                    itemBuilder: (context) =>
                        _commonOD.map((od) {
                          return PopupMenuItem(
                            value: od,
                            child: Text('Ø $od mm'),
                          );
                        }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Thickness
            TextFormField(
              controller: _tController,
              decoration: InputDecoration(
                labelText: context.tr(pl: 'Grubość ścianki t (mm) *', en: 'Wall thickness t (mm) *'),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null ||
                    double.tryParse(value.replaceAll(',', '.')) == null ||
                    double.tryParse(value.replaceAll(',', '.'))! <= 0) {
                  return context.tr(pl: 'Wpisz poprawną grubość', en: 'Enter a valid thickness');
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Stock length
            TextFormField(
              controller: _stockLenController,
              decoration: InputDecoration(
                labelText: context.tr(pl: 'Długość sztangi (mm)', en: 'Stock length (mm)'),
                border: const OutlineInputBorder(),
                helperText: context.tr(pl: 'Domyślnie: 6000 mm', en: 'Default: 6000 mm'),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),

            // Kerf
            TextFormField(
              controller: _kerfController,
              decoration: InputDecoration(
                labelText: context.tr(pl: 'Kerf (mm)', en: 'Kerf (mm)'),
                border: const OutlineInputBorder(),
                helperText: context.tr(pl: 'Domyślnie: 1.5 mm (zakres: 1-2)', en: 'Default: 1.5 mm (range: 1–2)'),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final kerf =
                      double.tryParse(value.replaceAll(',', '.'));
                  if (kerf != null && (kerf < 1 || kerf > 2)) {
                    return context.tr(pl: 'Kerf musi być w zakresie 1-2 mm', en: 'Kerf must be in the 1–2 mm range');
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Summary removed per request
            const SizedBox(height: 24),

            // Error message
            if (_errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.error),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: cs.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: cs.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            if (_errorMessage != null) const SizedBox(height: 16),

            // Create button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _createProject,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        context.tr(pl: 'UTWÓRZ PROJEKT', en: 'CREATE PROJECT'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
