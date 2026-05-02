import 'package:flutter/material.dart';

import '../database/component_library_dao.dart';
import '../database/segment_dao.dart';
import '../i18n/app_language.dart';
import '../models/material_item.dart';
import '../services/material_list_builder.dart';
import '../widgets/help_button.dart';

class MaterialListScreen extends StatefulWidget {
  final String projectId;
  const MaterialListScreen({super.key, required this.projectId});

  @override
  State<MaterialListScreen> createState() => _MaterialListScreenState();
}

class _MaterialListScreenState extends State<MaterialListScreen> {
  late final MaterialListBuilder _builder;
  bool _loading = true;
  List<MaterialItem> _items = [];

  @override
  void initState() {
    super.initState();
    _builder = MaterialListBuilder(SegmentDao(), ComponentLibraryDao());
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _builder.buildForProject(widget.projectId);
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  String _fmtLen(double mm) {
    final m = mm / 1000.0;
    return '${m.toStringAsFixed(3)} m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(pl: 'Lista materiałowa (BOM)', en: 'Material list (BOM)')),
        actions: [HelpButton(help: kHelpMaterialList)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(child: Text(context.tr(pl: 'Brak danych (dodaj segmenty).', en: 'No data yet. Add segments first.')))
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, i) {
                    final it = _items[i];
                    return ListTile(
                      title: Text('${it.category}  •  ${it.description}'),
                      trailing: it.category == 'PIPE'
                          ? Text(_fmtLen(it.totalLengthMm ?? 0))
                          : Text(context.tr(pl: '${it.quantity ?? 0} szt.', en: '${it.quantity ?? 0} pcs')),
                    );
                  },
                ),
    );
  }
}
