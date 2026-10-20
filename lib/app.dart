import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'i18n/app_language.dart';
import 'app_navigator.dart';
import 'assistant/ui/assistant_overlay.dart';
import 'l10n/app_localizations.dart';
import 'screens/root_gate.dart';
import 'theme/app_theme.dart';
import 'widgets/weld_timer_alarm_overlay.dart';

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
    // Język ustalony w main() przed runApp (zapisany wybór albo język
    // telefonu). Kontroler aplikacji zapisuje każdą zmianę.
    _languageController =
        AppLanguageController.persistent(AppLanguageController.current);
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
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
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
                    // Koniec odliczania timera spawalniczego — pełny ekran
                    // nad każdym ekranem aplikacji.
                    child: WeldTimerAlarmOverlay(
                      child: AssistantOverlay(
                          child: child ?? const SizedBox.shrink()),
                    ),
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
