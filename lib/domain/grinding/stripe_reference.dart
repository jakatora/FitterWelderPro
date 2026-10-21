import 'grinding_check.dart';

String grindingStripeReference(SpeedStripe stripe, {required bool en}) =>
    '${en ? "Colour stripe" : "Pasek barwny"}: ${stripe.colour(en: en)} — ${stripe.speedMs.toStringAsFixed(0)} m/s.'
    '\n${en ? "EN 12413 Annex D (informative): reference colour code, not a reading of this disc marking. It does not set the disc speed or confirm grinder compatibility. Read the printed maximum speed and check the grinder, mounting, expiry, operation and guard separately." : "EN 12413 zał. D (informacyjny): to referencyjny kod kolorów, nie odczyt oznakowania tej tarczy. Nie ustala prędkości tarczy i nie potwierdza zgodności ze szlifierką. Odczytaj nadrukowaną prędkość maksymalną; osobno sprawdź szlifierkę, mocowanie, termin ważności, rodzaj pracy i osłonę."}';
