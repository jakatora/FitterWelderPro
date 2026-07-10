// Wspólne ziarno preferencji dla testów widgetowych.
//
// Brama startowa sprawdza DWIE rzeczy: profil i akceptację zasad. Test, który
// zasieje tylko profil, utknie na ekranie zgody — a nie o to w nim chodzi.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/legal/legal_texts.dart';
import 'package:cut_list_app/services/blocked_users.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import 'package:cut_list_app/services/user_profile.dart';

/// Użytkownik, który już przeszedł onboarding i zaakceptował zasady.
void seedOnboardedUser({
  String firstName = 'Marek',
  String lastName = 'Kowalczyk',
}) {
  SharedPreferences.setMockInitialValues({
    'user_profile_v1': jsonEncode({'firstName': firstName, 'lastName': lastName}),
    'legal_consent_v1': jsonEncode({
      'version': kLegalVersion,
      'acceptedAt': '2026-07-09T12:00:00.000',
    }),
  });
  _resetSingletons();
}

/// Świeża instalacja: brak profilu, brak zgody.
void seedFreshInstall() {
  SharedPreferences.setMockInitialValues({});
  _resetSingletons();
}

/// Użytkownik sprzed wprowadzenia regulaminu: ma profil, nie ma zgody.
void seedProfileWithoutConsent() {
  SharedPreferences.setMockInitialValues({
    'user_profile_v1': jsonEncode({'firstName': 'Marek', 'lastName': 'Kowalczyk'}),
  });
  _resetSingletons();
}

void _resetSingletons() {
  UserProfileService.instance.resetForTest();
  LegalConsent.instance.resetForTest();
  BlockedUsers.instance.resetForTest();
}
