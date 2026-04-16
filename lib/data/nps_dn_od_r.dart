class NpsRow {
  final String nps;
  final int dn;
  final double odMm;
  final double rMm;

  const NpsRow({required this.nps, required this.dn, required this.odMm, required this.rMm});
}

const List<NpsRow> kNpsTable = [
  NpsRow(nps: '1/2"', dn: 15, odMm: 21.3, rMm: 28.0),
  NpsRow(nps: '3/4"', dn: 20, odMm: 26.9, rMm: 29.0),
  NpsRow(nps: '1"', dn: 25, odMm: 30.0, rMm: 33.5),
  NpsRow(nps: '1"', dn: 25, odMm: 33.4, rMm: 38.1),
  NpsRow(nps: '1 1/4"', dn: 32, odMm: 42.4, rMm: 48.0),
  NpsRow(nps: '1 1/2"', dn: 40, odMm: 44.5, rMm: 51.0),
  NpsRow(nps: '1 1/2"', dn: 40, odMm: 48.3, rMm: 57.15),
  NpsRow(nps: '2"', dn: 50, odMm: 57.0, rMm: 72.0),
  NpsRow(nps: '2"', dn: 50, odMm: 60.3, rMm: 76.0),
  NpsRow(nps: '2"', dn: 50, odMm: 63.5, rMm: 82.5),
  NpsRow(nps: '2 1/2"', dn: 65, odMm: 70.0, rMm: 92.0),
  NpsRow(nps: '2 1/2"', dn: 65, odMm: 73.03, rMm: 95.25),
  NpsRow(nps: '2 1/2"', dn: 65, odMm: 76.1, rMm: 95.25),
  NpsRow(nps: '3"', dn: 80, odMm: 82.5, rMm: 107.5),
  NpsRow(nps: '3"', dn: 80, odMm: 88.9, rMm: 114.3),
  NpsRow(nps: '3 1/2"', dn: 80, odMm: 101.6, rMm: 133.35),
  NpsRow(nps: '4"', dn: 100, odMm: 104.0, rMm: 150.0),
  NpsRow(nps: '4"', dn: 100, odMm: 108.0, rMm: 142.5),
  NpsRow(nps: '6"', dn: 150, odMm: 154.0, rMm: 225.0),
  NpsRow(nps: '6"', dn: 150, odMm: 159.0, rMm: 216.0),
  NpsRow(nps: '6"', dn: 150, odMm: 165.1, rMm: 230.0),
  NpsRow(nps: '6"', dn: 150, odMm: 168.3, rMm: 228.6),
  NpsRow(nps: '8"', dn: 200, odMm: 204.0, rMm: 300.0),
  NpsRow(nps: '8"', dn: 200, odMm: 219.1, rMm: 304.8),
  NpsRow(nps: '10"', dn: 250, odMm: 267.0, rMm: 378.0),
  NpsRow(nps: '10"', dn: 250, odMm: 273.0, rMm: 381.0),
  NpsRow(nps: '12"', dn: 300, odMm: 318.0, rMm: 455.0),
  NpsRow(nps: '12"', dn: 300, odMm: 323.9, rMm: 455.0),
  NpsRow(nps: '14"', dn: 350, odMm: 355.6, rMm: 533.4),
  NpsRow(nps: '14"', dn: 350, odMm: 368.0, rMm: 533.5),
  NpsRow(nps: '16"', dn: 400, odMm: 406.4, rMm: 609.6),
  NpsRow(nps: '16"', dn: 400, odMm: 419.0, rMm: 609.5),
  NpsRow(nps: '18"', dn: 450, odMm: 457.2, rMm: 685.8),
  NpsRow(nps: '22"', dn: 500, odMm: 558.8, rMm: 838.2),
  NpsRow(nps: '24"', dn: 600, odMm: 609.6, rMm: 914.4),
  NpsRow(nps: '26"', dn: 600, odMm: 660.4, rMm: 990.6),
  NpsRow(nps: '28"', dn: 700, odMm: 711.2, rMm: 1066.8),
  NpsRow(nps: '30"', dn: 700, odMm: 762.0, rMm: 1143.0),
  NpsRow(nps: '32"', dn: 800, odMm: 812.8, rMm: 1219.2),
  NpsRow(nps: '34"', dn: 800, odMm: 863.6, rMm: 1295.4),
  NpsRow(nps: '36"', dn: 900, odMm: 914.4, rMm: 1371.6),
  NpsRow(nps: '38"', dn: 900, odMm: 965.2, rMm: 1447.8),
  NpsRow(nps: '40"', dn: 1000, odMm: 1016.0, rMm: 1524.0),
];
