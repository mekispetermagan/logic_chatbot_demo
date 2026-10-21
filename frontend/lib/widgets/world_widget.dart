import '../models/domain.dart';

import 'package:flutter/material.dart';

import '../models/world.dart';
import 'world_object_widget.dart';
import 'coordinate_frame.dart';

class WorldWidget extends StatelessWidget {
  const WorldWidget({
    super.key,
    required this.world,
    this.domain = WorldDomain.objects,
    this.onPaint,
    this.onErase,
  });

  final World world;
  final WorldDomain domain;
  final void Function(int, int)? onPaint;
  final void Function(int, int)? onErase;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CoordinateFrame(
        columns: world.width,
        rows: world.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cellWidth = constraints.maxWidth / world.width;
            final cellHeight = constraints.maxHeight / world.height;

            void act(Offset position, void Function(int, int)? callback) {
              final x = (position.dx / cellWidth).floor();
              final y = world.height - 1 - (position.dy / cellHeight).floor();
              if (x >= 0 && x < world.width && y >= 0 && y < world.height) {
                callback?.call(x, y);
              }
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: onPaint == null
                  ? null
                  : (details) => act(details.localPosition, onPaint),
              onSecondaryTapUp: onErase == null
                  ? null
                  : (details) => act(details.localPosition, onErase),
              onLongPressStart: onErase == null
                  ? null
                  : (details) => act(details.localPosition, onErase),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Semantics(
                    label:
                        '${world.width} by ${world.height} board with '
                        'alternating white and gray squares',
                    child: CustomPaint(
                      painter: _BoardPainter(world.width, world.height),
                    ),
                  ),
                  for (final object in world.objects.where(
                    (object) => object.position != null,
                  ))
                    Positioned(
                      left: object.position!.x * cellWidth,
                      top: (world.height - 1 - object.position!.y) * cellHeight,
                      width: cellWidth,
                      height: cellHeight,
                      child: WorldObjectWidget(object: object, domain: domain),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  const _BoardPainter(this.columns, this.rows);

  final int columns;
  final int rows;

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / columns;
    final cellHeight = size.height / rows;
    final paint = Paint()..isAntiAlias = false;

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        paint.color = (row + column).isEven
            ? Colors.blueGrey.shade400
            : Colors.blueGrey.shade300;
        canvas.drawRect(
          Rect.fromLTWH(
            column * cellWidth,
            row * cellHeight,
            cellWidth,
            cellHeight,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) =>
      columns != oldDelegate.columns || rows != oldDelegate.rows;
}
