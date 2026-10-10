import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/world_object.dart';
import 'shape_glyph.dart';

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = switch (object.size) {
              ObjectSize.small => 0.4,
              ObjectSize.medium || null => 0.6,
              ObjectSize.large => 0.9,
            };
            final cellSide = math.min(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            final side = cellSide * scale;
            final left = (constraints.maxWidth - side) / 2;
            final top = (constraints.maxHeight - side) / 2;
            final color = switch (object.color) {
              ObjectColor.red => Colors.red,
              ObjectColor.blue => Colors.blue,
              ObjectColor.green => Colors.green,
              ObjectColor.yellow => Colors.yellow,
              null => null,
            };
            final tint = color == null ? Colors.grey.shade700 : Colors.white;
            final glyph = object.shape != null
                ? ShapeGlyph(shape: object.shape!, color: tint)
                : FittedBox(
                    child: Text(
                      '?',
                      style: TextStyle(
                        color: tint,
                        height: 1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
            final radius = cellSide * 0.12;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: side,
                  height: side,
                  child: color == null
                      ? glyph
                      : ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) => LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [color.shade400, color.shade600],
                          ).createShader(bounds),
                          child: glyph,
                        ),
                ),
                if (object.size == null)
                  Positioned(
                    left: left + side - radius,
                    top: top - radius,
                    width: radius * 2,
                    height: radius * 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: radius * 1.5,
                            height: 1,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
