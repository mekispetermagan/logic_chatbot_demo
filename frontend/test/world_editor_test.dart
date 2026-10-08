import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logic_chatbot/controllers/world_display_controller.dart';
import 'package:logic_chatbot/models/world.dart';
import 'package:logic_chatbot/models/world_object.dart';
import 'package:logic_chatbot/widgets/world_widget.dart';

void main() {
  test(
    'edits preserve snapshots and selector changes stay outside history',
    () {
      final initial = World();
      final controller = WorldDisplayController(initialWorld: initial);
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.selectColor(ObjectColor.blue);
      expect(controller.history.length, 1);
      controller.paint(2, 3);
      expect(initial.objects, isEmpty);
      expect(controller.world.objects.single.color, ObjectColor.blue);
      controller.selectShape(ObjectShape.sphere);
      controller.paint(2, 3);
      expect(controller.world.objects.length, 1);
      expect(controller.world.hasCollisions(), isFalse);
      controller.undo();
      expect(controller.world.objects.single.shape, ObjectShape.cube);
      expect(controller.shape, ObjectShape.sphere);
      controller.clear();
      expect(controller.world.objects, isEmpty);
      controller.undo();
      controller.erase(2, 3);
      expect(controller.world.objects, isEmpty);
      controller.undo();
      controller.undo();
      expect(controller.world, same(initial));
      expect(controller.canUndo, isFalse);
      final before = notifications;
      controller.undo();
      controller.erase(0, 0);
      controller.paint(8, 0);
      expect(notifications, before);
    },
  );

  testWidgets('tap paints; secondary click and long press only erase', (
    tester,
  ) async {
    final painted = <(int, int)>[];
    final erased = <(int, int)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 320,
            height: 320,
            child: WorldWidget(
              world: World(),
              onPaint: (x, y) => painted.add((x, y)),
              onErase: (x, y) => erased.add((x, y)),
            ),
          ),
        ),
      ),
    );
    final board = find.byType(GestureDetector);
    final origin = tester.getTopLeft(board);
    final cell = tester.getSize(board).width / 8;
    final point = origin + Offset(2.5 * cell, 3.5 * cell);
    await tester.tapAt(point);
    expect(painted, [(2, 4)]);
    final mouse = await tester.startGesture(
      point,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.up();
    await tester.pump();
    expect(erased, [(2, 4)]);
    await tester.longPressAt(point);
    expect(erased, [(2, 4), (2, 4)]);
    expect(painted, [(2, 4)]);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('H'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('8')).dy,
      lessThan(tester.getTopLeft(find.text('1')).dy),
    );
    await tester.tapAt(origin + Offset(cell / 2, cell * 7.5));
    expect(painted.last, (0, 0));
  });
}
