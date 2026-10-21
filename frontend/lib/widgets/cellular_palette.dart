import 'package:flutter/material.dart';

import '../models/cellular_world.dart';
import 'object_palette.dart';

abstract final class CellularPalette {
  static Color forColor(CellColor color) => switch (color) {
    CellColor.white => Colors.white,
    CellColor.black => Colors.black,
    CellColor.red => ObjectPalette.red,
    CellColor.green => ObjectPalette.green,
    CellColor.blue => ObjectPalette.blue,
    CellColor.yellow => ObjectPalette.yellow,
  };
}
