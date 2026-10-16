// Drobne klocki ekranów symboli spawalniczych.

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Krótka etykieta sekcji (wygaszona, rozstrzelona). Bez zamiany na wielkie
/// litery: w etykietach są oznaczenia wymiarów (a, z, n × l), a „A” to nie
/// „a”.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: kTextMut,
            letterSpacing: 0.4,
          ),
        ),
      );
}

/// Karta ściągi: rysunek(i) u góry, tytuł, podtytuł normowy i opis.
class SymbolCard extends StatelessWidget {
  const SymbolCard({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.drawings = const [],
    this.drawingHeight = 84,
    this.stackDrawings = false,
  });

  final String title;
  final String? subtitle;
  final String body;
  final List<CustomPainter> drawings;
  final double drawingHeight;

  /// Rysunki jeden pod drugim (każdy na całą szerokość) zamiast obok siebie.
  final bool stackDrawings;

  Widget _frame(CustomPainter painter) => Container(
        decoration: BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: CustomPaint(painter: painter, size: Size.infinite),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (drawings.isNotEmpty && stackDrawings)
            for (var i = 0; i < drawings.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              SizedBox(height: drawingHeight, child: _frame(drawings[i])),
            ]
          else if (drawings.isNotEmpty)
            SizedBox(
              height: drawingHeight,
              child: Row(
                children: [
                  for (var i = 0; i < drawings.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: _frame(drawings[i])),
                  ],
                ],
              ),
            ),
          if (drawings.isNotEmpty) const SizedBox(height: 10),
          Text(title,
              style: const TextStyle(
                  color: kText, fontSize: 15, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!,
                style: const TextStyle(color: kTextMut, fontSize: 12)),
          ],
          const SizedBox(height: 6),
          Text(body,
              style:
                  const TextStyle(color: kTextSec, fontSize: 13, height: 1.45)),
        ],
      ),
    );
  }
}

/// Akapit wprowadzenia na górze zakładki.
class IntroText extends StatelessWidget {
  const IntroText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text,
            style: const TextStyle(color: kTextSec, fontSize: 13, height: 1.5)),
      );
}

/// Dopisek o źródle (norma, uproszczenia).
class SourceNote extends StatelessWidget {
  const SourceNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.menu_book_outlined, color: kTextMut, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: kTextMut,
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      height: 1.4)),
            ),
          ],
        ),
      );
}
