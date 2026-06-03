# CUT LIST — User Spec (verbatim, canonical)

> Authoritative product spec for the Zeszyt ISO / Prefab Engine rebuild.
> Captured 2026-05-31. This file is the source of truth — implementation docs
> (`CUT_LIST_PREFAB_ENGINE.md`, `BACKLOG.md`) must defer to it on any conflict.

---

# NOWA LOGIKA CUT LIST – MODUŁ ZESZYT ISO

Musisz przebudować logikę obliczania CUT LIST w module „Zeszyt ISO”.

## Jak działa moduł

Użytkownik:

* rysuje izometrykę,
* dodaje segmenty,
* dodaje komponenty,
* wpisuje wymiary ISO,
* a program ma automatycznie obliczyć długości cięcia rur (CUT LIST).

Segment oznacza odcinek pomiędzy komponentami.

Przykład:

* kolanko → rura → kolanko = jeden segment rury pomiędzy dwoma komponentami.

---

# GŁÓWNA ZASADA

CUT LENGTH rury liczymy:

```text
WYMIAR ISO
MINUS
WSZYSTKIE WYMIARY KOMPONENTÓW OSIOWYCH „DO OSI”
```

Czyli:

* komponenty osiowe odejmujemy od wymiaru ISO,
* komponenty nieosiowe wymagają dodatkowej informacji od użytkownika.

---

# KOMPONENTY OSIOWE

Komponent osiowy:

* kolanko 90,
* kolanko 45,
* trójnik,
* każdy komponent posiadający wymiar „CENTER TO END” / „DO OSI”.

Dla takich komponentów:

* zawsze odejmujemy wymiar do osi od wymiaru ISO.

---

# PRZYKŁADY LOGIKI

## 1. RURA + KOLANKO 90

Układ:

```text
RURA → ELBOW 90
```

Jeżeli wymiar ISO jest do osi kolanka:

```text
CUT LENGTH = ISO - ELBOW_CENTER
```

---

## 2. KOLANKO + RURA + KOLANKO

Układ:

```text
ELBOW → RURA → ELBOW
```

Wtedy:

```text
CUT LENGTH = ISO - ELBOW1_CENTER - ELBOW2_CENTER
```

---

# KOMPONENTY NIEOSIOWE

Komponent nieosiowy:

* redukcja,
* flansza,
* zaślepka,
* komponenty posiadające długość fizyczną zamiast wymiaru do osi.

Dla takich komponentów NIE DA SIĘ automatycznie wiedzieć:

* czy komponent należy odjąć od wymiaru ISO,
* ponieważ nie wiadomo do którego miejsca użytkownik podał wymiar ISO.

Dlatego użytkownik MUSI wskazać:
„Do jakiego miejsca podany jest wymiar ISO”.

---

# PRZYKŁAD – REDUKCJA

Układ:

```text
ELBOW → RURA → REDUKCJA → RURA → FLANSZA
```

Program musi zapytać użytkownika:

## PYTANIE:

„Do którego miejsca podany jest wymiar ISO?”

Opcje:

* do czoła redukcji,
* do końca redukcji.

---

# PRZYPADEK 1 – ISO DO CZOŁA REDUKCJI

Jeżeli ISO jest podane do początku/czoła redukcji:

```text
CUT LENGTH = ISO - ELBOW_CENTER
```

Długości redukcji NIE odejmujemy.

---

# PRZYPADEK 2 – ISO DO KOŃCA REDUKCJI

Jeżeli ISO jest podane do końca redukcji:

użytkownik musi podać:

* długość redukcji,
* średnicę wyjściową redukcji.

Wtedy:

```text
CUT LENGTH = ISO - ELBOW_CENTER - REDUCTION_LENGTH
```

---

# ZMIANA ŚREDNICY ZA REDUKCJĄ

To bardzo ważne.

Jeżeli użytkownik dodaje redukcję:

* musi podać średnicę wejściową,
* musi podać średnicę wyjściową.

Po redukcji:

* następna rura ma już nową średnicę,
* kolejne komponenty również używają nowej średnicy.

Czyli redukcja zmienia średnicę całej dalszej części segmentu.

---

# WAŻNE ZAŁOŻENIE LOGIKI

Program NIE MOŻE zakładać:
że każdy wymiar ISO jest do osi komponentu.

Dlatego:

* komponenty osiowe odejmujemy automatycznie,
* komponenty nieosiowe wymagają określenia punktu odniesienia wymiaru ISO.

---

# CO MA ZROBIĆ SYSTEM

System ma:

1. Analizować segment.
2. Rozpoznawać komponenty osiowe i nieosiowe.
3. Dla osiowych:

   * odejmować wymiar do osi.
4. Dla nieosiowych:

   * pytać użytkownika do którego miejsca podany jest wymiar ISO.
5. Automatycznie wyliczać CUT LENGTH rur.
6. Aktualizować średnice po redukcjach.
7. Obsługiwać wiele segmentów w jednej izometryce.
8. Zachować pełną zgodność z rzeczywistą logiką prefabrykacji rurociągów.

---

# BARDZO WAŻNE

Nie chcę prostego odejmowania stałych wartości.

Chcę inteligentny system zależny od:

* typu komponentu,
* sposobu podania wymiaru ISO,
* kierunku segmentu,
* średnic przed i po redukcji,
* pozycji komponentu w segmencie.

System musi działać jak rzeczywisty CUT LIST dla prefabrykacji rur.

Zaprojektuj:

* model danych,
* strukturę segmentów,
* logikę obliczeń,
* algorytm obliczania CUT LIST,
* UI pytań dla użytkownika,
* oraz edge cases.

Przeanalizuj logikę tak, jak robi to monter/składacz rurociągów przemysłowych podczas prefabrykacji.

System nie może działać jak prosty kalkulator geometryczny.
Musi działać jak rzeczywisty warsztat prefabrykacji rur.

---

# 1. WYMIAR ISO NIE ZAWSZE OZNACZA TO SAMO

Na izometrykach przemysłowych:

* część wymiarów jest do osi,
* część do czoła,
* część do końca komponentu,
* część między osiami,
* część między czołami,
* część od osi do czoła.

Dlatego system musi wiedzieć:
do jakiego punktu odnosi się każdy wymiar ISO.

Każdy wymiar ISO powinien mieć typ odniesienia:

* CENTER_TO_CENTER
* CENTER_TO_FACE
* FACE_TO_FACE
* FACE_TO_END
* CENTER_TO_END

Nie zakładaj automatycznie jednego typu wymiarowania.

---

# 2. KOLEJNOŚĆ KOMPONENTÓW MA OGROMNE ZNACZENIE

Program musi analizować kolejność komponentów w segmencie.

Przykład:

```text
ELBOW → PIPE → TEE
```

to NIE jest to samo co:

```text
TEE → PIPE → ELBOW
```

Ponieważ:

* tee może mieć różne długości center-to-end,
* różne strony tee mogą mieć różne wymiary,
* odejmowanie zależy od kierunku segmentu.

System musi znać:

* wejście segmentu,
* wyjście segmentu,
* kierunek przepływu segmentu,
* stronę komponentu używaną w obliczeniu.

---

# 3. KOLANKO 45 NIE ZACHOWUJE SIĘ JAK 90

Kolanka 45:

* często mają inne take-off,
* mogą tworzyć offset,
* mogą wpływać na rzeczywistą długość osi.

Program musi być przygotowany na:

* offsety,
* rolling offset,
* ukośne segmenty,
* przyszłą obsługę 3D.

Nie projektuj logiki tylko pod proste 90°.

---

# 4. TRÓJNIK MUSI MIEĆ STRONY

Tee musi posiadać:

* RUN LEFT
* RUN RIGHT
* BRANCH

Każda strona może mieć:

* inny wymiar center-to-end,
* inną średnicę.

Podczas obliczeń program musi wiedzieć:
z której strony użytkownik prowadzi segment.

---

# 5. REDUKCJA ZMIENIA WSZYSTKO DALEJ

Po redukcji:

* zmienia się średnica kolejnych rur,
* zmieniają się kolejne komponenty,
* zmieniają się możliwe take-offy.

Program musi propagować średnicę dalej przez cały pipeline.

Nie tylko dla następnej rury.

---

# 6. FLANSZA NIE ZAWSZE JEST LICZONA TAK SAMO

Na różnych izometrykach:

* wymiar może być do czoła flanszy,
* do RF,
* do końca szyjki,
* do osi rury przed flanszą.

Dlatego flansza musi mieć:

* typ odniesienia,
* długość fizyczną,
* opcjonalny take-off.

---

# 7. SYSTEM MUSI ROZRÓŻNIAĆ:

## komponent osiowy

odejmowany automatycznie:

* elbow,
* tee,
* lateral,
* o-let,
* komponenty center-to-end.

## komponent długościowy

wymaga określenia odniesienia:

* reducer,
* flange,
* cap,
* valve,
* strainer,
* expansion joint.

---

# 8. ZAWORY MUSZĄ POSIADAĆ DŁUGOŚĆ FACE TO FACE

Valve:

* ma fizyczną długość,
* może być liczony między flanszami,
* może być gwintowany,
* może być socket weld.

Program musi obsługiwać:

* długość valve,
* typ końcówek,
* czy wymiar ISO obejmuje valve czy nie.

---

# 9. SPAWALNICZA REALNOŚĆ

Monter NIE TYLKO liczy geometrię.

On musi wiedzieć:

* co ma uciąć,
* z jakiej średnicy,
* gdzie zmienia się średnica,
* ile zostawić na spaw,
* gdzie są spoiny.

Dlatego każdy segment powinien posiadać:

* pipe size,
* schedule/thickness,
* material,
* weld points,
* spool number,
* cut length.

---

# 10. SYSTEM MUSI OBSŁUGIWAĆ SPOOLING

Rzeczywiste izometryki są dzielone na:

* spools,
* prefab sections,
* field welds.

Dlatego:

* segmenty muszą należeć do spoola,
* CUT LIST musi być liczony per spool.

---

# 11. DŁUGOŚĆ CIĘCIA ≠ DŁUGOŚĆ MONTAŻOWA

Program musi rozróżniać:

* długość geometryczną,
* długość montażową,
* długość cięcia.

W przyszłości trzeba będzie dodać:

* gap pod spaw,
* shrinkage,
* bevel allowance,
* machine allowance.

Architektura musi być przygotowana na takie rozszerzenia.

---

# 12. EDGE CASES

System musi obsłużyć:

* wiele redukcji w jednym segmencie,
* redukcję mimośrodową,
* dwa komponenty bez rury pomiędzy,
* bardzo krótkie spool pieces,
* valve pomiędzy elbow,
* mixed units,
* imperial + metric,
* brak danych komponentu,
* custom fittings,
* mirrored orientation.

---

# 13. NIE OPERAJ LOGIKI NA TEKŚCIE

Nie opieraj obliczeń na nazwach typu:

* „Elbow90”
* „Reducer”

Każdy komponent musi mieć:

* typ techniczny,
* klasę zachowania,
* metodę obliczeń,
* definicję geometryczną.

Przykład:

```text
component.behaviorType = AXIAL_CENTER
component.behaviorType = PHYSICAL_LENGTH
component.behaviorType = DIAMETER_CHANGE
```

---

# 14. SYSTEM MA DZIAŁAĆ JAK SMART PREFAB ENGINE

To nie jest zwykły rysownik ISO.

To ma być inteligentny system prefabrykacyjny:

* analizujący geometrię,
* analizujący kolejność,
* analizujący typy komponentów,
* automatycznie wyliczający CUT LIST,
* zachowujący logikę prawdziwego warsztatu prefabrykacji rur.

Projektuj architekturę tak, aby później można było dodać:

* automatyczne spooling,
* nesting rur 6m,
* BOM,
* weld map,
* MTO,
* eksport do PCF / IFC / AutoCAD.

---

# AUTOMATYCZNE DODAWANIE SPAWÓW PODCZAS RYSOWANIA IZOMETRII

Dodaj do systemu inteligentną logikę automatycznego wykrywania miejsc spawów podczas rysowania izometryki.

Podczas prefabrykacji przemysłowych rurociągów:

* praktycznie każde połączenie komponentów jest spawane,
* monter musi widzieć gdzie znajdują się spawy,
* CUT LIST i późniejszy weld map muszą być zgodne z rzeczywistością.

Dlatego system powinien automatycznie dodawać punkty spawów (kropki weld point) podczas tworzenia segmentów.

---

# GŁÓWNA ZASADA

Jeżeli:

* komponent styka się z rurą,
* komponent styka się z innym komponentem,
* i połączenie jest spawane,

to system automatycznie dodaje weld point.

Weld point powinien być widoczny jako:

* kropka,
* marker,
* punkt spawu,
* node połączenia.

---

# GDZIE AUTOMATYCZNIE DODAWAĆ SPAWY

## 1. RURA → KOLANKO

Układ:

```text
PIPE → ELBOW
```

Automatycznie dodaj spaw:

* pomiędzy rurą a kolankiem.

---

## 2. KOLANKO → RURA → KOLANKO

Układ:

```text
ELBOW → PIPE → ELBOW
```

Dodaj:

* spaw przed rurą,
* spaw za rurą.

Czyli rura posiada dwa weld pointy.

---

## 3. RURA → TEE

Układ:

```text
PIPE → TEE
```

Dodaj spaw:

* na wejściu tee.

Jeżeli tee posiada odnogę:

* branch również posiada własny weld point.

---

# 4. REDUKCJA

Układ:

```text
PIPE → REDUCER → PIPE
```

Dodaj:

* spaw przed redukcją,
* spaw za redukcją.

Ponieważ redukcja jest osobnym komponentem prefabrykacyjnym.

---

# 5. FLANSZA

Układ:

```text
PIPE → FLANGE
```

Domyślnie:

* dodaj spaw pomiędzy rurą i flanszą.

Ale system musi obsługiwać typ połączenia:

* Weld Neck,
* Socket Weld,
* Slip-On,
* Threaded,
* Lap Joint.

Nie każda flansza ma taki sam typ spawu.

---

# 6. ZAWORY

Układ:

```text
PIPE → VALVE → PIPE
```

Domyślnie:

* jeden spaw z lewej,
* jeden spaw z prawej.

Ale zależnie od typu:

* threaded,
* flanged,
* butt weld,
* socket weld,

logika może się różnić.

---

# 7. DWA KOMPONENTY BEZ RURY

Układ:

```text
ELBOW → REDUCER
```

Jeżeli komponenty są bezpośrednio połączone:

* również dodaj weld point.

---

# 8. CAP / END CAP

Układ:

```text
PIPE → CAP
```

Dodaj:

* jeden końcowy spaw.

---

# 9. O-LET / SOCKOLET / WELDOLET

O-lety:

* posiadają osobny spaw branchowy,
* są spawane do rury głównej,
* mogą mieć dodatkowy spaw do branch pipe.

Program musi obsługiwać:

* weld main,
* weld branch.

---

# SPAW MUSI POSIADAĆ DANE

Każdy weld point powinien być osobnym obiektem.

Przykład:

```text
weld.id
weld.number
weld.type
weld.position
weld.connectedComponents
weld.pipeSize
weld.schedule
weld.material
weld.spool
weld.ndtStatus
```

---

# NUMERACJA SPAWÓW

System powinien automatycznie numerować spawy:

```text
W-001
W-002
W-003
```

Numeracja:

* globalna,
* lub per spool.

---

# FIELD WELD VS SHOP WELD

System musi obsługiwać:

* SHOP WELD,
* FIELD WELD.

Field weld:

* wykonywany na montażu,
* powinien mieć specjalny symbol.

Shop weld:

* wykonywany w prefabrykacji.

Użytkownik musi móc zmienić typ spawu.

---

# AUTOMATYCZNE ZACHOWANIE PODCZAS RYSOWANIA

Podczas rysowania izometryki:

## gdy użytkownik:

* dodaje komponent,
* dodaje rurę,
* łączy dwa komponenty,

system automatycznie:

* tworzy weld point,
* dodaje kropkę,
* numeruje spaw,
* przypisuje połączenie.

Bez potrzeby ręcznego dodawania.

---

# SPAW JAKO ELEMENT LOGIKI SYSTEMU

Spaw nie może być tylko grafiką.

Spaw musi być częścią:

* CUT LIST,
* spoolingu,
* weld map,
* BOM,
* prefabrykacji,
* raportów.

---

# RZECZYWISTE ZASADY WARSZTATOWE

W prawdziwej prefabrykacji:

* prawie każdy fitting posiada spaw,
* każdy spool ma listę weldów,
* monter i spawacz pracują na weld mapie.

System powinien zachowywać się jak prawdziwy system prefabrykacyjny używany w przemyśle:

* oil & gas,
* food industry,
* pharma,
* process piping,
* power plants.

---

# ARCHITEKTURA

Projektuj system tak, aby później można było dodać:

* weld map,
* NDT tracking,
* RT/UT/PT/MT status,
* welder assignment,
* heat numbers,
* spool tracking,
* QC inspection,
* eksport PCF.

---

# DECYZJE PROJEKTOWE — POTWIERDZONE PRZEZ UŻYTKOWNIKA

## 1. Default DimRef

Tak:

* gdy obie strony segmentu są axial → default CTC,
* NIE pytaj użytkownika za każdym razem.

Czyli:

```text
ELBOW → PIPE → ELBOW
TEE → PIPE → ELBOW
TEE → PIPE → TEE
```

defaultowo:

```text
DimRef = CENTER_TO_CENTER
```

Ale:
jeżeli w segmencie pojawi się komponent physical:

* reducer,
* flange,
* valve,
* cap,
* strainer,
* expansion joint,
  itd.

wtedy system ma automatycznie wymagać określenia DimRef dla tego końca segmentu.

Czyli:

* axial ↔ axial = auto CTC,
* axial ↔ physical = pytanie,
* physical ↔ physical = pytanie.

Nie chcę miliona popupów podczas rysowania.

System ma być szybki jak prawdziwy warsztat.

---

## 2. Picker UI

Tak — dodatkowy wiersz w obecnym dim sheet.

Nie osobny modal.

Powód:

* mniej kliknięć,
* szybsze workflow,
* bardziej „warsztatowe”,
* monter nie może być zatrzymywany popupami co chwilę.

Proponuję:

```text
ISO DIMENSION: [ 1500 ]

DIM REF:
[ Center-Center ▼ ]
```

I dynamicznie:

* hidden dla axial↔axial,
* visible gdy physical component detected.

---

## 3. Numeracja spawów

Default:

* GLOBALNA dla całej izometryki.

Czyli:

```text
W-001
W-002
W-003
```

Powód:

* tak łatwiej śledzić weld map,
* łatwiej dla QC,
* łatwiej dla NDT,
* łatwiej dla prefab shop.

Ale architektura MUSI wspierać później:

* per spool,
* field weld numbering,
* shop weld numbering.

Czyli przygotuj:

```text
weld.numberingMode
```

Na przyszłość.

---

## 4. Mixed Units

System musi wspierać:

* mm,
* inch,
* feet-inch.

Parser ma akceptować:

```text
1500
59"
4'11"
```

Ale:
CAŁY PROJEKT powinien mieć PRIMARY UNIT SYSTEM.

Czyli:

* metric project,
* imperial project.

Wewnątrz:

* parser może przyjąć inne jednostki,
* ale system zawsze konwertuje do internal base unit.

Proponuję:

```text
internalUnit = mm
```

Czyli:

* wszystko trzymane wewnętrznie w mm,
* UI tylko formatuje.

To będzie bardzo ważne później dla:

* PCF,
* IFC,
* BOM,
* nesting,
* spool export.

---

## 5. Phase Plan

Tak — rób dokładnie tak:

Phase 1:

* minimal invasive,
* behaviour-preserving,
* nowa logika DimRef,
* weld auto-placement,
* component behavior flags,
* bez rozwalania obecnego workflow.

Osobny commit.

To ma być stabilny foundation layer.

---

## 6. Phase 2 — tutaj jest real value

Tu chcę:

* component behavior classes,
* real fabrication logic,
* smart cut calculations,
* reducer propagation,
* tee directional logic,
* weld intelligence,
* spool-aware architecture,
* spec-driven component sheets,
* future-ready prefab engine.

Projektuj to jak profesjonalny system pipingowy, a nie prosty kalkulator długości rur.
