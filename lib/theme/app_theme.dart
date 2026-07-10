import 'package:flutter/material.dart';

// System projektowy Fitter Welder Pro — "przyrząd pomiarowy".
//
// Zasada: stal jest zimna, spoina jest gorąca. Neutrale mają chłodne
// przesunięcie ku stali (nie są czystym szarym), a bursztyn łuku (kArc) jest
// JEDYNYM akcentem i pojawia się wyłącznie tam, gdzie coś jest "gorące":
// wynik obliczenia, aktywne pole, akcja główna.
//
// Semantyka (kPass / kWarn / kFail) jest ODRĘBNA od akcentu — bursztyn nigdy
// nie znaczy "błąd".
//
// Ekrany, które nadal trzymają własne stałe kolorów, używają dokładnie tych
// samych wartości; migracja do tych tokenów idzie stopniowo.

// ── Grunt i płaszczyzny ─────────────────────────────────────────────────────
const Color kBg = Color(0xFF0B0E13);
const Color kCard = Color(0xFF141821);
const Color kBorder = Color(0xFF2A3140);

// ── Akcenty ─────────────────────────────────────────────────────────────────
/// Bursztyn łuku spawalniczego. Jedyny akcent aplikacji.
const Color kArc = Color(0xFFFF8E1E);

/// Złoto — akcent drugorzędny (wyróżnienia, nie akcje).
const Color kGold = Color(0xFFE8C14B);

// ── Tekst ───────────────────────────────────────────────────────────────────
const Color kText = Color(0xFFE7ECF3);
const Color kTextSec = Color(0xFF9BA3C7);
const Color kTextMut = Color(0xFF5A6478);

// ── Semantyka stanu ─────────────────────────────────────────────────────────
const Color kPass = Color(0xFF35C88B);
const Color kWarn = Color(0xFFF5B23D);
const Color kFail = Color(0xFFF0655A);

/// Minimalny cel dotyku. Monter pracuje w rękawicy — nic mniejszego.
const double kMinTapTarget = 44;

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    colorSchemeSeed: kArc,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: kBg,
    appBarTheme: const AppBarTheme(
      scrolledUnderElevation: 0,
      backgroundColor: kCard,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        color: kText,
      ),
      iconTheme: IconThemeData(color: kTextSec),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: kBorder, width: 1),
      ),
      margin: const EdgeInsets.symmetric(vertical: 4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kArc, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: const TextStyle(color: kTextSec, fontSize: 14),
      hintStyle: const TextStyle(color: kTextMut, fontSize: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kArc,
        foregroundColor: Colors.black,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        minimumSize: const Size(0, kMinTapTarget),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kArc,
        side: const BorderSide(color: kArc),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        minimumSize: const Size(0, kMinTapTarget),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kTextSec,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kArc,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: StadiumBorder(),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: kArc,
      unselectedLabelColor: kTextSec,
      indicatorColor: kArc,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: kBorder,
      labelStyle:
          TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3),
      unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
    dividerTheme: const DividerThemeData(color: kBorder, thickness: 1, space: 0),
    chipTheme: ChipThemeData(
      backgroundColor: kCard,
      side: const BorderSide(color: kBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: const TextStyle(color: kText, fontSize: 13),
      deleteIconColor: kTextSec,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kCard,
      surfaceTintColor: Colors.transparent,
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      collapsedIconColor: kTextSec,
      iconColor: kArc,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    ),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: kArc,
      ),
      dataTextStyle: const TextStyle(fontSize: 13, color: kTextSec),
      headingRowColor: WidgetStateProperty.all(kCard),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kBorder)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: kCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kBorder,
      contentTextStyle: const TextStyle(color: kText),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(kCard),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return kArc;
          return kCard;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return kTextSec;
        }),
        side: WidgetStateProperty.all(const BorderSide(color: kBorder)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: kText,
        letterSpacing: -0.3,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: kText,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: kText,
        letterSpacing: 0.1,
      ),
      titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kTextSec),
      bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: kTextSec),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: kTextSec),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: kTextSec),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: kText,
        letterSpacing: 0.3,
      ),
    ),
  );
}
