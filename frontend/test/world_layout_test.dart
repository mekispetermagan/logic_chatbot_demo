import 'package:logic_chatbot/models/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logic_chatbot/models/conversation_state.dart';
import 'package:logic_chatbot/models/world.dart';
import 'package:logic_chatbot/models/world_object.dart';
import 'package:logic_chatbot/widgets/conversation_world_panel.dart';
import 'package:logic_chatbot/widgets/world_widget.dart';

void main() {
  testWidgets('only viewport changes resize the board', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    Future<void> display({
      bool editing = false,
      bool loading = false,
      String? error,
      int unplaced = 0,
      int? selected,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationWorldPanel(
              conversation: ConversationState(
                domain: WorldDomain.objects,
                id: 'test',
                world: World(
                  objects: List.generate(unplaced, (id) => WorldObject(id: id)),
                ),
                canUndo: false,
              ),
              loading: loading,
              editing: editing,
              error: error,
              onRetry: () {},
              selectedUnplacedObjectId: selected,
              onPaint: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    Rect board() => tester.getRect(
      find
          .descendant(
            of: find.byType(WorldWidget),
            matching: find.byType(GestureDetector),
          )
          .first,
    );

    await display();
    final initial = board();
    await display(editing: true);
    expect(board(), initial);
    await display(loading: true);
    expect(board(), initial);
    await display(error: 'Offline');
    expect(board(), initial);
    await display(unplaced: 30, selected: 0);
    expect(board(), initial);
    await display();
    expect(board(), initial);
    tester.view.physicalSize = const Size(600, 900);
    await tester.pump();
    expect(board().size, isNot(initial.size));
    expect(tester.takeException(), isNull);
  });
}
