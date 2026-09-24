import 'backend_config.dart';

/// Adresy i kontakt wymagane przez sklepy.
///
/// Regulamin i polityka prywatności są WBUDOWANE w aplikację
/// (`lib/legal/legal_texts.dart` → ekran „Zasady i prywatność" w profilu), więc
/// działają bez Internetu i nie mogą rozjechać się z kodem.
///
/// Google Play i App Store Connect wymagają dodatkowo publicznego,
/// nieedytowalnego URL-a polityki prywatności i strony usuwania danych. Serwuje
/// je dedykowany backend (`backend/src/routes/publicPages.js`, ta sama treść co
/// `legal_texts.dart` — zmieniasz jedno, zmień drugie).
class AppLinks {
  /// Adres kontaktowy widoczny w aplikacji i w polityce prywatności.
  /// Apple wymaga kontaktu przy treściach tworzonych przez użytkowników (1.2).
  /// Podmień, jeśli chcesz oddzielić skrzynkę wsparcia od prywatnej. Ten sam
  /// adres ustawia backend (`SUPPORT_EMAIL`) na stronach /privacy i
  /// /data-deletion.
  static const String supportEmail = 'jakatora68@gmail.com';

  /// Publiczna polityka prywatności (PL + EN) na dedykowanym backendzie.
  ///
  /// UWAGA (2026-09-24): strona ruszy dopiero po wdrożeniu nowej wersji
  /// backendu — dziś ten adres odpowiada 404. PRZED wydaniem aplikacji i przed
  /// wpisaniem adresu w Google Play / App Store Connect sprawdź, że zwraca
  /// HTTP 200 (np. `curl -I <adres>`).
  static const String privacyPolicyUrl =
      '${BackendConfig.baseUrl}${BackendConfig.privacyPage}';

  /// Strona usuwania danych (wymagana przez Google Play, gdy aplikacja wysyła
  /// jakiekolwiek dane użytkownika). Opisuje „Usuń moje dane" w profilu i drogę
  /// mailową.
  ///
  /// UWAGA: jak wyżej — przed wydaniem potwierdź HTTP 200.
  static const String dataDeletionUrl =
      '${BackendConfig.baseUrl}${BackendConfig.dataDeletionPage}';

  static bool get hasHostedPolicy => privacyPolicyUrl.isNotEmpty;
}
