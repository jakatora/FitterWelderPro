import 'package:flutter/material.dart';

import 'home_screen.dart';

// Punkt startowy aplikacji — i miejsce, do którego wracamy po „Usuń moje dane"
// oraz po przywróceniu kopii zapasowej (ProfileScreen robi
// pushAndRemoveUntil(RootGate)).
//
// Kiedyś to była brama: imię, nazwisko i zgoda PRZED ekranem głównym. Jedynym
// powodem był podpis na czacie — a kalkulatory, projekty i dziennik działają
// offline i nie potrzebują konta. Monter na rusztowaniu, który chce szybko
// sprawdzić wymiar kolana, nie powinien najpierw wypełniać formularza.
//
// Teraz aplikacja otwiera się od razu na ekranie głównym. Imię, nazwisko i
// akceptację zasad (bieżąca `kLegalVersion`) zbiera bramka przed czatem —
// patrz lib/widgets/community_gate.dart.

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) => const HomeScreen();
}
