/// Zagrożenia dymem wg materiału i procesu, NDS kluczowych składników
/// i minimalna ochrona dróg oddechowych.
///
/// Zasady zapisane w kodzie (i w testach):
/// * NDS podajemy TYLKO wtedy, gdy wartość potwierdzono w tekście
///   rozporządzenia (fume_sources.dart); bez potwierdzenia — `null`, a ekran
///   pisze „sprawdź aktualny wykaz NDS”;
/// * materiał „inne / nieznany” to najgorszy przypadek, nie „brak
///   zagrożeń”;
/// * minimalna ŚOI: nierdzewka, ocynk, powłoki, miedź/mosiądz, materiał
///   nieznany i każdy materiał bez SPRAWDZONEGO odciągu — P3 albo TH3;
///   stal węglowa i aluminium przy sprawdzonym odciągu — APF ≥ 20 (FFP3/P3,
///   TH2, TH3; HSE). FFP2 i TH1 nigdy nie wystarczają (APF 10).
///
/// Czysty Dart.
library;

import 'fume_sources.dart';

// ── Materiał i proces ──────────────────────────────────────────────────────

enum FumeMaterial {
  carbonSteel('Stal węglowa / niestopowa', 'Carbon / mild steel'),
  stainless('Nierdzewna, stal Cr-Ni', 'Stainless, Cr-Ni steel'),
  galvanised('Ocynk (stal ocynkowana)', 'Galvanised steel'),
  aluminium('Aluminium', 'Aluminium'),
  coated('Z powłoką / farbą', 'Painted / coated'),
  copper('Miedź, mosiądz, brąz', 'Copper, brass, bronze'),
  other('Inne / nieznany skład', 'Other / unknown');

  const FumeMaterial(this.labelPl, this.labelEn);
  final String labelPl;
  final String labelEn;
  String label({required bool en}) => en ? labelEn : labelPl;

  /// Materiał, przy którym minimum to P3/TH3 niezależnie od odciągu.
  bool get highHazard => switch (this) {
        FumeMaterial.carbonSteel || FumeMaterial.aluminium => false,
        _ => true,
      };

  static FumeMaterial? byName(Object? name) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return null;
  }
}

enum FumeProcess {
  mma('111 MMA (elektroda otulona)', '111 MMA (stick)'),
  migMag('131/135 MIG/MAG', '131/135 MIG/MAG'),
  fcaw('136/114 drut proszkowy', '136/114 flux-cored (FCAW)'),
  tig('141 TIG', '141 TIG'),
  cutting('Cięcie plazmą / gazem', 'Plasma / oxy-fuel cutting'),
  grinding('Szlifowanie', 'Grinding');

  const FumeProcess(this.labelPl, this.labelEn);
  final String labelPl;
  final String labelEn;
  String label({required bool en}) => en ? labelEn : labelPl;

  /// Proces w osłonie gazowej — za silny ciąg przy łuku zdmuchuje osłonę.
  bool get gasShielded =>
      this == FumeProcess.migMag ||
      this == FumeProcess.fcaw ||
      this == FumeProcess.tig;

  static FumeProcess? byName(Object? name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// Minimalna prędkość uchwycenia dla procesu [m/s] — próg tylko
/// zaostrzalny. Szlifowanie wyrzuca cząstki z dużą prędkością — osobna,
/// wyższa kategoria ACGIH ([kFumeCaptureGrindingMinMs]).
double fumeCaptureMinFor(FumeProcess? p) =>
    p == FumeProcess.grinding ? kFumeCaptureGrindingMinMs : kFumeCaptureMinMs;

// ── Składniki dymu ─────────────────────────────────────────────────────────

/// Jedna wartość NDS z rozporządzenia [mg/m³].
class FumeNds {
  const FumeNds(this.nds, {this.ndsch, this.fractionPl, this.fractionEn});

  /// NDS [mg/m³].
  final double nds;

  /// NDSCh [mg/m³] (null — przepis nie podaje).
  final double? ndsch;

  /// Frakcja: „wdychalna”, „respirabilna” (null — przepis nie podaje).
  final String? fractionPl;
  final String? fractionEn;

  String? fraction({required bool en}) => en ? fractionEn : fractionPl;
}

/// Składnik dymu / gazu.
enum FumeAgent {
  feOx(
    'Tlenki żelaza (Fe)',
    'Iron oxides (Fe)',
    'Główny składnik dymu ze stali. Odkładają się w płucach (syderoza); '
        'dym spawalniczy jako całość jest rakotwórczy (IARC grupa 1).',
    'The main part of steel fume. They build up in the lungs (siderosis); '
        'welding fume as a whole is carcinogenic (IARC group 1).',
    [
      FumeNds(5,
          ndsch: 10,
          fractionPl: 'frakcja wdychalna',
          fractionEn: 'inhalable fraction'),
      FumeNds(2.5,
          ndsch: 5,
          fractionPl: 'frakcja respirabilna',
          fractionEn: 'respirable fraction'),
    ],
    'jako Fe',
    'as Fe',
  ),
  mn(
    'Mangan (Mn)',
    'Manganese (Mn)',
    'Uszkadza układ nerwowy — po latach narażenia objawy podobne do choroby '
        'Parkinsona (drżenie, sztywność, zaburzenia chodu). Jest w dymie '
        'z każdej stali, więcej z drutów i elektrod o wysokiej zawartości Mn.',
    'Damages the nervous system — after years of exposure, symptoms like '
        'Parkinson’s disease (tremor, stiffness, walking problems). It is in '
        'the fume from every steel, more from high-Mn wires and electrodes.',
    [
      FumeNds(0.2,
          fractionPl: 'frakcja wdychalna', fractionEn: 'inhalable fraction'),
      FumeNds(0.05,
          fractionPl: 'frakcja respirabilna',
          fractionEn: 'respirable fraction'),
    ],
    'jako Mn',
    'as Mn',
  ),
  crVI(
    'Chrom sześciowartościowy Cr(VI)',
    'Hexavalent chromium Cr(VI)',
    'Rakotwórczy (płuca, nos i zatoki), niszczy przegrodę nosa, uczula skórę '
        'i drogi oddechowe (astma). Powstaje przy spawaniu i cięciu stali '
        'z chromem — najwięcej z elektrod otulonych i drutów proszkowych.',
    'Carcinogenic (lung, nose and sinuses), damages the nasal septum, '
        'sensitises skin and airways (asthma). Formed when welding and '
        'cutting chromium steels — most from covered electrodes and '
        'flux-cored wires.',
    [FumeNds(0.005)],
    'jako Cr(VI)',
    'as Cr(VI)',
  ),
  ni(
    'Nikiel i jego związki (Ni)',
    'Nickel and its compounds (Ni)',
    'Związki niklu są rakotwórcze (płuca, nos) i uczulają skórę oraz drogi '
        'oddechowe. Nierdzewka Cr-Ni, stopy niklu, spoiwa niklowe.',
    'Nickel compounds are carcinogenic (lung, nose) and sensitise skin and '
        'airways. Cr-Ni stainless, nickel alloys, nickel filler metals.',
    [
      FumeNds(0.05,
          fractionPl: 'frakcja wdychalna', fractionEn: 'inhalable fraction'),
      FumeNds(0.01,
          fractionPl: 'frakcja respirabilna',
          fractionEn: 'respirable fraction'),
    ],
    'związki niklu, jako Ni',
    'nickel compounds, as Ni',
  ),
  znO(
    'Tlenek cynku (ZnO)',
    'Zinc oxide (ZnO)',
    'Gorączka metaliczna: kilka godzin po spawaniu objawy jak grypa — '
        'dreszcze, gorączka, bóle mięśni, metaliczny posmak, kaszel. Ocynk, '
        'mosiądz, farby cynkowe.',
    'Metal fume fever: a few hours after welding, flu-like symptoms — '
        'chills, fever, aching muscles, metallic taste, cough. Galvanised '
        'steel, brass, zinc-rich paints.',
    [
      FumeNds(5,
          ndsch: 10,
          fractionPl: 'frakcja wdychalna',
          fractionEn: 'inhalable fraction'),
    ],
    'jako Zn',
    'as Zn',
  ),
  pb(
    'Ołów (Pb)',
    'Lead (Pb)',
    'Stare farby (minia ołowiana) i powłoki: uszkadza układ nerwowy, nerki '
        'i krew, szkodzi płodności i dziecku w ciąży; gromadzi się '
        'w organizmie.',
    'Old paints (red lead) and coatings: damages the nervous system, '
        'kidneys and blood, harms fertility and the unborn child; builds up '
        'in the body.',
    [
      FumeNds(0.03,
          fractionPl: 'frakcja wdychalna', fractionEn: 'inhalable fraction'),
    ],
    'jako Pb',
    'as Pb',
  ),
  cd(
    'Kadm (Cd)',
    'Cadmium (Cd)',
    'Powłoki kadmowe, niektóre luty srebrne: nawet krótkie narażenie może '
        'dać ciężki obrzęk płuc; uszkadza nerki, rakotwórczy.',
    'Cadmium plating, some silver brazing alloys: even a short exposure can '
        'cause severe lung oedema; damages kidneys, carcinogenic.',
    [
      FumeNds(0.001,
          fractionPl: 'frakcja wdychalna', fractionEn: 'inhalable fraction'),
    ],
    'jako Cd',
    'as Cd',
  ),
  o3(
    'Ozon (O₃)',
    'Ozone (O₃)',
    'Powstaje z tlenu pod wpływem UV z łuku — najwięcej przy MIG i TIG, '
        'zwłaszcza na aluminium. Drażni oczy, gardło i płuca; duże stężenia — '
        'obrzęk płuc. Filtry przeciwpyłowe (P2, P3) go nie zatrzymują.',
    'Formed from oxygen by the arc’s UV — most with MIG and TIG, '
        'especially on aluminium. Irritates eyes, throat and lungs; high '
        'levels — lung oedema. Particle filters (P2, P3) do not stop it.',
    [FumeNds(0.15)],
    null,
    null,
  ),
  nox(
    'Tlenki azotu (NO, NO₂)',
    'Nitrogen oxides (NO, NO₂)',
    'Cięcie plazmą, płomień gazowy, w mniejszym stopniu łuk TIG: drażnią '
        'płuca; obrzęk płuc może przyjść z opóźnieniem — kilka godzin po '
        'pracy. Filtry przeciwpyłowe ich nie zatrzymują.',
    'Plasma cutting, gas flames and, less, the TIG arc: irritate the lungs; '
        'lung oedema may come hours after work. Particle filters do not stop '
        'them.',
    [FumeNds(0.7, ndsch: 1.5), FumeNds(2.5)],
    'NO₂ (pierwsza), NO (druga)',
    'NO₂ (first), NO (second)',
  ),
  co(
    'Tlenek węgla (CO)',
    'Carbon monoxide (CO)',
    'MAG w CO₂ i mieszankach z CO₂, płomień gazowy: bez zapachu, zatrucie — '
        'groźne zwłaszcza w ciasnych miejscach. Filtry przeciwpyłowe go nie '
        'zatrzymują.',
    'MAG with CO₂ and CO₂ mixes, gas flames: odourless, poisoning — '
        'dangerous especially in tight spaces. Particle filters do not stop '
        'it.',
    [FumeNds(23, ndsch: 117)],
    'w ppm: 20 (NDSCh 100)',
    'in ppm: 20 (STEL 100)',
  ),
  fluorides(
    'Fluorki (F)',
    'Fluorides (F)',
    'Z otuliny zasadowej elektrod i topnika drutów proszkowych: drażnią oczy '
        'i drogi oddechowe.',
    'From basic electrode coatings and flux-cored wire flux: irritate eyes '
        'and airways.',
    [FumeNds(2)],
    'jako F',
    'as F',
  ),
  al(
    'Glin (Al) — tlenek glinu',
    'Aluminium (Al) — aluminium oxide',
    'Dym z aluminium drażni drogi oddechowe; przy długim narażeniu zmiany '
        'w płucach. Główny problem przy MIG/TIG na aluminium to jednak ozon.',
    'Aluminium fume irritates the airways; long exposure can change the '
        'lungs. With MIG/TIG on aluminium the main problem is ozone, though.',
    null,
    null,
    null,
  ),
  cu(
    'Miedź (Cu)',
    'Copper (Cu)',
    'Dym z miedzi drażni i może dać gorączkę metaliczną. Mosiądz to miedź '
        'z cynkiem (ZnO). Miedź berylowa: beryl jest rakotwórczy — wymaga '
        'osobnej oceny ryzyka.',
    'Copper fume irritates and can cause metal fume fever. Brass is copper '
        'with zinc (ZnO). Beryllium copper: beryllium is carcinogenic — needs '
        'its own risk assessment.',
    null,
    null,
    null,
  ),
  coatingOrganics(
    'Produkty rozkładu powłok',
    'Coating breakdown products',
    'Farby, podkłady, oleje, kleje, tworzywa: w łuku i płomieniu rozkładają '
        'się na aldehydy, izocyjaniany, CO i inne — skład zależy od powłoki '
        '(karta charakterystyki farby). Najlepiej usunąć powłokę ze strefy '
        'spawania.',
    'Paints, primers, oils, adhesives, plastics: the arc and flame break '
        'them down into aldehydes, isocyanates, CO and more — what exactly '
        'depends on the coating (the paint’s safety data sheet). Best: '
        'remove the coating from the weld area.',
    null,
    null,
    null,
  ),
  dust(
    'Pył metali (szlifowanie)',
    'Metal dust (grinding)',
    'Cząstki większe niż w dymie, skład jak szlifowany materiał '
        '(nierdzewka: Cr, Ni; powłoki: Pb, Zn) plus ścierniwo. Odciąg przy '
        'tarczy musi łapać strumień wyrzucanych cząstek.',
    'Particles larger than in fume, made of the ground material (stainless: '
        'Cr, Ni; coatings: Pb, Zn) plus abrasive. Extraction at the disc has '
        'to catch the stream of thrown particles.',
    null,
    null,
    null,
  ),
  unknown(
    'Skład nieznany',
    'Unknown composition',
    'Bez karty charakterystyki materiału i spoiwa nie wiadomo, co jest '
        'w dymie — przyjmij najgorszy przypadek (jak nierdzewka i powłoki), '
        'dopóki nie ustalisz składu.',
    'Without the safety data sheets of the material and filler you do not '
        'know what is in the fume — assume the worst case (as for stainless '
        'and coatings) until you find out.',
    null,
    null,
    null,
  );

  const FumeAgent(this.namePl, this.nameEn, this.effectPl, this.effectEn,
      this.nds, this.ndsNotePl, this.ndsNoteEn);

  final String namePl;
  final String nameEn;
  final String effectPl;
  final String effectEn;

  /// Wartości NDS potwierdzone w rozporządzeniu; `null` — nie podajemy
  /// liczby (brak potwierdzenia albo skład zależy od powłoki).
  final List<FumeNds>? nds;

  /// Dopisek do wartości („jako Mn”, „NO₂ (pierwsza), NO (druga)”).
  final String? ndsNotePl;
  final String? ndsNoteEn;

  String title({required bool en}) => en ? nameEn : namePl;
  String effect({required bool en}) => en ? effectEn : effectPl;
  String? ndsNote({required bool en}) => en ? ndsNoteEn : ndsNotePl;
}

/// Składniki z materiału.
List<FumeAgent> _materialAgents(FumeMaterial m) => switch (m) {
      FumeMaterial.carbonSteel => const [FumeAgent.feOx, FumeAgent.mn],
      FumeMaterial.stainless => const [
          FumeAgent.crVI,
          FumeAgent.ni,
          FumeAgent.mn,
          FumeAgent.feOx,
        ],
      FumeMaterial.galvanised => const [
          FumeAgent.znO,
          FumeAgent.feOx,
          FumeAgent.mn,
        ],
      FumeMaterial.aluminium => const [FumeAgent.al],
      FumeMaterial.coated => const [
          FumeAgent.pb,
          FumeAgent.cd,
          FumeAgent.znO,
          FumeAgent.coatingOrganics,
          FumeAgent.feOx,
          FumeAgent.mn,
        ],
      FumeMaterial.copper => const [FumeAgent.cu, FumeAgent.znO],
      FumeMaterial.other => const [FumeAgent.unknown],
    };

/// Składniki z procesu.
List<FumeAgent> _processAgents(FumeProcess p) => switch (p) {
      FumeProcess.mma => const [FumeAgent.fluorides],
      FumeProcess.migMag => const [FumeAgent.o3, FumeAgent.co],
      FumeProcess.fcaw => const [FumeAgent.fluorides, FumeAgent.co],
      FumeProcess.tig => const [FumeAgent.o3, FumeAgent.nox],
      FumeProcess.cutting => const [FumeAgent.nox, FumeAgent.co],
      FumeProcess.grinding => const [FumeAgent.dust],
    };

/// Wiersz listy zagrożeń.
class FumeHazard {
  const FumeHazard(this.agent, {this.emphasised = false});
  final FumeAgent agent;

  /// Ten składnik jest przy tej parze materiał–proces szczególnie istotny
  /// (np. Cr(VI) przy MMA na nierdzewce, ozon przy MIG/TIG na aluminium).
  final bool emphasised;
}

/// Zagrożenia dla pary materiał–proces: najpierw z materiału, potem
/// z procesu, bez powtórzeń.
List<FumeHazard> fumeHazards(FumeMaterial m, FumeProcess p) {
  final seen = <FumeAgent>{};
  final out = <FumeHazard>[];
  for (final a in [..._materialAgents(m), ..._processAgents(p)]) {
    if (!seen.add(a)) continue;
    out.add(FumeHazard(a, emphasised: _emphasised(a, m, p)));
  }
  return out;
}

bool _emphasised(FumeAgent a, FumeMaterial m, FumeProcess p) {
  switch (a) {
    case FumeAgent.crVI:
      return p == FumeProcess.mma ||
          p == FumeProcess.fcaw ||
          p == FumeProcess.cutting;
    case FumeAgent.o3:
      return m == FumeMaterial.aluminium;
    case FumeAgent.znO:
      return m == FumeMaterial.galvanised;
    case FumeAgent.pb:
    case FumeAgent.cd:
    case FumeAgent.unknown:
      return true;
    case FumeAgent.nox:
      return p == FumeProcess.cutting;
    default:
      return false;
  }
}

/// Krótka uwaga o procesie (ilość dymu i co z niej wynika).
(String, String) fumeProcessNote(FumeProcess p) => switch (p) {
      FumeProcess.mma => (
          'Dużo dymu. Na nierdzewce elektroda otulona daje najwięcej Cr(VI) '
              'z procesów łukowych.',
          'A lot of fume. On stainless, covered electrodes give the most '
              'Cr(VI) of the arc processes.'
        ),
      FumeProcess.migMag => (
          'Dymu zwykle mniej niż przy MMA i drucie proszkowym, ale przy '
              'dużym prądzie dużo. UV z łuku robi ozon, CO₂ w gazie — CO.',
          'Usually less fume than MMA and flux-cored, but a lot at high '
              'current. The arc’s UV makes ozone, CO₂ in the gas makes CO.'
        ),
      FumeProcess.fcaw => (
          'Najwięcej dymu z procesów łukowych. Na nierdzewce — dużo Cr(VI).',
          'The most fume of the arc processes. On stainless — a lot of '
              'Cr(VI).'
        ),
      FumeProcess.tig => (
          'Mało dymu, ale silne UV: ozon i tlenki azotu. „Nie dymi” nie '
              'znaczy „bezpiecznie” — zwłaszcza na aluminium i nierdzewce.',
          'Little fume, but strong UV: ozone and nitrogen oxides. “No smoke” '
              'does not mean “safe” — especially on aluminium and stainless.'
        ),
      FumeProcess.cutting => (
          'Bardzo dużo dymu i tlenki azotu; na powłokach i ocynku — ołów, '
              'cynk. Najlepiej stół z odciągiem dolnym.',
          'A lot of fume and nitrogen oxides; on coatings and galvanising — '
              'lead, zinc. A downdraft cutting table works best.'
        ),
      FumeProcess.grinding => (
          'Pył, nie dym — cząstki lecą z prędkością tarczy, więc odciąg '
              'potrzebuje znacznie większej prędkości uchwycenia niż przy '
              'spawaniu.',
          'Dust, not fume — particles fly at disc speed, so extraction needs '
              'a much higher capture velocity than for welding.'
        ),
    };

// ── Ochrona dróg oddechowych ───────────────────────────────────────────────

/// Sprzęt ochrony dróg oddechowych (klasa).
enum FumeRpe {
  none('Brak', 'None'),
  p2('FFP2 / półmaska + P2', 'FFP2 / half mask + P2'),
  p3('FFP3 / półmaska + P3', 'FFP3 / half mask + P3'),
  th1('TH1 — przyłbica z nawiewem', 'TH1 — powered welding helmet'),
  th2('TH2 — przyłbica z nawiewem', 'TH2 — powered welding helmet'),
  th3('TH3 — przyłbica z nawiewem', 'TH3 — powered welding helmet');

  const FumeRpe(this.labelPl, this.labelEn);
  final String labelPl;
  final String labelEn;
  String label({required bool en}) => en ? labelEn : labelPl;

  /// Sprzęt szczelnie przylegający do twarzy — wymaga testu dopasowania
  /// i gładko ogolonej strefy uszczelnienia.
  bool get tightFitting => this == FumeRpe.p2 || this == FumeRpe.p3;

  /// Sprzęt z wymuszonym przepływem (EN 12941).
  bool get powered =>
      this == FumeRpe.th1 || this == FumeRpe.th2 || this == FumeRpe.th3;

  static FumeRpe? byName(Object? name) {
    for (final r in values) {
      if (r.name == name) return r;
    }
    return null;
  }
}

/// Minimalny poziom ŚOI.
enum FumeRpeRequirement {
  /// Przypisany współczynnik ochrony co najmniej 20 (HSE: „APF of at least
  /// 20” dla spawaczy): FFP3 / półmaska + P3 (HSE: do ok. godziny pracy),
  /// TH2, TH3. FFP2 / P2 (APF 10) i TH1 (APF 10, DGUV 5) — nie.
  apf20,

  /// Co najmniej P3 albo TH3: FFP3 / półmaska + P3, TH3.
  p3OrTh3;
}

/// Minimum ŚOI dla materiału. [levEffective] — odciąg u źródła jest
/// i kalkulator potwierdził zasięg (ocena „ok”). Bez sprawdzonego odciągu
/// i dla materiałów [FumeMaterial.highHazard] — P3 albo TH3; stal węglowa
/// i aluminium przy sprawdzonym odciągu — APF ≥ 20 na dym resztkowy.
FumeRpeRequirement fumeRpeRequirement(FumeMaterial m,
    {required bool levEffective}) {
  if (m.highHazard || !levEffective) return FumeRpeRequirement.p3OrTh3;
  return FumeRpeRequirement.apf20;
}

/// Czy sprzęt spełnia minimum.
bool fumeRpeMeets(FumeRpe r, FumeRpeRequirement req) => switch (req) {
      FumeRpeRequirement.apf20 =>
        r == FumeRpe.p3 || r == FumeRpe.th2 || r == FumeRpe.th3,
      FumeRpeRequirement.p3OrTh3 => r == FumeRpe.p3 || r == FumeRpe.th3,
    };
