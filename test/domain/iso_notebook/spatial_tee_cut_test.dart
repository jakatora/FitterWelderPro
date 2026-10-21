import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/domain/iso_notebook/sketch_cut.dart';
import 'package:cut_list_app/domain/iso_notebook/spatial_route.dart';
import 'package:cut_list_app/domain/iso_notebook/sketch_to_project.dart';
import 'sketch_fakes.dart';

class SpatialPipe extends Pipe implements SketchSpatialPipe {
  SpatialPipe(Offset a, Offset b, this.spatialDirection)
      : super(a, b, Dim('1000'));
  @override
  final IsoSpatialVector spatialDirection;
}

class SpatialTee extends Comp implements SketchSpatialTee {
  SpatialTee(this.spatialTee)
      : super(Offset.zero, 'tee', dn: 100, dnOut: 80, cteMm: 123);
  @override
  final IsoSpatialTee spatialTee;
}

void main() {
  test(
      'overlapping paper rays keep distinct physical run/branch DN and C/M take-outs',
      () {
    final run = IsoSpatialVector.gridHeading(0)
        .turnTowards(IsoSpatialVector.gridHeading(2), 45);
    final branch = IsoSpatialVector.gridHeading(1);
    final tee = SpatialTee(IsoSpatialTee(run: run, branch: branch));
    Offset paper(IsoSpatialVector v) {
      final p = v.projected;
      return Offset(p.x, p.y) * 128;
    }

    final incoming = SpatialPipe(paper(run * -1), Offset.zero, run);
    final outgoing = SpatialPipe(Offset.zero, paper(run), run);
    final outlet = SpatialPipe(Offset.zero, paper(branch), branch);
    final pipes = [incoming, outgoing, outlet];
    // Both outgoing projected rays point along exactly the same paper line.
    expect(
        (paper(run) / paper(run).distance -
                paper(branch) / paper(branch).distance)
            .distance,
        lessThan(1e-8));
    expect(
        sketchLegRoleAt(outlet, Offset.zero, pipes, kSketchJointTolerance,
            component: tee),
        SketchLegRole.branch);
    expect(
        sketchLegRoleAt(outgoing, Offset.zero, pipes, kSketchJointTolerance,
            component: tee),
        SketchLegRole.run);
    expect(sketchInferredDn(outlet, [tee], kSketchJointTolerance, pipes: pipes),
        80);
    expect(
        sketchInferredDn(outgoing, [tee], kSketchJointTolerance, pipes: pipes),
        100);
    expect(sketchCutMm(outlet, [tee], pipes: pipes), 902,
        reason: 'branch uses actual B16.9 M98');
    expect(sketchCutMm(outgoing, [tee], pipes: pipes), 877,
        reason: 'run preserves explicit C123');
    final project = planProjectFromSketch(pipes: pipes, components: [tee]);
    expect(project.segments.map((p) => p.cutMm), [877, 877, 902]);
  });
}
