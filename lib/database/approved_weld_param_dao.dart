import '../database/db.dart';
import '../models/approved_weld_param.dart';

class ApprovedWeldParamDao {
  Future<List<ApprovedWeldParam>> listAll({String? method, String? material}) async {
    final db = await AppDatabase.get();
    final whereParts = <String>[];
    final args = <Object?>[];
    if (method != null && method.trim().isNotEmpty) {
      whereParts.add('method = ?');
      args.add(method);
    }
    if (material != null && material.trim().isNotEmpty) {
      whereParts.add('base_material = ?');
      args.add(material);
    }
    final rows = await db.query(
      'approved_weld_params',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'base_material, diameter_mm, wall_thickness_mm, method',
    );
    return rows.map(ApprovedWeldParam.fromRow).toList();
  }
}
