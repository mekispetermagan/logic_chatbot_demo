import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/network_shape.dart';

class NetworkGlyph extends StatelessWidget {
  const NetworkGlyph({super.key, required this.shape, required this.color});
  final NetworkShape shape;
  final Color color;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/images/network_shapes/${shape.assetName}.svg',
    colorMapper: _NetworkColors(color),
  );
}

class _NetworkColors extends ColorMapper {
  const _NetworkColors(this.base);
  final Color base;
  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) => color == const Color(0xFFD4483A)
      ? Color.lerp(base, Colors.white, .2)!
      : color == const Color(0xFFA11507)
      ? Color.lerp(base, Colors.black, .2)!
      : color;
}
