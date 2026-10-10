import 'package:flutter/material.dart';

import '../models/world_object.dart';

/// Shared piece and selector colors; gradients mix 20% white and black.
abstract final class ObjectPalette {
  static const red = Color(0xFFC91A09);
  static const blue = Color(0xFF0055BF);
  static const yellow = Color(0xFFFEC401);
  static const green = Color(0xFF237841);

  static Color? forColor(ObjectColor? color) => switch (color) {
    ObjectColor.red => red,
    ObjectColor.blue => blue,
    ObjectColor.yellow => yellow,
    ObjectColor.green => green,
    null => null,
  };

  static LinearGradient gradient(Color color) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color.lerp(color, Colors.white, 0.2)!,
      Color.lerp(color, Colors.black, 0.2)!,
    ],
  );
}
