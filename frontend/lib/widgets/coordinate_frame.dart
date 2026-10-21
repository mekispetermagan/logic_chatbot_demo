import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fits a board and its chessboard coordinates into the available viewport.
class CoordinateFrame extends StatelessWidget {
  const CoordinateFrame({
    super.key,
    required this.columns,
    required this.rows,
    required this.child,
  });

  final int columns;
  final int rows;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const gutter = 24.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = math.max(
          0.0,
          math.min(
            (constraints.maxWidth - gutter) / columns,
            (constraints.maxHeight - gutter) / rows,
          ),
        );
        final width = cell * columns;
        final height = cell * rows;
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
              for (var row = 0; row < rows; row++)
                Positioned(
                  left: 0,
                  top: row * cell,
                  width: gutter,
                  height: cell,
                  child: Center(child: Text('${rows - row}')),
                ),
              for (var column = 0; column < columns; column++)
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
