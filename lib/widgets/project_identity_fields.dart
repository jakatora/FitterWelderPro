import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/app_language.dart';
import '../models/project.dart';

/// Text controllers for the five identification fields of a project (schema
/// v22). Owned by the form that shows [ProjectIdentityFields]; dispose them
/// with the form.
class ProjectIdentityControllers {
  ProjectIdentityControllers([ProjectIdentity initial = ProjectIdentity.empty])
      : lineNo = TextEditingController(text: initial.lineNo ?? ''),
        isoNo = TextEditingController(text: initial.isoNo ?? ''),
        isoRev = TextEditingController(text: initial.isoRev ?? ''),
        client = TextEditingController(text: initial.client ?? ''),
        spec = TextEditingController(text: initial.spec ?? '');

  final TextEditingController lineNo;
  final TextEditingController isoNo;
  final TextEditingController isoRev;
  final TextEditingController client;
  final TextEditingController spec;

  /// What is typed, trimmed; blanks become null.
  ProjectIdentity get value => ProjectIdentity.clean(
        lineNo: lineNo.text,
        isoNo: isoNo.text,
        isoRev: isoRev.text,
        client: client.text,
        spec: spec.text,
      );

  void dispose() {
    lineNo.dispose();
    isoNo.dispose();
    isoRev.dispose();
    client.dispose();
    spec.dispose();
  }
}

/// Line no. / ISO no. + revision / client / piping class — one block for the
/// new-project form, the project settings dialog and the scan review, so the
/// three can never label or filter them differently.
///
/// Free text on purpose (line and drawing numbers are full of letters,
/// dashes and slashes), single line, capped at 80 characters like the name.
class ProjectIdentityFields extends StatelessWidget {
  const ProjectIdentityFields({
    super.key,
    required this.controllers,
    this.enabled = true,
    this.dense = false,
  });

  final ProjectIdentityControllers controllers;
  final bool enabled;

  /// Compact fields for a dialog or a card.
  final bool dense;

  static final List<TextInputFormatter> _formatters = [
    FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
    LengthLimitingTextInputFormatter(80),
  ];

  Widget _field(
    BuildContext context,
    TextEditingController c,
    String label, {
    String? hint,
    TextCapitalization capitalization = TextCapitalization.characters,
  }) {
    return TextField(
      controller: c,
      enabled: enabled,
      inputFormatters: _formatters,
      textCapitalization: capitalization,
      decoration: InputDecoration(
        isDense: dense,
        labelText: label,
        hintText: hint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gap = SizedBox(height: dense ? 8 : 12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(
          context,
          controllers.lineNo,
          context.tr(pl: 'Nr linii', en: 'Line no.'),
          hint: context.tr(pl: 'np. DN100-CWS-1234', en: 'e.g. DN100-CWS-1234'),
        ),
        gap,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _field(
                context,
                controllers.isoNo,
                context.tr(pl: 'Nr ISO (rysunku)', en: 'ISO (drawing) no.'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _field(
                context,
                controllers.isoRev,
                context.tr(pl: 'Rewizja', en: 'Revision'),
              ),
            ),
          ],
        ),
        gap,
        _field(
          context,
          controllers.client,
          context.tr(pl: 'Klient', en: 'Client'),
          capitalization: TextCapitalization.words,
        ),
        gap,
        _field(
          context,
          controllers.spec,
          context.tr(pl: 'Klasa rurociągu', en: 'Piping class'),
          hint: context.tr(pl: 'np. A1B', en: 'e.g. A1B'),
        ),
      ],
    );
  }
}
