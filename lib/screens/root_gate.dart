import 'package:flutter/material.dart';

import '../services/legal_consent.dart';
import '../services/user_profile.dart';
import 'consent_screen.dart';
import 'home_screen.dart';
import 'onboarding_name_screen.dart';

// Brama startowa. Trzy stany, w tej kolejności:
//   1. brak profilu     → onboarding (imię, nazwisko + akceptacja zasad),
//   2. profil bez zgody → ekran zgody (osoby sprzed wprowadzenia regulaminu
//                          oraz wszyscy po podniesieniu `kLegalVersion`),
//   3. profil i zgoda   → aplikacja.
//
// Zgoda jest bramą, nie zakładką w ustawieniach: Apple przy treściach od
// użytkowników wymaga akceptacji zasad ZANIM cokolwiek opublikują. Kolejność ma
// znaczenie — najpierw wiemy, kto to, potem pytamy, czy zna zasady.
//
// Ekran celowo cienki: żadnej logiki obliczeń ani danych.

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _GateState {
  final bool hasProfile;
  final bool hasConsent;
  const _GateState(this.hasProfile, this.hasConsent);
}

class _RootGateState extends State<RootGate> {
  late Future<_GateState> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  Future<_GateState> _resolve() async {
    final profile = await UserProfileService.instance.get();
    await LegalConsent.instance.load();
    return _GateState(profile != null, LegalConsent.instance.isAccepted);
  }

  /// Uwaga: ciało blokowe, nie strzałka. `setState(() => _future = _resolve())`
  /// zwraca `Future` z callbacka, a Flutter to asertuje w trybie debug.
  void _refresh() {
    setState(() {
      _future = _resolve();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_GateState>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done || snap.data == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF0B0E13),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFFF8E1E)),
            ),
          );
        }
        final state = snap.data!;
        if (!state.hasProfile) {
          return OnboardingNameScreen(onDone: _refresh);
        }
        if (!state.hasConsent) {
          return ConsentScreen(onAccepted: _refresh);
        }
        return const HomeScreen();
      },
    );
  }
}
