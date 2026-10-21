import '../../core/skill.dart';

Map<String, List<String>> get colourStems => const {
      'violet': ['fiolet', 'violet', 'purple'],
      'green': ['zielon', 'green'],
      'yellow': ['zolt', 'yellow'],
      'grey': ['szar', 'grey', 'gray'],
      'red': ['czerwon', 'red'],
      'brown': ['brazow', 'brown'],
      'blue': ['niebies', 'blue'],
      'orange': ['pomarancz', 'orange'],
      'unknown': ['bial', 'white', 'czarn', 'black', 'rozow', 'pink'],
    };
List<String> spokenColours(Utterance u) => [
      for (final e in colourStems.entries)
        if (e.value.any((s) => s.length <= 3 ? u.hasAny([s]) : u.hasStem([s])))
          e.key
    ];
