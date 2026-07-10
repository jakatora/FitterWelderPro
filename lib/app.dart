import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'i18n/app_language.dart';
import 'l10n/app_localizations.dart';
import 'screens/root_gate.dart';
import 'theme/app_theme.dart';

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
            // Tokeny i motyw mieszkają w lib/theme/app_theme.dart — jedno
            // źródło prawdy dla kolorów, typografii i celów dotyku.
            theme: buildAppTheme(),
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
            home: const RootGate(),
          );
        },
      ),
    );
  }
}
