/// Spoiny projektu CUT (lista cięć: odcinki rury + kształtki) jako
/// [ImportWeld] dla importu do wyceny (`domain/quotes/quote_import.dart` —
/// grupowanie, wymiary, pozycja są tam, nie tutaj).
///
/// Model CUT: odcinek (`segments`) to kawałek rury między dwoma końcami,
/// START i END. Koniec to „koniec otwarty" (`*_kind = logical`) albo
/// kształtka: wpis biblioteki (`*_library_id` → typ ELB90 / ELB45 / TEE /
/// REDUCER / FLANGE / VALVE) albo — w projektach ze skanu / szkicu ISO —
/// sam rodzaj bez typu (`axial` = kolano / trójnik / olet, `nonAxial` =
/// kołnierz / zawór / redukcja / zaślepka). Każdy odcinek ma swoją OD
/// i ściankę (za redukcją ekran trasy pyta o nową ściankę). Spoin projekt
/// nie zapisuje — liczymy je z tego, co zapisuje.
///
/// REGUŁY (podgląd importu pokazuje je jako „założenia"):
///  1. Spoina na każdym końcu odcinka przy kształtce — tam, gdzie CUT
///     odejmuje szczelinę spoiny ([PrefabEngine.weldCountForEnds]). Wymiar
///     spoiny = OD i ścianka TEGO odcinka, więc rura–kolano–rura to 2 spoiny,
///     trójnik z trzema odcinkami — 3, redukcja — 2 o różnych średnicach.
///  2. Kolano, trójnik, redukcja z biblioteki — doczołowa (BW); tak samo
///     koniec `axial` z wpisem usuniętym z biblioteki (osiowe w bibliotece to
///     tylko kolana i trójniki). Koniec `axial` bez wpisu (skan / szkic:
///     kolano, trójnik albo olet) — spoina na pewno jest, rodzaju dane nie
///     mówią: idzie bez oznaczenia, wycena przyjmuje doczołową i pokazuje to
///     jako założenie (jak przy dzienniku spoin).
///  3. Kołnierz i zawór — CUT nie zapisuje, jak są łączone. Bez decyzji
///     montera ([CutEndJoint.unknown]) spoina idzie do „do sprawdzenia"
///     ([ImportSkipReason.flangeType] / [ImportSkipReason.valveEnds]).
///     Decyzja w podglądzie: kołnierz WN / zawór BW → doczołowa; kołnierz
///     SO, SW / zawór SW → pachwinowa; luźny, gwintowany / zawór kołnierzowy,
///     gwintowany → bez spoiny. Para kołnierzy skręcona śrubami (koniec
///     odcinka i początek następnego) to dwie spoiny — każda z rurą.
///  4. Kształtka z korpusem bez typu (`nonAxial` ze skanu / szkicu albo po
///     usuniętym wpisie, nieznany typ / rodzaj) — może to być kołnierz luźny
///     (bez spoiny) albo redukcja (BW): do sprawdzenia
///     ([ImportSkipReason.fittingType]).
///  5. Koniec otwarty — bez spoiny (CUT nie odejmuje tam szczeliny). Spoiny
///     rura–rura na końcach otwartych (np. montażowe) nie są w projekcie.
///  6. Odcinek dłuższy niż sztanga — lista cięć dzieli go
///     ([splitCutLengths], ta sama długość sztangi i szczelina): każdy
///     podział to doczołowa rura–rura w wymiarze odcinka.
///  7. Wolny koniec kształtki: kolano / trójnik / redukcja z biblioteki ma
///     spoinę na każdym końcu (2 / 3 / 2). Sztuki liczy ta sama reguła co
///     zestawienie materiałów ([MaterialListBuilder.countFittings]); koniec
///     sztuki bez odcinka rury w projekcie (np. odgałęzienie trójnika bez
///     odcinka, kolano spawane wprost do kolejnej kształtki albo trasa
///     dalej poza projektem) idzie do „do sprawdzenia"
///     ([ImportSkipReason.openPort]) — co jest po drugiej stronie, nie
///     wiadomo. Projekt budowany nie po kolei (sąsiedztwo = kolejność
///     odcinków) też trafi tutaj — tylko do sprawdzenia, nie do ceny.
///     Licznik może być zawyżony: dwie RÓŻNE kształtki spawane wprost do
///     siebie (kolano 90° → kolano 45°, bez rury) to jedna spoina, a dwa
///     wolne końce — model nie odróżnia tego od dwóch spoin z czymś spoza
///     projektu, więc nie łączymy ich na zgadywanie.
///  8. Odgałęzienia wspawane bez trójnika (olet, króciec nasadzany — BR):
///     spoiny z rurą główną CUT nie zapisuje; import ich nie zna.
///  9. Pozycja spawania i warsztat / obiekt — projekt ich nie ma: pozycja
///     z wyceny ([defaultImportPosition]), jako założenie.
///
/// Typ wpisu biblioteki porównywany po `trim().toUpperCase()` ([_typeOf]).
/// Odczyt jest odporny na uszkodzone wiersze: odcinki każdego projektu
/// czytane osobno — projekt, którego odcinków nie da się odczytać, wraca
/// z [CutImportProject.readError] (lista pokazuje go jako nieaktywny),
/// a pozostałe działają; wpis biblioteki, którego nie da się odczytać,
/// jest traktowany jak usunięty (reguły 2 i 4 — nic nie jest zgadywane).
library;

import '../database/component_library_dao.dart';
import '../database/project_dao.dart';
import '../database/segment_dao.dart';
import '../domain/quotes/quote_import.dart';
import '../domain/weld_journal/weld_entry.dart' show WeldJointType;
import '../models/library_component.dart';
import '../models/project.dart';
import '../models/segment.dart';
import 'bar_nesting.dart' show splitCutLengths;
import 'cut_list_summary.dart' show segmentLabel;
import 'material_list_builder.dart';

/// Jak kołnierz / zawór łączy się z rurą — CUT tego nie zapisuje, więc
/// decyduje monter w podglądzie importu.
enum CutEndJoint {
  /// Nie wiadomo — spoina do sprawdzenia, nie do wyceny.
  unknown,

  /// Doczołowa: kołnierz szyjkowy (WN), zawór do wspawania (BW).
  butt,

  /// Pachwinowa: kołnierz płaski nasuwany (SO) / mufowy (SW), zawór mufowy.
  fillet,

  /// Bez spoiny: kołnierz luźny / gwintowany, zawór kołnierzowy / gwintowany.
  none,
}

/// Projekt CUT z odcinkami (w kolejności `seq_no`) i wpisami biblioteki,
/// których używają (id → wpis; brak klucza = wpis usunięty).
class CutImportProject {
  final Project project;
  final List<Segment> segments;
  final Map<String, LibraryComponent> library;

  /// Odcinków projektu nie dało się odczytać (uszkodzony wiersz) —
  /// [segments] puste, projekt nie do importu.
  final bool readError;

  const CutImportProject({
    required this.project,
    required this.segments,
    this.library = const {},
    this.readError = false,
  });
}

/// Decyzje montera i słowa numeracji spoin („S03 pocz.", „S03 kon.").
class CutImportOptions {
  final CutEndJoint flanges;
  final CutEndJoint valves;

  /// Dopisek przy spoinie na początku / końcu odcinka.
  final String startTag;
  final String endTag;

  const CutImportOptions({
    this.flanges = CutEndJoint.unknown,
    this.valves = CutEndJoint.unknown,
    this.startTag = 'start',
    this.endTag = 'end',
  });
}

/// Spoiny projektu (także te „do sprawdzenia", z [ImportWeld.skip]) i ile
/// końców odcinków stoi na kołnierzach / zaworach — po tym podgląd wie, czy
/// pytać o ich typ.
class CutProjectWelds {
  final List<ImportWeld> welds;
  final int flangeEnds;
  final int valveEnds;

  const CutProjectWelds({
    required this.welds,
    required this.flangeEnds,
    required this.valveEnds,
  });
}

/// Typy biblioteki, które są kształtkami do spawania doczołowego.
const Set<String> _kButtFittings = {'ELB90', 'ELB45', 'TEE', 'REDUCER'};

/// Typ wpisu biblioteki tak, jak go porównujemy — „ tee", „Elb90" to TEE,
/// ELB90. JEDNO miejsce: rodzaj spoiny, liczba końców sztuki i opis wolnego
/// końca muszą widzieć ten sam typ, inaczej spoiny i wolne końce by się
/// rozjechały.
String _typeOf(LibraryComponent c) => c.type.trim().toUpperCase();

enum _End { open, butt, unmarked, flange, valve, unknownType }

_End _classify(
    String kind, String? libraryId, Map<String, LibraryComponent> library) {
  if (kind == 'logical') return _End.open;
  final comp = libraryId == null ? null : library[libraryId];
  if (comp != null) {
    final type = _typeOf(comp);
    if (_kButtFittings.contains(type)) return _End.butt;
    if (type == 'FLANGE') return _End.flange;
    if (type == 'VALVE') return _End.valve;
    return _End.unknownType;
  }
  if (libraryId != null) {
    // Wpis usunięty z biblioteki: osiowe w bibliotece to tylko kolana
    // i trójniki — doczołowe; z korpusem — kołnierz, zawór albo redukcja.
    return kind == 'axial' ? _End.butt : _End.unknownType;
  }
  // Skan / szkic: typu nie ma. Osiowa (kolano / trójnik / olet) — spoina
  // jest; z korpusem albo rodzaj spoza słownika — nie wiadomo.
  return kind == 'axial' ? _End.unmarked : _End.unknownType;
}

/// Spoiny projektu [p] według reguł z opisu biblioteki, w kolejności trasy:
/// dla każdego odcinka spoina początku, spoiny podziału, spoina końca; na
/// końcu wolne końce kształtek.
CutProjectWelds importWeldsFromCutProject(
  CutImportProject p, {
  CutImportOptions options = const CutImportOptions(),
}) {
  final ordered = [...p.segments]..sort((a, b) => a.seqNo.compareTo(b.seqNo));
  final welds = <ImportWeld>[];
  var flangeEnds = 0;
  var valveEnds = 0;

  ImportWeld weld(Segment s, String ref,
          {String type = '', ImportSkipReason? skip}) =>
      ImportWeld(
        ref: ref,
        jointType: type,
        odMm: s.diameterMm,
        wallMm: s.wallThicknessMm,
        skip: skip,
      );

  void chosen(Segment s, String ref, CutEndJoint choice, String filletCode,
      ImportSkipReason unknown) {
    switch (choice) {
      case CutEndJoint.unknown:
        welds.add(weld(s, ref, skip: unknown));
      case CutEndJoint.butt:
        welds.add(weld(s, ref, type: WeldJointType.butt));
      case CutEndJoint.fillet:
        welds.add(weld(s, ref, type: filletCode));
      case CutEndJoint.none:
        break;
    }
  }

  void end(Segment s, String kind, String? libraryId, String ref) {
    switch (_classify(kind, libraryId, p.library)) {
      case _End.open:
        break;
      case _End.butt:
        welds.add(weld(s, ref, type: WeldJointType.butt));
      case _End.unmarked:
        welds.add(weld(s, ref));
      case _End.flange:
        flangeEnds++;
        chosen(s, ref, options.flanges, WeldJointType.fillet,
            ImportSkipReason.flangeType);
      case _End.valve:
        valveEnds++;
        chosen(s, ref, options.valves, WeldJointType.socket,
            ImportSkipReason.valveEnds);
      case _End.unknownType:
        welds.add(weld(s, ref, skip: ImportSkipReason.fittingType));
    }
  }

  for (final s in ordered) {
    final mark = segmentLabel(s);
    end(s, s.startKind, s.startLibraryId, '$mark ${options.startTag}');
    final parts = s.cutMm.isFinite && s.cutMm > 0
        ? splitCutLengths(s.cutMm,
                stockLengthMm: p.project.stockLengthMm,
                joinGapMm: p.project.gapMm)
            .length
        : 1;
    for (var i = 1; i < parts; i++) {
      welds.add(weld(s, '$mark ($i|${i + 1})', type: WeldJointType.butt));
    }
    end(s, s.endKind, s.endLibraryId, '$mark ${options.endTag}');
  }
  welds.addAll(_openPorts(ordered, p.library));
  return CutProjectWelds(
    welds: List.unmodifiable(welds),
    flangeEnds: flangeEnds,
    valveEnds: valveEnds,
  );
}

String _mm(double v) => v.toStringAsFixed(1);

/// „TEE Ø114.3", „REDUCER Ø114.3→60.3" — jak wpis biblioteki na liście CUT.
String _fittingRef(LibraryComponent c) {
  final type = _typeOf(c);
  final out = c.diameterOutMm;
  return type == 'REDUCER' && out != null
      ? '$type Ø${_mm(c.diameterMm)}→${_mm(out)}'
      : '$type Ø${_mm(c.diameterMm)}';
}

/// Końce sztuki wpisu [c] — [MaterialListBuilder.portsForType] (reguła
/// zestawienia materiałów, bez zmian) dla typu znormalizowanego tutaj.
int _portsOf(LibraryComponent? c) =>
    MaterialListBuilder.portsForType(c == null ? null : _typeOf(c));

/// Reguła 7: końce sztuk kolan / trójników / redukcji bez odcinka rury.
///
/// Dwa wolne końce sąsiednich odcinków na RÓŻNYCH kształtkach (koniec S01 na
/// kolanie 90°, początek S02 na kolanie 45°) to albo jedna spoina kolano–
/// kolano, albo dwie spoiny z czymś spoza projektu (nowa gałąź, druga
/// sztuka, odcinki budowane nie po kolei) — model tego nie rozróżnia, więc
/// liczone są oba końce; licznik „do sprawdzenia" może być wtedy zawyżony
/// (mówią o tym założenia w podglądzie). Do ceny nie idzie żaden.
List<ImportWeld> _openPorts(
    List<Segment> ordered, Map<String, LibraryComponent> library) {
  int portsOf(FittingKey key) =>
      key.libraryId == null ? 2 : _portsOf(library[key.libraryId]);
  final pieces = MaterialListBuilder.countFittings(ordered, portsOf: portsOf);
  // Końce odcinków na wpisie — liczone jak w countFittings (po id wpisu).
  final ends = <String, int>{};
  for (final s in ordered) {
    for (final id in [s.startLibraryId, s.endLibraryId]) {
      if (id != null) ends[id] = (ends[id] ?? 0) + 1;
    }
  }
  final out = <ImportWeld>[];
  for (final e in pieces.entries) {
    final id = e.key.libraryId;
    final comp = id == null ? null : library[id];
    if (comp == null || !_kButtFittings.contains(_typeOf(comp))) continue;
    final free = e.value * _portsOf(comp) - (ends[id] ?? 0);
    for (var i = 0; i < free; i++) {
      out.add(ImportWeld(
        ref: _fittingRef(comp),
        jointType: WeldJointType.butt,
        // Który koniec redukcji jest wolny — nie wiadomo.
        odMm: _typeOf(comp) == 'REDUCER' ? null : comp.diameterMm,
        wallMm: comp.wallThicknessMm,
        skip: ImportSkipReason.openPort,
      ));
    }
  }
  return out;
}

/// Projekt CUT ze stali nierdzewnej (`material_group = SS`).
bool cutProjectIsStainless(Project p) =>
    p.materialGroup.trim().toUpperCase() == 'SS';

/// Etykieta pozycji wyceny z projektu: nazwa, inaczej numer ISO z rewizją,
/// inaczej numer linii; pusta, gdy nic z tego nie ma.
String cutImportLabel(Project p, {required bool english}) {
  final name = p.name?.trim() ?? '';
  if (name.isNotEmpty) return name;
  final identity = p.identity;
  return identity.isoWithRev(english: english) ?? identity.lineNo ?? '';
}

/// Wszystkie projekty CUT (ostatnio zmieniane pierwsze) z odcinkami
/// i wpisami biblioteki — tylko odczyt.
///
/// Uszkodzony wiersz odcinka psuje tylko swój projekt
/// ([CutImportProject.readError]), nie całą listę. Uszkodzony wiersz
/// biblioteki: wpisy czytane wtedy pojedynczo, a ten jeden — jak usunięty.
/// Błąd samej listy projektów (wiersz `projects`) leci dalej — tej listy nie
/// ma z czego zbudować.
Future<List<CutImportProject>> loadCutProjectsForImport({
  ProjectDao? projects,
  SegmentDao? segments,
  ComponentLibraryDao? library,
}) async {
  final segmentDao = segments ?? SegmentDao();
  final libraryDao = library ?? ComponentLibraryDao();
  final list = await (projects ?? ProjectDao()).listAll();
  final read = <({Project project, List<Segment>? segments})>[];
  for (final p in list) {
    List<Segment>? segs;
    try {
      segs = await segmentDao.listForProject(p.id);
    } catch (_) {
      segs = null;
    }
    read.add((project: p, segments: segs));
  }
  final entries = <String, LibraryComponent>{};
  try {
    for (final c in await libraryDao.listAll()) {
      entries[c.id] = c;
    }
  } catch (_) {
    entries.clear();
    final ids = {
      for (final r in read)
        for (final s in r.segments ?? const <Segment>[])
          for (final id in [s.startLibraryId, s.endLibraryId])
            if (id != null) id,
    };
    for (final id in ids) {
      try {
        final c = await libraryDao.getById(id);
        if (c != null) entries[id] = c;
      } catch (_) {
        // Nieczytelny wpis = usunięty: reguły 2 i 4, bez zgadywania.
      }
    }
  }
  return [
    for (final r in read)
      CutImportProject(
        project: r.project,
        segments: r.segments ?? const [],
        library: entries,
        readError: r.segments == null,
      ),
  ];
}
