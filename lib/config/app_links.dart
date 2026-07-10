/// Adresy i kontakt wymagane przez sklepy.
///
/// Regulamin i polityka prywatności są WBUDOWANE w aplikację
/// (`lib/legal/legal_texts.dart` → ekran „Zasady i prywatność" w profilu), więc
/// działają bez Internetu i nie mogą rozjechać się z kodem.
///
/// Google Play i App Store Connect wymagają dodatkowo publicznego,
/// nieedytowalnego URL-a polityki prywatności. Plik `privacy-policy.html` w repo
/// zawiera tę samą treść — wystarczy go opublikować (np. GitHub Pages) i wpisać
/// adres poniżej. Do tego czasu aplikacja pokazuje wersję wbudowaną.
class AppLinks {
  /// Adres kontaktowy widoczny w aplikacji i w polityce prywatności.
  /// Apple wymaga kontaktu przy treściach tworzonych przez użytkowników (1.2).
  /// Podmień, jeśli chcesz oddzielić skrzynkę wsparcia od prywatnej.
  static const String supportEmail = 'jakatora68@gmail.com';

  /// TODO(publikacja): wpisz adres po opublikowaniu `privacy-policy.html`.
  static const String privacyPolicyUrl = '';

  /// TODO(publikacja): strona żądania usunięcia danych (wymagana przez Google
  /// Play, gdy aplikacja wysyła jakiekolwiek dane użytkownika).
  static const String dataDeletionUrl = '';

  static bool get hasHostedPolicy => privacyPolicyUrl.isNotEmpty;
}
