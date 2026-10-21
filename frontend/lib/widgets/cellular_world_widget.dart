import 'package:flutter/material.dart';

import '../models/cellular_world.dart';
import 'coordinate_frame.dart';
import 'cellular_palette.dart';

class CellularWorldWidget extends StatelessWidget {
  const CellularWorldWidget({super.key, required this.world, this.onPaint});

  final CellularWorld world;
  final void Function(int, int)? onPaint;

  @override
  Widget build(BuildContext context) => Center(
    child: CoordinateFrame(
      columns: world.width,
      rows: world.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellWidth = constraints.maxWidth / world.width;
          final cellHeight = constraints.maxHeight / world.height;
          return Stack(
            fit: StackFit.expand,
            children: [
              for (var y = 0; y < world.height; y++)
                for (var x = 0; x < world.width; x++)
                  Positioned(
                    left: x * cellWidth,
                    top: (world.height - 1 - y) * cellHeight,
                    width: cellWidth,
                    height: cellHeight,
                    child: Tooltip(
                      message:
                          '${String.fromCharCode(65 + x)}${y + 1}: ${world.colorAt(x, y).name}',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onPaint == null ? null : () => onPaint!(x, y),
                        child: DecoratedBox(
                          key: ValueKey(
                            'cellular-cell-${String.fromCharCode(65 + x)}${y + 1}',
                          ),
                          decoration: BoxDecoration(
                            color: CellularPalette.forColor(
                              world.colorAt(x, y),
                            ),
                            border: Border.all(
                              color: const Color(0xFF808080),
                              width: 0.5,
                            ),
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
