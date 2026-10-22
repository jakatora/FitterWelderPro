# Nazwa ISO, potwierdzony zapis i spójne Cofnij — 2026-10-22

Dodano `iso.name` obok umiejętności rysowania i wymiarowania. Polecenia PL/EN „Nazwij rysunek…”, „Zmień nazwę rysunku na…” i „Name/Rename drawing…” zachowują tytuł z oryginalnego tekstu: wielkość liter, polskie znaki, numer linii, cudzysłów oznaczający cale. Otaczające cudzysłowy nazwy są zdejmowane. Pusta nazwa, znaki sterujące i ponad 200 znaków nie są przyjmowane przez asystenta. Tytuł z tekstem polecenia pozostaje tytułem, nie kolejnym poleceniem.

AI może zaproponować kanoniczną komendę, ale natywny walidator wymaga dokładnego tytułu z oryginału. Przy prośbie konwersacyjnej, np. `Chciałbym nazwać ten rysunek „Linia CW-123”`, akceptowany jest pojedynczy jawnie cytowany tytuł (polskie/angielskie typograficzne lub zwykłe cudzysłowy), z rozpoznanym zamiarem nadania nazwy. Nie wybiera ani nie poprawia samodzielnie nazwy. Prośba o wyjaśnienie sposobu nadania nazwy nie pozwala jej zmienić.

Kontroler kolejkuje zmianę bieżącego szkicu z kontrolą rewizji, zachowuje identyfikator i geometrię oraz czeka na rzeczywiste `_flushSave`. Sprawdza też stan po zapisie. Dopiero powodzenie daje komunikat o zapisanej nazwie. Błąd bazy oznacza osobno: nazwa zmieniona na ekranie, zapis nieudany, edytor powinien pozostać otwarty. Nie tworzy kopii i nie obsługuje „zapisz jako” jako ukrytego duplikowania.

Wspólny stos Cofnij obejmuje teraz elementy, nazwę i szczelinę rysunku. Zmiana nazwy przez asystenta, ręczny dialog nazwy i ręczna szczelina dodają własny krok. Cofnięcie nazwy/szczeliny nie usuwa wcześniej narysowanej rury. Snapshoty poleceń rysowania i korekty kierunku dostosowano do tego samego typu. Ręczna zmiana nazwy/szczeliny używa `_mutate`, zwiększa rewizję i powiadamia kontroler, chroniąc przed spóźnionymi propozycjami AI.

Nowy test ręcznego okna nazwy wykrył istniejący błąd użycia `TextEditingController` po `dispose` podczas animacji zamykania. Wydzielono dialog ze stanem, który jest właścicielem kontrolera aż do usunięcia trasy. Wygląd i działania okna pozostają takie jak wcześniej.

Dowody: 1510 zaliczonych testów bez pominięć obejmujących ISO, kodowanie szkiców, geometrię, zapisy/ponowne otwieranie, cały korpus routera i wydajność 500 wypowiedzi w 737 ms (`build/iso-name-acceptance-test.log`). Następnie dodane testy dokładnej i zmienionej propozycji AI na rzeczywistym ekranie z SQLite: końcowy zestaw 15 zaliczonych (`build/iso-name-final-ai-test.log`), bez dalszych zmian produkcyjnych. Analiza 12 plików bez uwag (`build/iso-name-final-verified-analyze.log`). Wymuszony błąd zapisu jest testowany prawdziwym triggerem SQLite. Nowy test ręczny sprawdza rura → nazwa → szczelina → Cofnij → Cofnij.

Pierwszy szeroki przebieg omyłkowo uwzględnił plik pomocniczy bez `main`; finalny zestaw ograniczono do `_test.dart`. Początkowa asercja zerowej szczeliny zakładała zapis `0`, podczas gdy istniejący kodek pomija wartość domyślną; test porównuje teraz dokładny zapis ze stanem sprzed zmiany.

Transport modelu w testach jest kontrolowany. Nie wykonano nowego płatnego wywołania, zmiany backendu ani wdrożenia Railway. Dosłowne polecenie działa lokalnie; rozpoznanie swobodnej wypowiedzi przez prawdziwy model wymaga uruchomionej usługi. Konto nadal czeka na logowanie Railway. ISO pozostaje w dotychczasowym zakresie danych urządzenia. Pełna wizja asystenta nie jest jeszcze zakończona.
