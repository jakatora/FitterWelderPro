import 'package:flutter/material.dart';

import '../i18n/app_language.dart';

const _kCard   = Color(0xFF1A1D26);
const _kBorder = Color(0xFF2C3354);
const _kOrange = Color(0xFFF5A623);
const _kBlue   = Color(0xFF4A9EFF);
const _kRed    = Color(0xFFE74C3C);
const _kSec    = Color(0xFF9BA3C7);
const _kMuted  = Color(0xFF55607A);

class _Step {
  final String pl;
  final String en;
  const _Step(this.pl, this.en);
}

// Post-weld surface treatment guide for stainless steel in food & pharma.
// This is a PROCESS guide — the steps, the order, the hazards — not a recipe:
// concentrations and dwell times always come from the product data sheet of
// the paste/bath actually used, and from the project specification.

const List<_Step> _pickling = [
  _Step('Odtłuść spoinę i strefę wpływu ciepła — brak smaru, oleju, odcisków palców.',
        'Degrease the weld and heat-affected zone — no grease, oil or fingerprints.'),
  _Step('Usuń luźne tlenki / żużel mechanicznie szczotką ze stali nierdzewnej (dedykowaną).',
        'Remove loose oxide / slag mechanically with a dedicated stainless brush.'),
  _Step('Nałóż pastę trawiącą równomiernie na spoinę i przebarwienia (heat tint).',
        'Apply pickling paste evenly over the weld and the heat-tint band.'),
  _Step('Odczekaj czas oddziaływania WG KARTY PRODUKTU — zależny od temperatury otoczenia.',
        'Leave for the dwell time PER THE DATA SHEET — depends on ambient temperature.'),
  _Step('Spłucz obficie wodą demineralizowaną — usuń całą pastę, też od wewnątrz rury.',
        'Rinse thoroughly with demineralised water — remove all paste, inside the tube too.'),
  _Step('Sprawdź: powierzchnia jednolicie matowa, bez przebarwień i śladów pasty.',
        'Check: surface uniformly matt, no tint and no paste residue left.'),
];

const List<_Step> _passivation = [
  _Step('Wykonaj po piklingu i dokładnym płukaniu — powierzchnia czysta i sucha.',
        'Do this after pickling and a full rinse — surface clean and dry.'),
  _Step('Nałóż środek pasywujący (kwas azotowy lub — bezpieczniejszy — kwas cytrynowy).',
        'Apply the passivation agent (nitric acid or — safer — citric acid).'),
  _Step('Odczekaj czas WG SPECYFIKACJI / karty produktu.',
        'Leave for the time PER THE SPECIFICATION / data sheet.'),
  _Step('Spłucz wodą demineralizowaną i wysusz czystym, niepylącym materiałem.',
        'Rinse with demineralised water and dry with a clean, lint-free cloth.'),
  _Step('Wykonaj test pasywacji (np. ferroxyl / test wilgotnościowy) jeśli wymaga specyfikacja.',
        'Run a passivation test (e.g. ferroxyl / humidity test) if the spec requires it.'),
];

class PassivationScreen extends StatelessWidget {
  const PassivationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr(
              pl: 'Trawienie i pasywacja', en: 'Pickling & passivation')),
          bottom: TabBar(
            tabs: [
              Tab(text: context.tr(pl: 'Trawienie', en: 'Pickling')),
              Tab(text: context.tr(pl: 'Pasywacja', en: 'Passivation')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _StepList(
              intro: context.tr(
                pl: 'Trawienie (pickling) usuwa przebarwienia i warstwę zubożoną '
                    'w chrom po spawaniu — przywraca odporność korozyjną spoiny.',
                en: 'Pickling removes heat tint and the chromium-depleted layer '
                    'left by welding — it restores the weld\'s corrosion resistance.',
              ),
              steps: _pickling,
              showHfWarning: true,
            ),
            _StepList(
              intro: context.tr(
                pl: 'Pasywacja odtwarza pasywną warstwę tlenku chromu na '
                    'powierzchni — wymóg dla instalacji spożywczych i farmaceutycznych.',
                en: 'Passivation rebuilds the passive chromium-oxide layer on the '
                    'surface — a requirement for food and pharma installations.',
              ),
              steps: _passivation,
              showHfWarning: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepList extends StatelessWidget {
  final String intro;
  final List<_Step> steps;
  final bool showHfWarning;
  const _StepList({
    required this.intro,
    required this.steps,
    required this.showHfWarning,
  });

  @override
  Widget build(BuildContext context) {
    final isPl = context.language == AppLanguage.pl;
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        Text(intro,
            style: const TextStyle(color: _kSec, fontSize: 13, height: 1.5)),
        const SizedBox(height: 16),
        ...steps.asMap().entries.map((e) {
          final i = e.key;
          final s = e.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26, height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _kBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          color: _kBlue,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(isPl ? s.pl : s.en,
                      style: const TextStyle(
                          color: Color(0xFFE8ECF0),
                          fontSize: 13,
                          height: 1.45)),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),

        // Mandatory safety note.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kRed.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kRed.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.dangerous_outlined, color: _kRed, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  showHfWarning
                      ? context.tr(
                          pl: 'BHP: pasty trawiące zawierają kwas fluorowodorowy (HF) — '
                              'skrajnie niebezpieczny, wchłania się przez skórę. Wymagane: '
                              'odzież kwasoodporna, gogle, wentylacja, glukonian wapnia w '
                              'zasięgu. Zawsze stosuj kartę charakterystyki (SDS).',
                          en: 'SAFETY: pickling pastes contain hydrofluoric acid (HF) — '
                              'extremely hazardous, absorbed through skin. Required: '
                              'acid-resistant PPE, goggles, ventilation, calcium gluconate '
                              'on hand. Always follow the safety data sheet (SDS).',
                        )
                      : context.tr(
                          pl: 'BHP: środki pasywujące to kwasy — stosuj odzież ochronną, '
                              'gogle i wentylację. Zawsze według karty charakterystyki (SDS). '
                              'Stężenia i czasy — wg karty produktu, nie z pamięci.',
                          en: 'SAFETY: passivation agents are acids — use protective PPE, '
                              'goggles and ventilation. Always per the safety data sheet '
                              '(SDS). Concentrations and times — from the data sheet, not memory.',
                        ),
                  style: const TextStyle(color: _kSec, fontSize: 12, height: 1.45),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.menu_book_outlined, color: _kOrange, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr(
                  pl: 'Przewodnik procesowy — kolejność i kontrola. '
                      'Wiążące parametry: karta produktu + specyfikacja projektu.',
                  en: 'Process guide — sequence and checks. '
                      'Binding parameters: product data sheet + project specification.',
                ),
                style: const TextStyle(
                    color: _kMuted, fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
