import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  pl,
  en,
}

/// Język interfejsu.
///
/// Kolejność ustalania przy starcie ([restore]):
///   1. wybór zapisany przez użytkownika (SharedPreferences, [prefsKey]),
///   2. język telefonu — polski daje PL, każdy inny EN.
///
/// Zapisujemy tylko świadomy wybór (przełącznik PL/EN). Dopóki monter nic nie
/// wybrał, aplikacja idzie za językiem telefonu.
///
/// [current] jest czytany statycznie poza drzewem widżetów (formatowanie liczb,
/// komunikaty po `await`), dlatego [restore] ustawia go PRZED `runApp`.
class AppLanguageController extends ValueNotifier<AppLanguage> {
  /// Kontroler bez zapisu — do testów i podglądów pojedynczych ekranów.
  AppLanguageController([AppLanguage initialValue = AppLanguage.pl])
      : _persist = false,
        super(initialValue) {
    current = initialValue;
  }

  /// Kontroler aplikacji: każdy wybór języka trafia do SharedPreferences.
  AppLanguageController.persistent(AppLanguage initialValue)
      : _persist = true,
        super(initialValue) {
    current = initialValue;
  }

  static const String prefsKey = 'app_language_v1';

  final bool _persist;

  static AppLanguage current = AppLanguage.pl;

  static bool get isEnglish => current == AppLanguage.en;

  /// Polski telefon → PL, każdy inny → EN.
  static AppLanguage fromDeviceLocale(ui.Locale? locale) =>
      locale?.languageCode.toLowerCase() == 'pl'
          ? AppLanguage.pl
          : AppLanguage.en;

  static AppLanguage? parse(String? raw) => switch (raw) {
        'pl' => AppLanguage.pl,
        'en' => AppLanguage.en,
        _ => null,
      };

  /// Ustala język startowy i ustawia [current]. Nigdy nie rzuca: przy awarii
  /// odczytu zostaje język telefonu.
  static Future<AppLanguage> restore({ui.Locale? deviceLocale}) async {
    AppLanguage? saved;
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 2));
      saved = parse(prefs.getString(prefsKey));
    } catch (_) {
      saved = null;
    }
    final resolved = saved ??
        fromDeviceLocale(deviceLocale ?? ui.PlatformDispatcher.instance.locale);
    current = resolved;
    return resolved;
  }

  void setLanguage(AppLanguage language) {
    if (value == language) return;
    value = language;
    current = language;
    if (_persist) unawaited(_save(language));
  }

  static Future<void> _save(AppLanguage language) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, language.name);
    } catch (_) {
      // Wybór działa w tej sesji; przy następnym starcie wróci język telefonu.
    }
  }

  void toggle() {
    setLanguage(value == AppLanguage.pl ? AppLanguage.en : AppLanguage.pl);
  }

  Locale get locale =>
      value == AppLanguage.en ? const Locale('en') : const Locale('pl');
}

class AppLanguageScope extends InheritedNotifier<AppLanguageController> {
  const AppLanguageScope({
    required AppLanguageController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AppLanguageController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppLanguageScope>();
    assert(scope != null, 'AppLanguageScope not found in widget tree');
    return scope!.notifier!;
  }
}

extension AppLanguageTr on BuildContext {
  AppLanguageController get _lang => AppLanguageScope.of(this);

  AppLanguage get language => _lang.value;

  void setLanguage(AppLanguage language) => _lang.setLanguage(language);

  String tr({required String pl, required String en}) {
    return _lang.value == AppLanguage.en ? en : pl;
  }
}
