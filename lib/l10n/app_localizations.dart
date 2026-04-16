import 'package:flutter/material.dart';

/// Simple localization class for the Cut List application.
///
/// This class holds a lookup table of translation keys to their
/// localized strings for a given [Locale]. Currently only Polish
/// (`pl`) and English (`en`) are supported. When a key is missing
/// from a locale's table the key itself is returned.
class AppLocalizations {
  /// Creates an instance of [AppLocalizations] for the supplied [locale].
  const AppLocalizations(this.locale);

  /// The active locale.
  final Locale locale;

  /// Helper method to access the current localization from the
  /// provided [BuildContext].
  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  /// A static list of supported locales. Update this list when
  /// additional languages are added.
  static const List<Locale> supportedLocales = [
    Locale('pl'),
    Locale('en'),
  ];

  /// Translation map per locale. Each locale has a map of keys to
  /// translated strings. If you add new strings to your UI, add
  /// corresponding entries here for each supported language.
  static final Map<String, Map<String, String>> _localizedValues = {
    'pl': {
      // General strings
      'home_appbar': 'Wybierz tryb',
      'change_language': 'English',
      'fitter': 'Fitter',
      'welder': 'Welder',
      // Fitter menu
      'fitter_menu_appbar': 'Fitter',
      'cut_list_title': 'Cut List',
      'cut_list_subtitle': 'Segmenty i cięcia',
      'dn_mm_title': 'DN → mm',
      'dn_mm_subtitle': 'Tabela nominalna',
      'cut_elbow_title': 'Cięcie kolanka',
      'cut_elbow_subtitle': 'Oblicz odcięcie',
      'rotate_elbow_title': 'Obrót kolanka',
      'rotate_elbow_subtitle': 'Przesuń kąt',
      'insert_title': 'Wstawka',
      'insert_subtitle': 'Dodaj wstawkę',
      'reducer_title': 'Redukcja',
      'reducer_subtitle': 'Skracanie redukcji',
      'slope_title': 'Spadek',
      'slope_subtitle': 'Oblicz miter',
      'library_title': 'Biblioteka',
      'library_subtitle': 'Komponenty i parametry',
      // Welder menu
      'welder_menu_appbar': 'Welder',
      'pipes_title': 'Rury',
      'pipes_subtitle': 'AMP / Gazy / Parametry',
      'tanks_title': 'Zbiorniki',
      'tanks_subtitle': 'AMP / Tandem TIG',
      'register_appbar': 'Rejestracja',
      'register_title': 'Utwórz konto',
      'register_email': 'E-mail',
      'register_password': 'Hasło',
      'register_confirm_password': 'Potwierdź hasło',
      'register_button': 'Zarejestruj',
      'register_success': 'Konto utworzone pomyślnie.',
      'register_email_exists': 'Konto z tym adresem e-mail już istnieje.',
      'register_password_mismatch': 'Uzupełnij pola i upewnij się, że hasła są takie same.',
      'tutor_menu_appbar': 'Tutor',
      'tutor_input_hint': 'Zadaj pytanie o spawanie lub montaż',
      'tutor_out_of_scope': 'Tutor odpowiada tylko na pytania związane ze spawaniem i montażem.',
      'tutor_searching': 'Szukam odpowiedzi...',
      'tutor_no_answer': 'Nie udało się znaleźć odpowiedzi dla tego pytania.',
    },
    'en': {
      // General strings
      'home_appbar': 'Select Mode',
      'change_language': 'Polski',
      'fitter': 'Fitter',
      'welder': 'Welder',
      // Fitter menu
      'fitter_menu_appbar': 'Fitter',
      'cut_list_title': 'Cut List',
      'cut_list_subtitle': 'Segments and cuts',
      'dn_mm_title': 'DN to mm',
      'dn_mm_subtitle': 'Nominal table',
      'cut_elbow_title': 'Cut Elbow',
      'cut_elbow_subtitle': 'Calculate cut',
      'rotate_elbow_title': 'Rotate Elbow',
      'rotate_elbow_subtitle': 'Adjust angle',
      'insert_title': 'Insert',
      'insert_subtitle': 'Add insert',
      'reducer_title': 'Reducer',
      'reducer_subtitle': 'Reducer cut',
      'slope_title': 'Slope',
      'slope_subtitle': 'Calculate miter',
      'library_title': 'Library',
      'library_subtitle': 'Components and parameters',
      // Welder menu
      'welder_menu_appbar': 'Welder',
      'pipes_title': 'Pipes',
      'pipes_subtitle': 'AMP / Gases / Parameters',
      'tanks_title': 'Tanks',
      'tanks_subtitle': 'AMP / Tandem TIG',
      'register_appbar': 'Register',
      'register_title': 'Create account',
      'register_email': 'Email',
      'register_password': 'Password',
      'register_confirm_password': 'Confirm password',
      'register_button': 'Register',
      'register_success': 'Account created successfully.',
      'register_email_exists': 'An account with this email already exists.',
      'register_password_mismatch': 'Fill in all fields and make sure the passwords match.',
      'tutor_menu_appbar': 'Tutor',
      'tutor_input_hint': 'Ask a welding or fitting question',
      'tutor_out_of_scope': 'The tutor only answers questions related to welding and fitting.',
      'tutor_searching': 'Searching for an answer...',
      'tutor_no_answer': 'No answer was found for that question.',
    },
  };

  /// Looks up the translation for the provided [key]. If no translation
  /// exists for the key in the current locale, returns the key itself.
  String translate(String key) {
    return _localizedValues[locale.languageCode]?[key] ?? key;
  }

  /// The localization delegate that loads an instance of
  /// [AppLocalizations] for a given locale. Flutter will use this
  /// delegate when a locale change occurs.
  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();
}

/// Private delegate class responsible for loading the appropriate
/// [AppLocalizations] instance.
class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales.contains(Locale(locale.languageCode));
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) => false;
}