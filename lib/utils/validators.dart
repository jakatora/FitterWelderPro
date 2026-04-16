import '../i18n/app_language.dart';

class Validators {
  static String? email(String? value, {AppLanguage language = AppLanguage.pl}) {
    String trL({required String pl, required String en}) => language == AppLanguage.en ? en : pl;

    final v = (value ?? '').trim();
    if (v.isEmpty) return trL(pl: 'Podaj adres e-mail.', en: 'Enter an email address.');
    // Prosta, skuteczna walidacja
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailRegex.hasMatch(v)) return trL(pl: 'Podaj poprawny adres e-mail.', en: 'Enter a valid email address.');
    return null;
  }

  static String? password(String? value, {AppLanguage language = AppLanguage.pl}) {
    String trL({required String pl, required String en}) => language == AppLanguage.en ? en : pl;

    final v = value ?? '';
    if (v.isEmpty) return trL(pl: 'Podaj hasło.', en: 'Enter a password.');
    if (v.length < 8) return trL(pl: 'Hasło musi mieć min. 8 znaków.', en: 'Password must be at least 8 characters.');
    if (!RegExp(r'[A-Z]').hasMatch(v)) return trL(pl: 'Dodaj co najmniej 1 wielką literę.', en: 'Add at least 1 uppercase letter.');
    if (!RegExp(r'[a-z]').hasMatch(v)) return trL(pl: 'Dodaj co najmniej 1 małą literę.', en: 'Add at least 1 lowercase letter.');
    if (!RegExp(r'[0-9]').hasMatch(v)) return trL(pl: 'Dodaj co najmniej 1 cyfrę.', en: 'Add at least 1 digit.');
    return null;
  }

  static String passwordStrengthLabel(String value, {AppLanguage language = AppLanguage.pl}) {
    String trL({required String pl, required String en}) => language == AppLanguage.en ? en : pl;

    final v = value;
    int score = 0;
    if (v.length >= 8) score++;
    if (v.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(v)) score++;
    if (RegExp(r'[a-z]').hasMatch(v)) score++;
    if (RegExp(r'[0-9]').hasMatch(v)) score++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>_\-\\/\[\]=+;~`]').hasMatch(v)) score++;

    if (score <= 2) return trL(pl: 'Słabe', en: 'Weak');
    if (score <= 4) return trL(pl: 'Średnie', en: 'Medium');
    return trL(pl: 'Mocne', en: 'Strong');
  }
}
