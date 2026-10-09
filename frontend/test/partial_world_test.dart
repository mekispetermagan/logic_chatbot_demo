import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logic_chatbot/controllers/world_display_controller.dart';
import 'package:logic_chatbot/data/toy_world.dart';
import 'package:logic_chatbot/models/object_property.dart';
import 'package:logic_chatbot/models/world.dart';
import 'package:logic_chatbot/models/world_object.dart';
import 'package:logic_chatbot/widgets/world_display.dart';
import 'package:logic_chatbot/widgets/world_object_widget.dart';
import 'package:logic_chatbot/widgets/world_widget.dart';

void main() {
  test(
    'each property creates a partial object and then updates only its attribute',
    () {
      for (final property in ObjectProperty.values) {
        final controller = WorldDisplayController(initialWorld: World());
        controller.selectProperty(property);
        controller.paint(0, 0);
        final created = controller.world.objects.single;
        expect(created.id, 0);
        expect(created.position, const BoardPosition(0, 0));
        expect(
          [
            created.color,
            created.size,
            created.shape,
          ].where((value) => value != null).length,
          1,
        );
        final before = controller.world;
        controller.paint(0, 0);
        expect(controller.world, same(before));
        controller.dispose();
      }
      const previous = WorldObject(
        id: 20,
        shape: ObjectShape.cube,
        size: ObjectSize.small,
        position: BoardPosition(2, 3),
      );
      final initial = World(objects: const [WorldObject(id: 30), previous]);
      final controller = WorldDisplayController(initialWorld: initial);
      addTearDown(controller.dispose);
      controller.paint(2, 3);
      var edited = controller.world.objects.last;
      expect(edited.id, 20);
      expect(edited.color, ObjectColor.red);
      expect(edited.size, ObjectSize.small);
      expect(edited.shape, ObjectShape.cube);
      controller.selectProperty(ObjectProperty.blue);
      controller.paint(2, 3);
      edited = controller.world.objects.last;
      expect(edited.color, ObjectColor.blue);
      controller.selectProperty(ObjectProperty.large);
      controller.paint(2, 3);
      expect(controller.world.objects.last.shape, ObjectShape.cube);
      expect(controller.world.objects.last.color, ObjectColor.blue);
      controller.selectProperty(ObjectProperty.sphere);
      controller.paint(2, 3);
      expect(controller.world.objects.last.size, ObjectSize.large);
      controller.paint(4, 4);
      expect(controller.world.objects.last.id, 31);
      controller.undo();
      expect(controller.world.objects.length, 2);
      expect(initial.objects.last.color, isNull);
      expect(controller.world.objects.first.position, isNull);
      controller.clear();
      expect(controller.world.objects, isEmpty);
      controller.undo();
      expect(controller.world.objects.length, 2);
    },
  );

  test('unplaced objects do not collide or count as outside the board', () {
    final world = World(
      objects: const [WorldObject(id: 0), WorldObject(id: 1)],
    );
    expect(world.hasCollisions(), isFalse);
    expect(world.hasOutOfRangeCoordinates(), isFalse);
    expect(
      World(
        objects: const [
          WorldObject(id: 0, position: BoardPosition(0, 0)),
          WorldObject(id: 1, position: BoardPosition(0, 0)),
        ],
      ).hasCollisions(),
      isTrue,
    );
    expect(
      World(
        objects: const [WorldObject(id: 0, position: BoardPosition(8, 0))],
      ).hasOutOfRangeCoordinates(),
      isTrue,
    );
  });

  testWidgets(
    'partial objects have descriptive tooltips and do not steal erase gestures',
    (tester) async {
      var paints = 0;
      var erases = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 320,
            height: 320,
            child: WorldWidget(
              world: World(
                objects: const [
                  WorldObject(id: 4, position: BoardPosition(0, 0)),
                ],
              ),
              onPaint: (_, _) => paints++,
              onErase: (_, _) => erases++,
            ),
          ),
        ),
      );
      expect(
        find.byTooltip(
          '#4\nColor: none\nSize: none\nShape: none\nPosition: A1',
        ),
        findsOneWidget,
      );
      final object = find.byType(WorldObjectWidget);
      await tester.tap(object);
      expect(paints, 1);
      await tester.longPress(object);
      expect(erases, 1);
      expect(paints, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [280.0, 360.0, 600.0]) {
    testWidgets(
      'single property control and unplaced objects fit at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = WorldDisplayController(initialWorld: toyWorld);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => WorldDisplay(
                  world: controller.world,
                  selectedProperty: controller.selectedProperty,
                  selectedUnplacedObjectId: controller.selectedUnplacedObjectId,
                  onUnplacedObjectSelected: controller.selectUnplacedObject,
                  onPropertyChanged: controller.selectProperty,
                  onPaint: controller.paint,
                  onErase: controller.erase,
                  onClear: controller.clear,
                ),
              ),
            ),
          ),
        );
        final selector = tester.widget<SegmentedButton<ObjectProperty>>(
          find.byType(SegmentedButton<ObjectProperty>),
        );
        expect(selector.segments.length, 10);
        expect(selector.selected, {ObjectProperty.red});
        expect(find.text('Unplaced'), findsOneWidget);
        expect(find.text('#5'), findsOneWidget);
        expect(find.text('#6'), findsOneWidget);
        expect(find.byType(WorldObjectWidget), findsNWidgets(7));
        await tester.tap(find.byTooltip('blue'));
        await tester.pump();
        expect(controller.selectedProperty, ObjectProperty.blue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
