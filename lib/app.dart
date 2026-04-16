import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'i18n/app_language.dart';
import 'l10n/app_localizations.dart';
import 'screens/home_screen.dart';

class CutListApp extends StatefulWidget {
  const CutListApp({super.key});

  @override
  State<CutListApp> createState() => _CutListAppState();
}

class _CutListAppState extends State<CutListApp> {
  late final AppLanguageController _languageController;

  @override
  void initState() {
    super.initState();
    _languageController = AppLanguageController();
  }

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppLanguageScope(
      controller: _languageController,
      child: ListenableBuilder(
        listenable: _languageController,
        builder: (context, _) {
          return MaterialApp(
            title: 'Fitter Welder Pro',
            debugShowCheckedModeBanner: false,
            locale: _languageController.locale,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              AppLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('pl'),
              Locale('en'),
            ],
            theme: ThemeData(
              useMaterial3: true,
              colorSchemeSeed: const Color(0xFFF5A623),
              brightness: Brightness.dark,
              scaffoldBackgroundColor: const Color(0xFF0F1117),
              appBarTheme: const AppBarTheme(
                scrolledUnderElevation: 0,
                backgroundColor: Color(0xFF1A1D26),
                surfaceTintColor: Colors.transparent,
                titleTextStyle: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: Color(0xFFE8ECF0),
                ),
                iconTheme: IconThemeData(color: Color(0xFF9BA3C7)),
              ),
              cardTheme: CardThemeData(
                elevation: 0,
                color: const Color(0xFF1A1D26),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFF2C3354), width: 1),
                ),
                margin: const EdgeInsets.symmetric(vertical: 4),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: const Color(0xFF1A1D26),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2C3354)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2C3354)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFF5A623), width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                labelStyle: const TextStyle(color: Color(0xFF9BA3C7), fontSize: 14),
                hintStyle: const TextStyle(color: Color(0xFF55607A), fontSize: 14),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF5A623),
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF5A623),
                  side: const BorderSide(color: Color(0xFFF5A623)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF9BA3C7),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              floatingActionButtonTheme: const FloatingActionButtonThemeData(
                backgroundColor: Color(0xFFF5A623),
                foregroundColor: Colors.white,
                elevation: 2,
                shape: StadiumBorder(),
              ),
              tabBarTheme: const TabBarThemeData(
                labelColor: Color(0xFFF5A623),
                unselectedLabelColor: Color(0xFF9BA3C7),
                indicatorColor: Color(0xFFF5A623),
                indicatorSize: TabBarIndicatorSize.label,
                dividerColor: Color(0xFF2C3354),
                labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              dividerTheme: const DividerThemeData(
                color: Color(0xFF2C3354),
                thickness: 1,
                space: 0,
              ),
              chipTheme: ChipThemeData(
                backgroundColor: const Color(0xFF1A1D26),
                side: const BorderSide(color: Color(0xFF2C3354)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                labelStyle: const TextStyle(color: Color(0xFFE8ECF0), fontSize: 13),
                deleteIconColor: const Color(0xFF9BA3C7),
              ),
              dialogTheme: DialogThemeData(
                backgroundColor: const Color(0xFF1A1D26),
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              bottomSheetTheme: const BottomSheetThemeData(
                backgroundColor: Color(0xFF1A1D26),
                surfaceTintColor: Colors.transparent,
              ),
              expansionTileTheme: const ExpansionTileThemeData(
                collapsedIconColor: Color(0xFF9BA3C7),
                iconColor: Color(0xFFF5A623),
              ),
              listTileTheme: const ListTileThemeData(
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              ),
              dataTableTheme: DataTableThemeData(
                headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Color(0xFFF5A623),
                ),
                dataTextStyle: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF9BA3C7),
                ),
                headingRowColor: WidgetStateProperty.all(const Color(0xFF1A1D26)),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFF2C3354))),
                ),
              ),
              popupMenuTheme: PopupMenuThemeData(
                color: const Color(0xFF1A1D26),
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              snackBarTheme: SnackBarThemeData(
                backgroundColor: const Color(0xFF2C3354),
                contentTextStyle: const TextStyle(color: Color(0xFFE8ECF0)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                behavior: SnackBarBehavior.floating,
              ),
              dropdownMenuTheme: const DropdownMenuThemeData(
                menuStyle: MenuStyle(
                  backgroundColor: WidgetStatePropertyAll(Color(0xFF1A1D26)),
                  surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
                ),
              ),
              segmentedButtonTheme: SegmentedButtonThemeData(
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Color(0xFFF5A623);
                    }
                    return const Color(0xFF1A1D26);
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return const Color(0xFF9BA3C7);
                  }),
                  side: WidgetStateProperty.all(const BorderSide(color: Color(0xFF2C3354))),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              textTheme: const TextTheme(
                headlineMedium: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE8ECF0),
                  letterSpacing: -0.3,
                ),
                titleLarge: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE8ECF0),
                  letterSpacing: -0.2,
                ),
                titleMedium: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE8ECF0),
                  letterSpacing: 0.1,
                ),
                titleSmall: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9BA3C7),
                ),
                bodyLarge: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF9BA3C7),
                ),
                bodyMedium: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF9BA3C7),
                ),
                bodySmall: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF9BA3C7),
                ),
                labelLarge: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE8ECF0),
                  letterSpacing: 0.3,
                ),
              ),
            ),
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return GestureDetector(
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: MediaQuery(
                  data: media.copyWith(),
                  child: SafeArea(
                    top: false,
                    left: true,
                    right: true,
                    bottom: true,
                    minimum: const EdgeInsets.only(bottom: 4),
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              );
            },
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
