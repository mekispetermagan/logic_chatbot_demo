import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/world_object.dart';

class WorldObjectWidget extends StatelessWidget {
  const WorldObjectWidget({super.key, required this.object});

  final WorldObject object;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${object.size.name} ${object.color.name} ${object.shape.name} '
          'at column ${object.x + 1}, row ${object.y + 1}',
      child: CustomPaint(painter: _ObjectPainter(object)),
    );
  }
}

class _ObjectPainter extends CustomPainter {
  const _ObjectPainter(this.object);

  final WorldObject object;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = switch (object.size) {
      ObjectSize.small => 0.4,
      ObjectSize.medium => 0.6,
      ObjectSize.large => 0.9,
    };
    final side = math.min(size.width, size.height) * scale;
    final center = Offset(size.width / 2, size.height / 2);
    final color = switch (object.color) {
      ObjectColor.red => Colors.red,
      ObjectColor.blue => Colors.blue,
      ObjectColor.green => Colors.green,
      ObjectColor.yellow => Colors.yellow,
    };
    final height = object.shape == ObjectShape.pyramid
        ? side * math.sqrt(3) / 2
        : side;
    final bounds = Rect.fromCenter(center: center, width: side, height: height);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.shade400, color.shade600],
      ).createShader(bounds);

    switch (object.shape) {
      case ObjectShape.cube:
        canvas.drawRect(
          Rect.fromCenter(center: center, width: side, height: side),
          paint,
        );
      case ObjectShape.sphere:
        canvas.drawCircle(center, side / 2, paint);
      case ObjectShape.pyramid:
        final triangle = Path()
          ..moveTo(center.dx, center.dy - height / 2)
          ..lineTo(center.dx + side / 2, center.dy + height / 2)
          ..lineTo(center.dx - side / 2, center.dy + height / 2)
          ..close();
        canvas.drawPath(triangle, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ObjectPainter oldDelegate) =>
      object.shape != oldDelegate.object.shape ||
      object.size != oldDelegate.object.size ||
      object.color != oldDelegate.object.color;
}
