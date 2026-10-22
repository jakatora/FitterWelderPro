import 'package:flutter/material.dart';
import '../i18n/app_language.dart';

Future<String?> showIsoSketchNameDialog(BuildContext context,
        {required String current}) =>
    showDialog<String>(
        context: context, builder: (_) => _SketchNameDialog(current: current));

class _SketchNameDialog extends StatefulWidget {
  const _SketchNameDialog({required this.current});
  final String current;
  @override
  State<_SketchNameDialog> createState() => _SketchNameDialogState();
}

class _SketchNameDialogState extends State<_SketchNameDialog> {
  late final _controller = TextEditingController(text: widget.current);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, _controller.text.trim());
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(context.tr(
              pl: 'Nazwa rysunku / nr linii', en: 'Drawing name / line no.')),
          content: TextField(
              key: const Key('iso-sketch-name'),
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                  hintText: context.tr(
                      pl: 'np. 6"-CWS-1234', en: 'e.g. 6"-CWS-1234')),
              onSubmitted: (_) => _save()),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.tr(pl: 'Anuluj', en: 'Cancel'))),
            ElevatedButton(onPressed: _save, child: const Text('OK')),
          ]);
}
