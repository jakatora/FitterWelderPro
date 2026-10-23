import 'package:flutter_test/flutter_test.dart';
import 'support/test_database.dart';

import 'package:cut_list_app/database/heat_photo_dao.dart';

void main() {
  useTestDatabase();

  test('HeatPhotoDao insert / list / deleteById round-trip', () async {
    final dao = HeatPhotoDao();
    // Unique ids so the test is isolated from any pre-existing rows in the
    // suite-local test DB.
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final projectId = 'test_project_$stamp';
    final id = 'heat_$stamp';
    await insertTestProject(projectId);

    await dao.insert({
      'id': id,
      'project_id': projectId,
      'library_component_id': null,
      // The persistent path is what fix (a) now stores (app documents dir),
      // not the picker's volatile cache path.
      'image_path': '/documents/heat_photos/$id.jpg',
      'note': 'HEAT-123',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    var rows = await dao.listForProject(projectId);
    expect(rows.length, 1);
    expect(rows.single.id, id);
    expect(rows.single.imagePath, '/documents/heat_photos/$id.jpg');

    // Fix (d): the new delete action must actually remove the record.
    await dao.deleteById(id);
    rows = await dao.listForProject(projectId);
    expect(rows, isEmpty);
  });
}
