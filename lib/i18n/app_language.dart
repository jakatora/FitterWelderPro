import 'package:flutter/widgets.dart';

enum AppLanguage {
  pl,
  en,
}

class AppLanguageController extends ValueNotifier<AppLanguage> {
  AppLanguageController([AppLanguage initialValue = AppLanguage.pl])
      : super(initialValue) {
    current = initialValue;
  }

  static AppLanguage current = AppLanguage.pl;

  static bool get isEnglish => current == AppLanguage.en;

  void setLanguage(AppLanguage language) {
    if (value == language) return;
    value = language;
    current = language;
  }

  void toggle() {
    setLanguage(value == AppLanguage.pl ? AppLanguage.en : AppLanguage.pl);
  }

  Locale get locale => value == AppLanguage.en ? const Locale('en') : const Locale('pl');
}

class AppLanguageScope extends InheritedNotifier<AppLanguageController> {
  const AppLanguageScope({
    required AppLanguageController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AppLanguageController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppLanguageScope>();
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
