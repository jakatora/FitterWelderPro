import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/clipboard_helper.dart';

// Sygnatura systemu projektowego: "odczyt przyrządu".
//
// Każda wartość policzona przez aplikację podawana jest w tej formie:
//   • liczba cyframi TABULARNYMI — kolumny wyników wyrównują się co do piksela,
//     a monter czyta je w rękawicy zamiast odcyfrowywać;
//   • jednostka kapitalikami, wygaszona — nie konkuruje z liczbą;
//   • pod spodem kreska z gradientem ciepła (bursztyn → nic), echo strefy
//     wpływu ciepła z ikony aplikacji.
//
// Bursztyn (`hot: true`) rezerwujemy dla wyniku GŁÓWNEGO ekranu. Wartości
// pomocnicze zostają w bieli — inaczej akcent przestaje cokolwiek znaczyć.
//
// Przytrzymanie kopiuje wartość do schowka (konwencja całej aplikacji).

class Readout extends StatelessWidget {
  /// Co to za wielkość, np. „Takeout LR 45°".
  final String label;

  /// Sformatowana wartość, np. „64" albo „0.220".
  final String value;

  /// Jednostka i kontekst, np. „mm · DN100". Opcjonalne.
  final String? unit;

  /// Wynik główny ekranu — jedyny, który świeci bursztynem.
  final bool hot;

  const Readout({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.hot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: kTextMut,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        CopyOnLongPress(
          value: value,
          label: label,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 36,
              height: 1.0,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: hot ? kArc : kText,
              fontFeatures: const [
                FontFeature.tabularFigures(),
                FontFeature.slashedZero(),
              ],
            ),
          ),
        ),
        if (unit != null) ...[
          const SizedBox(height: 4),
          Text(
            unit!.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: kTextMut,
              letterSpacing: 1.2,
            ),
          ),
        ],
        const SizedBox(height: 8),
        // Kreska gradientu ciepła — wygasa w nic, jak strefa wpływu ciepła.
        Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                hot ? kArc : kTextMut,
                (hot ? kArc : kTextMut).withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
