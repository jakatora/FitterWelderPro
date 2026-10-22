import '../database/tandem_tig_param_dao.dart';
import '../domain/welding/tandem_currents.dart';
import '../models/tandem_tig_param.dart';

TandemPoint _pt(TandemTigParam p) => TandemPoint(
      t1: p.wallThicknessMm,
      t2: p.wallThickness2Mm ?? p.wallThicknessMm,
      outsideA: p.outsideAmps,
      insideA: p.insideAmps,
    );

/// Prądy tandemu TIG (zbiorniki SS) z zatwierdzonych punktów startowych —
/// jedno źródło dla ekranu „Parametry — zbiorniki” i asystenta.
/// Pion bez własnego wpisu: poziom przeskalowany parą odniesienia.
Future<TandemEstimate> estimateTandemFromApproved({
  TandemTigParamDao? dao,
  required double t1,
  required double t2,
  required String position,
  required String jointType,
  required double? landMm,
  required double? gapMm,
}) async {
  final source = dao ?? TandemTigParamDao();
  Future<List<TandemPoint>> load(String pos) async =>
      (await source.listApprovedFiltered(
        materialGroup: 'SS',
        position: pos,
        jointType: jointType,
        landMm: landMm,
        gapMm: gapMm,
      ))
          .map(_pt)
          .toList();

  final hPts = await load('HORIZONTAL');
  if (position == 'HORIZONTAL') return estimateTandem(hPts, t1, t2);
  final vPts = await load('VERTICAL');
  final own = estimateTandem(vPts, t1, t2);
  return own.hasResult
      ? own
      : estimateTandemVerticalFromHorizontal(
          horizontal: hPts, vertical: vPts, t1: t1, t2: t2);
}
