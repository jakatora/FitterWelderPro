import 'package:flutter/material.dart';

import '../screens/consent_screen.dart';
import '../screens/onboarding_name_screen.dart';
import '../services/legal_consent.dart';
import '../services/user_profile.dart';

// Bramka przed wszystkim, co wysyła dane na serwer pod nazwiskiem montera
// (dziś: czat; jutro: ogłoszenia — patrz `ToolSpec.needsAccount`). Skaner ISO
// tu nie trafia: zdjęcie nie idzie pod nazwiskiem, więc pyta tylko o zgodę na
// wysyłkę (`scan_consent_gate.dart`).
//
// Kalkulatory, projekty i dziennik działają offline i bez konta, więc aplikacja
// startuje prosto na ekran główny. Imienia, nazwiska i akceptacji zasad
// wymagamy dopiero tu — bo dopiero tu są potrzebne: podpisują wiadomość, a Apple
// (wytyczna 1.2) chce akceptacji zasad, zanim ktoś cokolwiek opublikuje.
//
// Podniesienie `kLegalVersion` blokuje więc tylko czat, nie całą aplikację.

/// Czy profil i zgoda na bieżącą wersję zasad są już w pamięci. Synchroniczne,
/// do szybkiej ścieżki; `false` znaczy tylko „trzeba sprawdzić".
bool get hasCommunityAccess =>
    UserProfileService.instance.hasProfile && LegalConsent.instance.isAccepted;

/// Zwraca `true`, gdy monter może pisać na serwer: ma imię i nazwisko oraz
/// zaakceptował bieżącą wersję zasad. W przeciwnym razie pokazuje brakujący
/// krok (przedstawienie się + zasady albo same zasady) i zwraca `true` dopiero
/// po jego ukończeniu. Cofnięcie się z tego kroku zwraca `false`.
Future<bool> ensureCommunityAccess(BuildContext context) async {
  final profile = await UserProfileService.instance.get();
  await LegalConsent.instance.load();
  if (profile != null && LegalConsent.instance.isAccepted) return true;
  if (!context.mounted) return false;

  final navigator = Navigator.of(context);
  final done = await navigator.push<bool>(MaterialPageRoute(
    builder: (routeContext) => profile == null
        // Nikt jeszcze się nie przedstawił: imię, nazwisko i zasady w jednym
        // kroku.
        ? OnboardingNameScreen(
            onDone: () => Navigator.of(routeContext).pop(true),
          )
        // Profil jest, brakuje zgody (nigdy jej nie było albo zasady się
        // zmieniły): same zasady.
        : ConsentScreen(
            onAccepted: () => Navigator.of(routeContext).pop(true),
          ),
  ));
  return done == true && hasCommunityAccess;
}

/// Wariant bramki dla funkcji, które wysyłają treść na serwer, ale NIE pod
/// nazwiskiem (asystent: pytania „Odpowiedz" i klasyfikacja poleceń na
/// serwerze). Imię i nazwisko nie są tu do niczego potrzebne — serwer widzi
/// tylko identyfikator instalacji — więc ich nie zbieramy (minimalizacja
/// danych). Wymagamy wyłącznie akceptacji bieżącej wersji zasad i polityki
/// prywatności, które opisują, co i dokąd wysyła asystent.
Future<bool> ensureServerConsent(BuildContext context) async {
  await LegalConsent.instance.load();
  if (LegalConsent.instance.isAccepted) return true;
  if (!context.mounted) return false;
  final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
    builder: (routeContext) => ConsentScreen(
      onAccepted: () => Navigator.of(routeContext).pop(true),
    ),
  ));
  return done == true && LegalConsent.instance.isAccepted;
}
