import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logic_chatbot/controllers/world_display_controller.dart';
import 'package:logic_chatbot/models/object_property.dart';
import 'package:logic_chatbot/models/world.dart';
import 'package:logic_chatbot/models/world_object.dart';
import 'package:logic_chatbot/widgets/world_display.dart';
import 'package:logic_chatbot/widgets/world_widget.dart';

const unplaced = WorldObject(
  id: 12,
  shape: ObjectShape.sphere,
  color: ObjectColor.blue,
);
const occupied = WorldObject(
  id: 3,
  position: BoardPosition(0, 0),
  color: ObjectColor.green,
);

void main() {
  test('placement preserves identity and attributes and is undoable', () {
    final initial = World(objects: const [occupied, unplaced]);
    final controller = WorldDisplayController(initialWorld: initial);
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.selectUnplacedObject(12);
    expect(controller.history.length, 1);
    controller.paint(0, 0);
    controller.paint(8, 0);
    expect(controller.world, same(initial));
    expect(controller.selectedUnplacedObjectId, 12);
    expect(notifications, 1);
    controller.paint(1, 2);
    expect(controller.world.objects.length, 2);
    final placed = controller.world.objects.last;
    expect(placed.id, 12);
    expect(placed.position, const BoardPosition(1, 2));
    expect(placed.color, ObjectColor.blue);
    expect(placed.shape, ObjectShape.sphere);
    expect(placed.size, isNull);
    expect(controller.selectedUnplacedObjectId, isNull);
    expect(initial.objects.last.position, isNull);
    expect(notifications, 2);
    controller.undo();
    expect(controller.world, same(initial));
    expect(controller.world.objects.last.position, isNull);
    expect(controller.selectedUnplacedObjectId, isNull);
  });

  test(
    'selection toggles and property selection cancels even when unchanged',
    () {
      final controller = WorldDisplayController(
        initialWorld: World(objects: const [occupied, unplaced]),
      );
      addTearDown(controller.dispose);
      controller.selectUnplacedObject(3);
      controller.selectUnplacedObject(99);
      expect(controller.selectedUnplacedObjectId, isNull);
      controller.selectUnplacedObject(12);
      controller.selectUnplacedObject(12);
      expect(controller.selectedUnplacedObjectId, isNull);
      controller.selectUnplacedObject(12);
      controller.selectProperty(ObjectProperty.red);
      expect(controller.selectedUnplacedObjectId, isNull);
      controller.paint(2, 2);
      expect(controller.world.objects.last.color, ObjectColor.red);
      expect(controller.world.objects.last.id, 13);
      expect(controller.world.objects[1].position, isNull);
      controller.selectUnplacedObject(12);
      controller.undo();
      expect(controller.selectedUnplacedObjectId, isNull);
      controller.selectUnplacedObject(12);
      controller.clear();
      expect(controller.selectedUnplacedObjectId, isNull);
      expect(controller.world.objects, isEmpty);
    },
  );

  testWidgets(
    'unplaced selection, same-segment cancellation, and placement work through the display',
    (tester) async {
      final controller = WorldDisplayController(
        initialWorld: World(objects: const [occupied, unplaced]),
      );
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
                onUndo: controller.canUndo ? controller.undo : null,
              ),
            ),
          ),
        ),
      );
      final tile = find.byKey(const ValueKey('unplaced-12'));
      await tester.tap(tile);
      await tester.pump();
      expect(controller.selectedUnplacedObjectId, 12);
      expect(
        find.textContaining('Tap an empty square to place #12'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('red'));
      await tester.pump();
      expect(controller.selectedUnplacedObjectId, isNull);
      expect(
        tester
            .widget<SegmentedButton<ObjectProperty>>(
              find.byType(SegmentedButton<ObjectProperty>),
            )
            .selected,
        {ObjectProperty.red},
      );
      await tester.tap(tile);
      await tester.pump();
      final board = find
          .descendant(
            of: find.byType(WorldWidget),
            matching: find.byType(GestureDetector),
          )
          .first;
      final origin = tester.getTopLeft(board);
      final cell = tester.getSize(board).width / 8;
      await tester.tapAt(origin + Offset(cell / 2, cell * 7.5));
      await tester.pump();
      expect(controller.selectedUnplacedObjectId, 12);
      await tester.tapAt(origin + Offset(cell * 1.5, cell * 6.5));
      await tester.pump();
      expect(controller.world.objects.last.position, const BoardPosition(1, 1));
      expect(find.text('Unplaced'), findsNothing);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(find.text('Unplaced'), findsOneWidget);
      expect(controller.world.objects.last.position, isNull);
      expect(controller.selectedUnplacedObjectId, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
