# PROPOZYCJE-COCKPIT — FitterWelderPro

**Data analizy:** 2026-06-16
**Cel biznesowy:** Wyższa konwersja i retencja = większy przychód.
**Zakres:** analiza kodu / ekranów / onboardingu / paywalla / monetyzacji. Bez zmian w kodzie aplikacji — to dokument decyzyjny + szkice wdrożenia.

---

## 1. Diagnoza stanu obecnego (co znalazłem w kodzie)

Aplikacja jest dojrzała funkcjonalnie: ~48 ekranów, moduły Fitter + Welder, AI Chat (Claude Haiku 4.5 + RAG), skaner ISO, czat, moduł Praca. Monetyzacja jest **w pełni zbudowana, ale wyłączona**.

| Obszar | Stan | Dowód w kodzie |
|---|---|---|
| Backend Stripe | **LIVE** (od 2026-05-27) | `lib/config/backend_config.dart:27` → `stripeBackendLive = true` |
| Backend AI | **LIVE** | `backend_config.dart:31` → `aiBackendLive = true` |
| **Paywall (gate)** | **WYŁĄCZONY** | `lib/widgets/premium_gate.dart:24` → `kPremiumGateEnforced = false` |
| Ekran Premium (checkout, plany, trial, tabela Free/Pro) | gotowy, dopracowany | `lib/screens/premium_screen.dart` (1247 linii) |
| Onboarding / first-run | **BRAK** | `lib/main.dart` → od razu `HomeScreen`; brak flagi `seen_onboarding`; backlog P2-10 to potwierdza |
| Prompt o ocenę w sklepie (in-app review) | **BRAK** | brak `in_app_review` w `pubspec.yaml`; brak `requestReview()` w kodzie |
| Winback / reaktywacja | logika w backendzie jest, UI brak | `premium_service.dart:323` `reactivateSubscription()` istnieje, nigdzie nie wywołane z UI |

### Krytyczny wniosek
Mamy paradoks: **kasa jest podpięta i działa (Stripe live), ale ani jedna funkcja nie jest realnie zablokowana.** `kPremiumGateEnforced = false` sprawia, że `PremiumGate` zwraca dziecko bez żadnej blokady (`premium_gate.dart:54`). Skutki:

1. **Przychód z subskrypcji ≈ 0** — jedyny sposób, by user trafił na paywall, to dobrowolne kliknięcie 1 z 7 kafelków „PREMIUM" na ekranie głównym (`home_screen.dart:270`). Nie ma żadnej presji ani momentu kontekstowego.
2. **AI Chat (feature „killer", `ai_chat_screen.dart:55`) jest darmowy dla wszystkich** — każdy darmowy user pali kredyty Anthropic (Claude Haiku 4.5) bez grosza przychodu. Tylko skaner ISO ma `alwaysEnforced` (Claude Vision), reszta AI leci za darmo.
3. **Brak onboardingu** = niska aktywacja D1 → user ląduje na siatce 7 kafelków bez prowadzenia, część odbija się bez dotarcia do „aha". Niska aktywacja zabija retencję, a retencja to mnożnik LTV.

Poniższe 3 propozycje są ułożone wg dźwigni na przychód (od największej).

---

## PROPOZYCJA 1 — Włączyć monetyzację: soft‑paywall z darmowym limitem AI + selektywny gate PRO

**Problem:** Infrastruktura płatnicza jest gotowa i włączona, ale `kPremiumGateEnforced = false` rozdaje 100% wartości za darmo. Zero blokady = zero powodu, by zapłacić. Dodatkowo darmowy AI pali pieniądze na kredytach Claude.

**Co zrobić (nie „hard wall" — to zabiłoby retencję beta-userów):**
- Dać AI Chatowi **darmowy limit dzienny** (np. 3–5 wiadomości/dzień), potem inline-upsell + przejście na `PremiumScreen`.
- **Rdzeń fittera zostaje darmowy** (cut list, ISO parser, podstawowe kalkulatory, takeouts) — to magnes akwizycyjny i powód do codziennego otwierania.
- **Gate na funkcje „pro":** heat input + preheat (CE), coping/saddle PDF, bolt torque, cloud sync, „bez reklam" — dokładnie te, które ekran Premium już reklamuje (`premium_screen.dart` tabela `_FreeVsPremiumTable`).
- Dodać kontekstowe wejścia „🔒 PRO" w menu narzędzi (`PremiumLockTile` już istnieje w `premium_gate.dart:71`!) zamiast jednego kafelka na ekranie głównym.

**Dlaczego to zarabia:**
Każda subskrypcja (19 PLN/mc lub 149 PLN/rok) to przychód, który **dziś fizycznie nie może się wydarzyć**. Przy aktywnej bazie nawet 1–2% konwersji × ARPU to różnica między 0 a realnym MRR. Soft-paywall jednocześnie **tnie koszt AI** (darmowi userzy przestają wywoływać Claude bez limitu) — poprawia marżę od razu, niezależnie od konwersji. To pojedyncza zmiana o najwyższym ROI w całym repo.

**Szkic wdrożenia:**
1. `PremiumService`: dodać licznik `freeAiMessagesUsedToday` w `SharedPreferences` + reset po dacie (klucz `fitter_ai_free_count` + `fitter_ai_free_date`).
2. `ai_chat_screen.dart`: przed wysłaniem sprawdzić `isPremium || freeRemaining > 0`; po wyczerpaniu pokazać bottom-sheet „Wykorzystałeś dzienny limit AI — odblokuj bez limitu" → `PremiumScreen`.
3. `premium_gate.dart:24`: `kPremiumGateEnforced = true`, ale opakować gate'em **tylko** ekrany pro (heat input, preheat, coping, bolt torque, cloud sync) — rdzeń zostaje bez gate.
4. W `fitter_tools_screen.dart` / `welder_tools_screen.dart` owinąć kafle pro w `PremiumLockTile` (badge „PRO" + tap → paywall).
5. Bramka właściciela: flip flagi to akcja odwracalna lokalnie; przed produkcją zweryfikować e2e checkout na realnym Stripe (test mode).

**Ryzyko/uwaga:** beta-userzy przyzwyczajeni do darmowego pełnego dostępu mogą zareagować negatywnie → komunikat „grandfathering" lub kod lifetime dla pierwszych userów (mechanizm `PremiumPlan.lifetime` już istnieje, `premium_service.dart:37`).

---

## PROPOZYCJA 2 — First‑run onboarding z „aha moment" w 30 s i miękkim upsellem trialu na końcu

**Problem:** `main.dart` ładuje od razu `HomeScreen` — **zero onboardingu**. Nowy user widzi siatkę 7 kafelków bez kontekstu „co to robi i po co". Jedyne prowadzenie to mała plakietka „Spróbuj tego" widoczna wyłącznie gdy lista projektów jest pusta (`home_screen.dart:304`). Backlog P2-10 sam to oznacza jako brakujące.

**Co zrobić:**
- Ekran `OnboardingScreen` przy pierwszym uruchomieniu (flaga `seen_onboarding` w `SharedPreferences`), 3 slajdy wartości:
  1. „Cut list + parser ISO w kieszeni — koniec liczenia na kartce."
  2. „Parametry spawania + AI asystent z 30+ norm ASME/EN/AWS."
  3. Wybór języka PL/EN + przycisk **„Zacznij"** → wrzuca usera prosto w FITTER → nowy projekt (prowadzona aktywacja), a NIE na pasywną siatkę.
- Na końcu onboardingu — **miękki upsell**: „Pierwsze 7 dni Premium za darmo" + „Pomiń teraz" (oba wzorce copy już są w `premium_screen.dart`).

**Dlaczego to zarabia:**
Retencja to mnożnik LTV. User, który w pierwszej sesji nie dotrze do „aha" (pierwszy wynik cut-listy / pierwsza odpowiedź AI), churnuje w D1 — i nigdy nie zobaczy paywalla z Propozycji 1. Wyższa aktywacja → więcej DAU → więcej sesji, w których paywall może skonwertować → wyższe LTV. Dodatkowo zakończenie onboardingu ofertą trialu **łapie intencję w szczycie motywacji** (zaraz po zobaczeniu wartości), co konwertuje wielokrotnie lepiej niż zakopany kafelek „PREMIUM".

**Szkic wdrożenia:**
1. Nowy `lib/screens/onboarding_screen.dart` — `PageView` 3 slajdy, teksty przez `context.tr(pl:…, en:…)`.
2. `main.dart` / `app.dart`: po `PremiumService.init()` sprawdzić `prefs.getBool('seen_onboarding')`; jeśli `false` → `home: OnboardingScreen()`, po ukończeniu set flagi + `Navigator.pushReplacement(HomeScreen)`.
3. Ostatni slajd: CTA „Zacznij" → `NewCutListProjectScreen` (prowadzona aktywacja); drugi przycisk „Wypróbuj 7 dni za darmo" → `PremiumScreen`.
4. Event aktywacji: jeśli po 1. sesji brak projektu, wyeksponować callout „Spróbuj tego" mocniej (już jest, `home_screen.dart:304`).

---

## PROPOZYCJA 3 — Prompt o ocenę w momencie sukcesu + winback (reaktywacja) + ekspozycja trialu

**Problem (3 nieszczelności naraz):**
- **Brak in-app review** — nigdzie nie ma `requestReview()`. Ocena i liczba recenzji to jeden z najsilniejszych czynników konwersji strony sklepu (store-page CRO) i rankingu ASO.
- **Winback gotowy w backendzie, brak UI** — `reactivateSubscription()` (`premium_service.dart:323`) i `previousStatus` (`:188`) istnieją, ale żaden ekran nie pokazuje „Reaktywuj poprzedni plan". Odzysk churnujących subskrybentów to najtańszy przychód, jaki jest.
- **Trial zakopany** — „Pierwsze 7 dni za darmo" jest małą plakietką przy karcie rocznej (`premium_screen.dart:491`), a nie głównym CTA.

**Co zrobić:**
- Dodać `in_app_review` i odpalać `requestReview()` po **pozytywnym zdarzeniu** (eksport PDF cut-listy, zapis do dziennika spawów, skopiowanie odpowiedzi AI), z throttlingiem (≥2 sesje, max 1×/wersję).
- Dodać baner „Reaktywuj plan" na `PremiumScreen`, gdy `previousStatus` to plan płatny → podpiąć istniejące `reactivateSubscription()`.
- Wypromować trial: zmienić główny przycisk na karcie rocznej z „Wybierz" na **„Wypróbuj 7 dni za darmo"**.

**Dlaczego to zarabia:**
- **Oceny:** prompt po „wygranej" daje wysokiej jakości recenzje 4–5★ → lepszy ranking i wyższa konwersja strony w Google Play / App Store → **więcej darmowych instalacji** (większy szczyt lejka, którego potem dotyczą Propozycje 1–2). To dźwignia na akwizycję bez wydatku na ads.
- **Winback:** reaktywacja istniejącego, anulowanego subskrybenta jest dużo tańsza niż pozyskanie nowego — czysty przychód z gotowej już logiki.
- **Trial w CTA:** obniża próg decyzji („za darmo, anuluj kiedy chcesz" — copy już jest, `premium_screen.dart:517`), podnosi start trialu → trialowcy konwertują na płatnych dużo lepiej niż zimny ruch.

**Szkic wdrożenia:**
1. `pubspec.yaml`: dodać `in_app_review: ^2.0.x`.
2. Serwis `ReviewPromptService` (licznik sesji + flaga „już proszono w tej wersji" w `SharedPreferences`); wywołać po sukcesach w: eksport PDF, zapis dziennika spawów, kopiowanie odpowiedzi AI.
3. `premium_screen.dart`: dodać warunkowy `_ReactivateBanner` gdy `PremiumService.instance.previousStatus?.plan` ∈ {monthly, yearly}; `onTap` → `reactivateSubscription()` + odświeżenie statusu.
4. Zmiana etykiety przycisku rocznego planu + wyniesienie trialu do hero (`_Hero`).
5. **ASO:** odświeżyć opis/keywords/screeny pod konwersję — użyć skilla `aso-app-store-optimization` (osobne zadanie).

---

## Priorytety (wpływ vs. nakład)

| # | Propozycja | Wpływ na przychód | Nakład | Rekomendacja |
|---|---|---|---|---|
| 1 | Soft‑paywall + limit AI + selektywny gate | **Bardzo wysoki** (włącza przychód + tnie koszt AI) | Niski–średni (infra gotowa) | **Najpierw to** |
| 2 | First‑run onboarding + aha + trial | Wysoki (retencja = mnożnik LTV) | Średni (nowy ekran) | Drugie |
| 3 | In‑app review + winback + ekspozycja trialu | Średni–wysoki (akwizycja + odzysk) | Niski | Trzecie / równolegle |

**Jednozdaniowy take-away:** Najszybszy przychód leży w jednej linijce — `kPremiumGateEnforced = false` (`premium_gate.dart:24`). Stripe już działa; dziś rozdajemy wszystko za darmo i jeszcze dopłacamy do kredytów AI. Włączenie soft-paywalla + onboarding + prompt o ocenę domykają lejek od instalacji po płatność.

---

## Załącznik: kluczowe pliki/punkty zaczepienia

- `lib/widgets/premium_gate.dart:24` — globalny kill-switch paywalla (`kPremiumGateEnforced`).
- `lib/config/backend_config.dart:27,31` — flagi `stripeBackendLive` / `aiBackendLive` (oba `true`).
- `lib/screens/premium_screen.dart` — gotowy ekran zakupu (plany, trial, tabela Free/Pro, checkout Stripe).
- `lib/services/premium_service.dart:323,188` — `reactivateSubscription()` + `previousStatus` (winback, gotowe w backendzie).
- `lib/screens/ai_chat_screen.dart:55` — `PremiumGate` wokół AI (dziś otwarty → AI za darmo).
- `lib/main.dart` — punkt wejścia bez onboardingu.
- `lib/screens/home_screen.dart:270,304` — kafelek PREMIUM + callout „Spróbuj tego".
- Backlog P2-10 (`BACKLOG_2026-06-07.md:323`) — potwierdza brak first-launch onboardingu.
