import 'package:flutter/material.dart';

import '../i18n/app_language.dart';
import '../legal/legal_texts.dart';
import '../theme/app_theme.dart';

/// Wyświetla regulamin albo politykę prywatności — treść jest wbudowana, więc
/// otwiera się bez Internetu, także wtedy gdy monter stoi w hali bez zasięgu.
class LegalScreen extends StatelessWidget {
  final LegalDocument Function(BuildContext) document;

  const LegalScreen({super.key, required this.document});

  static Route<void> route(LegalDocument Function(BuildContext) doc) =>
      MaterialPageRoute(builder: (_) => LegalScreen(document: doc));

  @override
  Widget build(BuildContext context) {
    final doc = document(context);
    return Scaffold(
      appBar: AppBar(title: Text(doc.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Text(
            context.tr(
                pl: 'Aktualizacja: $kLegalUpdated',
                en: 'Last updated: $kLegalUpdated'),
            style: const TextStyle(
              color: kTextMut,
              fontSize: 11,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kArc.withValues(alpha: 0.35)),
            ),
            child: Text(
              doc.intro,
              style: const TextStyle(color: kText, fontSize: 14, height: 1.55),
            ),
          ),
          const SizedBox(height: 26),
          for (final s in doc.sections) ...[
            Text(
              s.heading,
              style: const TextStyle(
                  color: kText, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              s.body,
              style: const TextStyle(color: kTextSec, fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 22),
          ],
        ],
      ),
    );
  }
}
