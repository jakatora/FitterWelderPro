// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';

import '../i18n/app_language.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = _helpCategories(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr(pl: 'Pomoc budowlana', en: 'Field help'))),
      body: ListView.builder(
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          return ExpansionTile(
            title: Text(cat.title, style: Theme.of(context).textTheme.titleMedium),
            children: cat.topics
                .map((topic) => ExpansionTile(
                      title: Text(topic.question),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          child: Text(topic.answer),
                        ),
                      ],
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}

class HelpCategory {
  final String title;
  final List<HelpTopic> topics;
  const HelpCategory(this.title, this.topics);
}

class HelpTopic {
  final String question;
  final String answer;
  const HelpTopic(this.question, this.answer);
}

List<HelpCategory> _helpCategories(BuildContext context) => [
  HelpCategory(context.tr(pl: 'Spoiny TIG', en: 'TIG welds'), [
    HelpTopic(
      context.tr(pl: 'Dlaczego spoina TIG zmienia kolor?', en: 'Why does a TIG weld change color?'),
      context.tr(pl: 'Najczęściej jest to wynik zbyt wysokiej temperatury, za małej osłony gazowej, za krótkiego post-flow lub zbyt wolnego prowadzenia palnika.', en: 'Most often this is caused by too much heat, insufficient gas shielding, too short post-flow, or moving the torch too slowly.'),
    ),
    HelpTopic(
      context.tr(pl: 'Dlaczego spoina jest matowa lub czarna?', en: 'Why is the weld dull or black?'),
      context.tr(pl: 'Matowa lub czarna spoina jest zwykle spowodowana brakiem purge, zbyt małym przepływem gazu lub zabrudzonym materiałem. Sprawdź szczelność układu, oczyść materiał i zwiększ osłonę gazową.', en: 'A dull or black weld is usually caused by no purge, too little gas flow, or contaminated material. Check system tightness, clean the material, and increase gas shielding.'),
    ),
    HelpTopic(
      context.tr(pl: 'Dlaczego spoina pęka po ostygnięciu?', en: 'Why does the weld crack after cooling?'),
      context.tr(pl: 'Zbyt szybkie chłodzenie, za duży prąd lub zanieczyszczenia w materiale mogą powodować pękanie. Zmniejsz prąd i zadbaj o czystość.', en: 'Cooling too quickly, excessive current, or contamination in the material can cause cracking. Reduce current and keep everything clean.'),
    ),
  ]),
  HelpCategory(context.tr(pl: 'Łuk TIG', en: 'TIG arc'), [
    HelpTopic(
      context.tr(pl: 'Dlaczego łuk jest niestabilny?', en: 'Why is the arc unstable?'),
      context.tr(pl: 'Niestabilny łuk najczęściej wynika z zanieczyszczonej elektrody, słabej masy lub zbyt długiego łuku. Upewnij się, że elektroda jest czysta i naostrzona oraz skróć dystans elektrodowy.', en: 'An unstable arc is most often caused by a contaminated electrode, poor grounding, or too long an arc. Make sure the electrode is clean and sharpened and shorten the arc length.'),
    ),
    HelpTopic(
      context.tr(pl: 'Dlaczego łuk gaśnie podczas spawania?', en: 'Why does the arc go out during welding?'),
      context.tr(pl: 'Może to być problem z zajarzeniem HF, za małym prądem lub niestabilnym połączeniem masy. Sprawdź ustawienia spawarki i połączenia elektryczne.', en: 'This may be caused by HF ignition issues, too little current, or an unstable ground connection. Check welder settings and electrical connections.'),
    ),
    HelpTopic(
      context.tr(pl: 'Dlaczego łuk rozchodzi się na boki?', en: 'Why does the arc drift to the sides?'),
      context.tr(pl: 'Zwykle przyczyną jest źle naostrzony tungsten lub wpływ pola magnetycznego (arc blow). Naostrz elektrodę i sprawdź rozkład masy.', en: 'This is usually caused by a poorly sharpened tungsten or magnetic field influence (arc blow). Sharpen the electrode and check the grounding layout.'),
    ),
  ]),
  HelpCategory(context.tr(pl: 'Elektroda (Tungsten)', en: 'Electrode (Tungsten)'), [
    HelpTopic(
      context.tr(pl: 'Dlaczego tungsten robi się kulisty?', en: 'Why does the tungsten ball up?'),
      context.tr(pl: 'Kulista końcówka elektrody pojawia się przy spawaniu AC lub zbyt wysokim prądzie. Zmniejsz prąd lub użyj odpowiedniej średnicy elektrody.', en: 'A rounded tungsten tip appears during AC welding or when the current is too high. Reduce current or use the correct electrode diameter.'),
    ),
    HelpTopic(
      context.tr(pl: 'Dlaczego tungsten szybko się zużywa?', en: 'Why does the tungsten wear out quickly?'),
      context.tr(pl: 'Dotykanie jeziorka spowoduje zanieczyszczenie i szybkie zużycie elektrody. Prowadź łuk stabilnie i nie zanurzaj elektrody w jeziorku.', en: 'Touching the weld pool contaminates the electrode and causes rapid wear. Keep the arc stable and do not dip the electrode into the pool.'),
    ),
    HelpTopic(
      context.tr(pl: 'Jak ostrzyć tungsten?', en: 'How should tungsten be sharpened?'),
      context.tr(pl: 'Szlifuj elektrodę wzdłuż jej osi na dedykowanej tarczy. Zachowaj kąt 20–30° i unikaj poprzecznych rys.', en: 'Grind the electrode along its axis on a dedicated wheel. Keep a 20-30° angle and avoid transverse scratches.'),
    ),
  ]),
  HelpCategory(context.tr(pl: 'Gaz i purge', en: 'Gas and purge'), [
    HelpTopic(
      context.tr(pl: 'Jaki przepływ gazu ustawić?', en: 'What gas flow should be set?'),
      context.tr(pl: 'Typowe przepływy to 6–8 l/min dla elektrody 1.6 mm i 7–10 l/min dla 2.4 mm. Zbyt duży przepływ może powodować turbulencje i porowatość.', en: 'Typical flows are 6-8 l/min for a 1.6 mm electrode and 7-10 l/min for 2.4 mm. Too much flow can cause turbulence and porosity.'),
    ),
    HelpTopic(
      context.tr(pl: 'Dlaczego purge ucieka?', en: 'Why is purge gas escaping?'),
      context.tr(pl: 'Najczęściej z powodu nieszczelności lub złego zamknięcia rur. Upewnij się, że wszystkie końce są dobrze uszczelnione i stosuj odpowiednie zawory purge.', en: 'Usually because of leaks or poor pipe sealing. Make sure all ends are sealed well and use proper purge valves.'),
    ),
    HelpTopic(
      context.tr(pl: 'Ile czasu powinien trwać purge?', en: 'How long should purge last?'),
      context.tr(pl: 'Zasada to 3–5 wymian objętości rury przed rozpoczęciem spawania. Dla rury Ø50 długości 1 m będzie to około 30–90 sekund.', en: 'A common rule is 3-5 volume changes of the pipe before welding starts. For a Ø50 pipe with 1 m length this is about 30-90 seconds.'),
    ),
  ]),
  HelpCategory(context.tr(pl: 'Materiał i przygotowanie', en: 'Material and preparation'), [
    HelpTopic(
      context.tr(pl: 'Dlaczego materiał się wygina?', en: 'Why does the material warp?'),
      context.tr(pl: 'Nadmierne nagrzanie bez punktów sczepnych powoduje odkształcenia. Stosuj sczepy i kontroluj tempo spawania.', en: 'Excessive heat without tack welds causes distortion. Use tack points and control welding speed.'),
    ),
    HelpTopic(
      context.tr(pl: 'Dlaczego materiał robi się kruchy?', en: 'Why does the material become brittle?'),
      context.tr(pl: 'Kruche spoiny to efekt przegrzania lub zbyt wysokiego heat input. Zmniejsz prąd i prędkość spawania.', en: 'Brittle welds are an effect of overheating or too much heat input. Reduce current and welding speed.'),
    ),
    HelpTopic(
      context.tr(pl: 'Dlaczego pojawia się porowatość?', en: 'Why does porosity appear?'),
      context.tr(pl: 'Porowatość wynika z brudu, tłuszczu, wilgoci lub zbyt dużego przepływu gazu. Dokładnie czyść materiał i elektrody oraz ustaw odpowiedni przepływ.', en: 'Porosity comes from dirt, grease, moisture, or too much gas flow. Clean the material and electrodes thoroughly and set the proper flow.'),
    ),
  ]),
  HelpCategory(context.tr(pl: 'Technika spawania', en: 'Welding technique'), [
    HelpTopic(
      context.tr(pl: 'Dlaczego spoina jest zbyt szeroka?', en: 'Why is the weld too wide?'),
      context.tr(pl: 'Zbyt szeroka spoina to najczęściej efekt za dużego prądu lub zbyt wolnego prowadzenia palnika. Zmniejsz prąd i zwiększ prędkość spawania.', en: 'A weld that is too wide is most often caused by too much current or moving the torch too slowly. Reduce current and increase welding speed.'),
    ),
    HelpTopic(
      context.tr(pl: 'Dlaczego spoina jest zbyt wąska?', en: 'Why is the weld too narrow?'),
      context.tr(pl: 'Zbyt wąska spoina może być spowodowana za małym prądem i zbyt szybkim prowadzeniem. Zwiększ prąd lub zwolnij prowadzenie.', en: 'A weld that is too narrow may be caused by too little current and moving too fast. Increase current or slow down.'),
    ),
    HelpTopic(
      context.tr(pl: 'Jak zakończyć spoinę TIG?', en: 'How should a TIG weld be finished?'),
      context.tr(pl: 'Wykorzystaj funkcję slope down, aby stopniowo zmniejszyć prąd. Pozostaw gaz na elektrodzie (post-flow), aby zapobiec utlenieniu.', en: 'Use the slope down function to reduce current gradually. Keep gas flowing over the electrode (post-flow) to prevent oxidation.'),
    ),
  ]),
  HelpCategory(context.tr(pl: 'Sprzęt i osprzęt', en: 'Equipment and accessories'), [
    HelpTopic(
      context.tr(pl: 'Dlaczego masa jest słaba?', en: 'Why is the ground poor?'),
      context.tr(pl: 'Słaba masa to częsta przyczyna niestabilnego łuku. Oczyść powierzchnię, upewnij się, że zacisk jest dobrze dokręcony i nie ma rdzy.', en: 'Poor grounding is a common cause of an unstable arc. Clean the surface, make sure the clamp is tight, and check for rust.'),
    ),
    HelpTopic(
      context.tr(pl: 'Dlaczego spawarka przerywa?', en: 'Why does the welder cut out?'),
      context.tr(pl: 'Może to być spowodowane przegrzewaniem, uszkodzonym przewodem lub niestabilnym zasilaniem. Sprawdź kable, chłodzenie i źródło prądu.', en: 'This may be caused by overheating, a damaged cable, or unstable power. Check cables, cooling, and the power source.'),
    ),
    HelpTopic(
      context.tr(pl: 'Jak dobrać kubek/gas lens?', en: 'How should cup size and gas lens be selected?'),
      context.tr(pl: 'Dobierz rozmiar dyszy i gas lens do średnicy elektrody i wymaganej osłony. W przypadku nierdzewki zaleca się gas lens i przepływ 7–10 l/min.', en: 'Match nozzle size and gas lens to the electrode diameter and required shielding. For stainless steel, a gas lens and 7-10 l/min flow are commonly recommended.'),
    ),
  ]),
];