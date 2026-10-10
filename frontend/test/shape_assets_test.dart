import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logic_chatbot/models/world_object.dart';
import 'package:logic_chatbot/widgets/world_object_widget.dart';

void main() {
  testWidgets('all SVG shapes render with partial-object indicators', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              for (final shape in ObjectShape.values)
                SizedBox.square(
                  dimension: 80,
                  child: WorldObjectWidget(
                    object: WorldObject(id: shape.index, shape: shape),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final shape in ObjectShape.values) {
      expect(
        find.byTooltip(
          '#${shape.index}\nColor: none\nSize: none\nShape: ${shape.name}\nPosition: none',
        ),
        findsOneWidget,
      );
    }
    expect(find.text('?'), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('loop keeps its hole transparent and its vertical gradient', (
    tester,
  ) async {
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: const SizedBox.square(
              dimension: 100,
              child: WorldObjectWidget(
                object: WorldObject(
                  id: 0,
                  shape: ObjectShape.loop,
                  size: ObjectSize.large,
                  color: ObjectColor.red,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final pixels = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    });
    int channel(int x, int y, int channel) =>
        pixels!.getUint8((y * 100 + x) * 4 + channel);
    expect(
      channel(50, 50, 3),
      0,
      reason: 'The ring hole must not fill with the shader color.',
    );
    expect(channel(50, 24, 3), greaterThan(200));
    expect(channel(50, 77, 3), greaterThan(200));
    expect(
      channel(50, 24, 1),
      greaterThan(channel(50, 77, 1)),
      reason: 'The red tint must be lighter at the top.',
    );
    expect(tester.takeException(), isNull);
  });
}
