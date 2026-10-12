import 'package:flutter/material.dart';
import '../models/network_shape.dart';
import '../models/world_object.dart';
import 'network_glyph.dart';
import 'object_palette.dart';

class NetworkSelector extends StatelessWidget {
  const NetworkSelector({
    super.key,
    required this.selectedShape,
    required this.selectedColor,
    this.onShapeChanged,
    this.onColorChanged,
  });
  final NetworkShape selectedShape;
  final ObjectColor? selectedColor;
  final ValueChanged<NetworkShape>? onShapeChanged;
  final ValueChanged<ObjectColor>? onColorChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget button(
      String key,
      String label,
      bool selected,
      Widget child,
      VoidCallback? callback,
    ) => Semantics(
      key: ValueKey(key),
      label: label,
      selected: selected,
      child: Tooltip(
        message: label,
        child: SizedBox.square(
          dimension: 48,
          child: FilledButton(
            onPressed: callback,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.all(8),
              backgroundColor: selected
                  ? colors.primary
                  : colors.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(child: child),
                if (selected)
                  const Positioned(
                    top: -5,
                    right: -5,
                    child: Icon(Icons.check, size: 12),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return Wrap(
      spacing: 6,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            for (final color in ObjectColor.values)
              button(
                'network-color-${color.name}',
                color.name,
                selectedColor == color,
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: ObjectPalette.forColor(color),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                onColorChanged == null ? null : () => onColorChanged!(color),
              ),
          ],
        ),
        for (final shape in NetworkShape.values)
          button(
            'network-shape-${shape.assetName}',
            shape.label,
            selectedColor == null && selectedShape == shape,
            SizedBox.square(
              dimension: 28,
              child: NetworkGlyph(
                shape: shape,
                color: selectedColor == null && selectedShape == shape
                    ? colors.onPrimary
                    : colors.onSurface,
              ),
            ),
            onShapeChanged == null ? null : () => onShapeChanged!(shape),
          ),
      ],
    );
  }
}
