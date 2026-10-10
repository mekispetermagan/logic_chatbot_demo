import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/world_object.dart';

/// Shared asset silhouettes for board pieces and property-selector icons.
class ShapeGlyph extends StatelessWidget {
  const ShapeGlyph({super.key, required this.shape, required this.color});

  final ObjectShape shape;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/images/shapes/${shape.name}.svg',
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    excludeFromSemantics: true,
  );
}
