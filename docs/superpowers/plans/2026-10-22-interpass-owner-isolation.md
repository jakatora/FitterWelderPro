# Rejestr temperatury według kont — 2026-10-22

## Wymaganie i RED
Po zmianie konta aplikacja i asystent mają odczytywać i zmieniać tylko wpisy bieżącego właściciela. Legacy interpass_log_v1 pozostaje trybem gościa. Nie przypisywać go automatycznie do pierwszego logowania. Dwa testy RED na0484ef2 potwierdziły odczyt guest w signed-in oraz wspólne jednostki.

## Implementacja
- InterpassStore chwyta LocalRecordOwner przed kolejką. Wszystkie publiczne operacje load/upsert/update/CAS/delete/loadUnit/saveUnit używają owner i sprawdzają sesję przed/po I/O i po wejściu do _serial. Guest zachowuje dotychczasowe klucze; konto używa .owner.<Uri.encodeComponent(account:id)> dla logu, jednostki i trzech kopii uszkodzonych danych. Kod nie skanuje cudzych kluczy ani nie przenosi wpisów automatycznie.
- scoped(captureOwner) wiąże manualne callbacki, snackbar undo i edytor ze źródłową sesją. Powtórne scoped nie usuwa wcześniejszej kontroli właściciela. Zmiana konta w trakcie callbacku nie może dopisać starego rekordu do nowego namespace. In-flight OS prefs write nie jest atomowy z logout; zapis ma jednak wcześniej ustalony klucz właściciela, a nie klucz nowego konta.
- LocalRecordScope odtwarza listę dla nowej sesji. Edytor i modale nie odtwarzają starego initial pod nowym kontem: usuwają poprzednie pola/handle z drzewa i pokazują komunikat powrotu. originSession zabezpiecza również opóźnione otwarcie starej karty. Okno usuwania, picker dziennika i date/time pickers są osłonięte. Zmiana konta czyści snackbary.
- PDF ma walidację sesji przed I/O, po budowie/zapisie PDF, po temp-directory i przed share. Każdy plik ma osobny losowy katalog, więc równoległe eksporty nie nadpisują sobie załączników. Tekst/PDF w edytorze używa callbacków powiązanych z sesją, również gdy share jest wstrzyknięty w testach.
- Dotychczasowy ownerScope historii asystenta i zabezpieczenia preview/confirm/undo pozostają. Przystosowano testy, które wcześniej świadomie korzystały z globalnego store: seed danych konta osobno, jawny guest fixture; nie usunięto assertów własności.

## Dowody
Początkowo86 testów wszystkich Interpass przechodziło po implementacji. Nowe5 storage tests: guest/account z identycznym record id i zachowaniem legacy; delete/unit isolation; osobne corrupt backups; wszystkie7 operacji bound store odmawiają nowej sesji; opóźnione admission nie przechodzi na nowego użytkownika.

Nowe5 widgetowych przypadków na rzeczywistych ekranach kontA/B z identycznym id: lista usuwa prywatny numer/opisA i ładujeB; editor autosave zachowujeA, zmiana konta usuwa pola i pozwala wrócić do listyB; modal delete ukrywaA i nie kasujeB; journal picker ukrywaA i nie wypełniaB; przechwycony callback Undo nie odtwarza starej spoiny doB ani doA po zmianie sesji. Te przypadki mająPASS i brak framework exceptions.

Dwa testy eksportu: stale owner odmawia przed platform I/O; rzeczywisty PDF budowany w teście czeka na MethodChannel temp directory, w tym czasie następuje sign-inB, wynik AccountException, zero utworzonych plików i zero share. Nie wykonano rzeczywistego systemowego share na telefonie.

## Granice
Brak zmiany backendu, modelu Haiku, cennika, budżetu lub retry. Zero płatnych API i brak nowego deploy/APK. History retention100 nadal wspólne; inne moduły (WelderIdentity, WPS/certyfikaty/kupony) nie uzyskały przez tę zmianę polityki per-account. Pełny cel i live phone/Railway/Anthropic acceptance nadal otwarte.

## Końcowe sprawdzenie
Pełny flutter test --no-pub: 8849 PASS, 37 wcześniejszych field-contract skips, zero failures, exit0 (4:06). Po nim wyłącznie mechaniczne klamry lint oraz dodatkowy test wymuszonego invalidateSession przy editorze: końcowy pełny zestaw Interpass97 PASS, zero skips (23s). Test wymuszonego unieważnienia potwierdza ukrycieA, pustyGuest i bezpieczny powrót do listyB po nowym logowaniu. Końcowa analiza11 plików --fatal-infos bez uwag; git diff --check czysty. Nie powtarzano wszystkich8849 po mechanicznej zmianie bez semantyki; dodany test jest w97 targeted.
