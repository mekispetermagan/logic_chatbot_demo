import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/world_object.dart';

class WorldObjectWidget extends StatelessWidget {
  const WorldObjectWidget({
    super.key,
    required this.object,
    this.tooltipTriggerMode = TooltipTriggerMode.manual,
  });

  final WorldObject object;
  final TooltipTriggerMode tooltipTriggerMode;

  @override
  Widget build(BuildContext context) {
    final description =
        '#${object.id}\n'
        'Color: ${object.color?.name ?? 'none'}\n'
        'Size: ${object.size?.name ?? 'none'}\n'
        'Shape: ${object.shape?.name ?? 'none'}\n'
        'Position: ${object.position?.square ?? 'none'}';
    // Board tooltips appear on hover, without competing with long-press erase.
    return Tooltip(
      message: description,
      triggerMode: tooltipTriggerMode,
      child: Semantics(
        label: description,
        child: CustomPaint(painter: _ObjectPainter(object)),
      ),
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
      ObjectSize.medium || null => 0.6,
      ObjectSize.large => 0.9,
    };
    final side = math.min(size.width, size.height) * scale;
    final center = Offset(size.width / 2, size.height / 2);
    final color = switch (object.color) {
      ObjectColor.red => Colors.red,
      ObjectColor.blue => Colors.blue,
      ObjectColor.green => Colors.green,
      ObjectColor.yellow => Colors.yellow,
      null => null,
    };
    final height = object.shape == ObjectShape.pyramid
        ? side * math.sqrt(3) / 2
        : side;
    final bounds = Rect.fromCenter(center: center, width: side, height: height);
    final paint = Paint();
    if (color == null) {
      paint
        ..color = Colors.grey.shade700
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
    } else {
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.shade400, color.shade600],
      ).createShader(bounds);
    }
    switch (object.shape) {
      case ObjectShape.cube:
        canvas.drawRect(bounds, paint);
      case ObjectShape.sphere:
        canvas.drawCircle(center, side / 2, paint);
      case ObjectShape.pyramid:
        final triangle = Path()
          ..moveTo(center.dx, center.dy - height / 2)
          ..lineTo(center.dx + side / 2, center.dy + height / 2)
          ..lineTo(center.dx - side / 2, center.dy + height / 2)
          ..close();
        canvas.drawPath(triangle, paint);
      case null:
        paint.style = PaintingStyle.fill;
        _question(canvas, center, side, paint);
    }
    if (object.size == null) {
      final badgeCenter = Offset(bounds.right, bounds.top);
      final radius = math.min(size.width, size.height) * 0.12;
      canvas.drawCircle(
        badgeCenter,
        radius,
        Paint()..color = Colors.grey.shade900,
      );
      _question(
        canvas,
        badgeCenter,
        radius * 1.5,
        Paint()..color = Colors.white,
      );
    }
  }

  void _question(Canvas canvas, Offset center, double fontSize, Paint paint) {
    final text = TextPainter(
      text: TextSpan(
        text: '?',
        style: TextStyle(
          fontSize: fontSize,
          height: 1,
          fontWeight: FontWeight.bold,
          foreground: paint,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
    text.dispose();
  }

  @override
  bool shouldRepaint(covariant _ObjectPainter oldDelegate) =>
      object.shape != oldDelegate.object.shape ||
      object.size != oldDelegate.object.size ||
      object.color != oldDelegate.object.color;
}
