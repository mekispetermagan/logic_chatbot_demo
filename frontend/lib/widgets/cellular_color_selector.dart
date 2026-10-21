import 'package:flutter/material.dart';

import '../models/cellular_world.dart';
import 'cellular_palette.dart';

class CellularColorSelector extends StatelessWidget {
  const CellularColorSelector({
    super.key,
    required this.palette,
    required this.selected,
    this.onChanged,
  });

  final List<CellColor> palette;
  final CellColor selected;
  final ValueChanged<CellColor>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            for (final color in palette)
              Semantics(
                key: ValueKey('cellular-color-${color.name}'),
                label: color.name,
                selected: color == selected,
                child: Tooltip(
                  message: color.name,
                  excludeFromSemantics: true,
                  child: SizedBox.square(
                    dimension: 48,
                    child: FilledButton(
                      onPressed: onChanged == null
                          ? null
                          : () => onChanged!(color),
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: color == selected
                            ? colors.primary
                            : colors.surfaceContainerHighest,
                        foregroundColor: colors.onPrimary,
                        disabledBackgroundColor: color == selected
                            ? colors.primary.withValues(alpha: 0.5)
                            : colors.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: CellularPalette.forColor(color),
                                border: Border.all(color: colors.outline),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                          if (color == selected)
                            const Positioned(
                              top: 3,
                              right: 3,
                              child: Icon(Icons.check, size: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
