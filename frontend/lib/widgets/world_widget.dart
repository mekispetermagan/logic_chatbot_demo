import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/world.dart';
import 'world_object_widget.dart';

class WorldWidget extends StatelessWidget {
  const WorldWidget({
    super.key,
    required this.world,
    this.onPaint,
    this.onErase,
  });

  final World world;
  final void Function(int, int)? onPaint;
  final void Function(int, int)? onErase;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _CoordinateFrame(
        world: world,
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
                      child: WorldObjectWidget(object: object),
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

class _CoordinateFrame extends StatelessWidget {
  const _CoordinateFrame({required this.world, required this.child});

  final World world;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const gutter = 24.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = math.max(
          0.0,
          math.min(
            (constraints.maxWidth - gutter) / world.width,
            (constraints.maxHeight - gutter) / world.height,
          ),
        );
        final width = cell * world.width;
        final height = cell * world.height;
        return SizedBox(
          width: width + gutter,
          height: height + gutter,
          child: Stack(
            children: [
              Positioned(
                left: gutter,
                top: 0,
                width: width,
                height: height,
                child: child,
              ),
              for (var row = 0; row < world.height; row++)
                Positioned(
                  left: 0,
                  top: row * cell,
                  width: gutter,
                  height: cell,
                  child: Center(child: Text('${world.height - row}')),
                ),
              for (var column = 0; column < world.width; column++)
                Positioned(
                  left: gutter + column * cell,
                  top: height,
                  width: cell,
                  height: gutter,
                  child: Center(child: Text(_columnLabel(column))),
                ),
            ],
          ),
        );
      },
    );
  }

  String _columnLabel(int column) {
    var index = column + 1;
    var label = '';
    while (index > 0) {
      index--;
      label = String.fromCharCode(65 + index % 26) + label;
      index ~/= 26;
    }
    return label;
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
