// Wspólne ziarno preferencji dla testów widgetowych.
//
// Aplikacja startuje prosto na ekran główny — profil i zgoda na zasady są
// potrzebne dopiero przy wejściu na czat (lib/widgets/community_gate.dart).
// Ziarna nadal rozróżniają trzy stany, bo od nich zależy, co pokaże bramka
// czatu: nic (wpuszcza), zgodę albo krok imienia i nazwiska.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/feedback/feedback_store.dart';
import 'package:cut_list_app/feedback/feedback_consent.dart';
import 'package:cut_list_app/legal/legal_texts.dart';
import 'package:cut_list_app/services/blocked_users.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import 'package:cut_list_app/services/tool_usage.dart';
import 'package:cut_list_app/services/user_profile.dart';

/// Użytkownik, który już się przedstawił i zaakceptował zasady.
void seedOnboardedUser({
  String firstName = 'Marek',
  String lastName = 'Kowalczyk',
  Map<String, Object> extra = const {},
}) {
  SharedPreferences.setMockInitialValues({
    'user_profile_v1':
        jsonEncode({'firstName': firstName, 'lastName': lastName}),
    'legal_consent_v1': jsonEncode({
      'version': kLegalVersion,
      'acceptedAt': '2026-07-09T12:00:00.000',
    }),
    ...extra,
  });
  _resetSingletons();
}

/// Świeża instalacja: brak profilu, brak zgody.
void seedFreshInstall({Map<String, Object> extra = const {}}) {
  SharedPreferences.setMockInitialValues({...extra});
  _resetSingletons();
}

/// Użytkownik sprzed wprowadzenia regulaminu (albo taki, który wpisał imię
/// w profilu, ale nie był jeszcze na czacie): ma profil, nie ma zgody.
void seedProfileWithoutConsent() {
  SharedPreferences.setMockInitialValues({
    'user_profile_v1':
        jsonEncode({'firstName': 'Marek', 'lastName': 'Kowalczyk'}),
  });
  _resetSingletons();
}

/// Użytkownik, który zaakceptował STARSZĄ wersję zasad (po podniesieniu
/// `kLegalVersion`).
void seedOutdatedConsent() {
  SharedPreferences.setMockInitialValues({
    'user_profile_v1':
        jsonEncode({'firstName': 'Marek', 'lastName': 'Kowalczyk'}),
    'legal_consent_v1': jsonEncode({
      'version': kLegalVersion - 1,
      'acceptedAt': '2026-01-01T00:00:00.000',
    }),
  });
  _resetSingletons();
}

void _resetSingletons() {
  // A fixture is a new install. Futures from a previous widget's fake-async
  // zone cannot be reused after replacing the mocked preference store.
  FeedbackStore.instance.resetForTest();
  FeedbackConsent.instance.resetForTest();
  UserProfileService.instance.resetForTest();
  LegalConsent.instance.resetForTest();
  BlockedUsers.instance.resetForTest();
  ToolUsageStore.instance.resetForTest();
  // Język jest statyczny i przeżywa między testami w jednym pliku. Asercje
  // w tych testach są po polsku — zaczynamy zawsze od PL.
  AppLanguageController.current = AppLanguage.pl;
}
