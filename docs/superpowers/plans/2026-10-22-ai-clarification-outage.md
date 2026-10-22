# Kontynuacja pytania AI po błędzie — 2026-10-22

Cel: użytkownik odpowiada na pytanie AI i może ponowić odpowiedź po awarii bez opuszczania bieżącej rozmowy.

## Dowód i zmiana
Poprzedni kod w _tryAiCommand obsługiwał błąd interpretacji z pytaniem natywnym lub ograniczonym zadaniem, ale nie z samym _aiQuestion. Odpowiedź krótka wpadała wtedy do zwykłej ścieżki fallback. Nowa flaga awaitingAiClarification wiąże obsługę błędu i braku zgody z istniejącym pytaniem AI. Nie skleja historii w polecenie, nie dodaje uprawnień i nie uruchamia dodatkowego wywołania. Pytanie zostaje zachowane; komunikat pozwala ponowić interpretację.

Dwa widgetowe przypadki: AssistantAiUnavailable503 i FormatException. Z poprzednim źródłem HEAD oba RED (brak komunikatu o nieudanej interpretacji); źródło przywrócone dopiero po terminalnym zakończeniu testu. Z poprawką 19 testów ai_chat_execution PASS, w tym ponowienie przekazuje pending_question i zero dodatkowych chatSender calls. Nie wykonano płatnego API ani testu telefonu/produkcyjnego Railway. Analiza obu plików --fatal-infos czysta.

## Koszty i granice
Nie zmieniono modelu Haiku, budżetu, liczników ani retry. Każde jawne ponowienie nadal używa istniejącego uwierzytelnionego endpointu i bramki kosztów. Brak drugiego wywołania czatu jest potwierdzony w widgetowym transporcie, nie na rachunku Anthropic. Test nie dowodzi pełnego rozumienia wszystkich swobodnych odpowiedzi; weryfikacja źródła wykonania po ogólnym clarify i pełne live acceptance nadal pozostają otwarte.

Końcowy zestaw wszystkich test/assistant/ai_*_test.dart: 185 PASS, zero pominięć, exit0. Dedykowanego FWP_ANTHROPIC_API_KEY nadal brak w vaulcie (sprawdzono tylko obecność, bez wypisywania sekretów).
