import '../models/domain.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/object_property.dart';
import '../models/world.dart';
import '../models/world_object.dart';
import 'world_object_widget.dart';
import 'shape_glyph.dart';
import 'object_palette.dart';
import 'world_widget.dart';

class WorldDisplay extends StatelessWidget {
  const WorldDisplay({
    super.key,
    required this.world,
    this.domain = WorldDomain.objects,
    required this.selectedProperty,
    required this.selectedUnplacedObjectId,
    required this.onUnplacedObjectSelected,
    required this.onPropertyChanged,
    required this.onPaint,
    required this.onErase,
    required this.onClear,
    this.interactionHint,
    this.selector,
  });

  final World world;
  final WorldDomain domain;
  final ObjectProperty selectedProperty;
  final int? selectedUnplacedObjectId;
  final ValueChanged<int>? onUnplacedObjectSelected;
  final ValueChanged<ObjectProperty>? onPropertyChanged;
  final void Function(int, int)? onPaint;
  final void Function(int, int)? onErase;
  final VoidCallback? onClear;
  final String? interactionHint;
  final Widget? selector;

  @override
  Widget build(BuildContext context) {
    final unplaced = world.objects
        .where((object) => object.position == null)
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: SizedBox(
            // Scroll on short screens; otherwise the viewport determines size.
            height: math.max(
              constraints.maxHeight,
              domain == WorldDomain.network
                  ? math.min(constraints.maxWidth, 320) +
                        240 +
                        (20 / (constraints.maxWidth / 54).floor().clamp(4, 20))
                                .ceil() *
                            56
                  : 520,
            ),
            child: Column(
              children: [
                Expanded(
                  child: WorldWidget(
                    world: world,
                    domain: domain,
                    onPaint: onPaint,
                    onErase: onErase,
                  ),
                ),
                SizedBox(
                  // Reserve the same row even when every object is placed.
                  height: 80,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (unplaced.isNotEmpty) ...[
                            const Text('Unplaced:'),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                spacing: 8,
                                children: [
                                  for (final object in unplaced)
                                    Semantics(
                                      selected:
                                          object.id == selectedUnplacedObjectId,
                                      button: true,
                                      child: InkWell(
                                        key: ValueKey('unplaced-${object.id}'),
                                        onTap: onUnplacedObjectSelected == null
                                            ? null
                                            : () => onUnplacedObjectSelected!(
                                                object.id,
                                              ),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color:
                                                  object.id ==
                                                      selectedUnplacedObjectId
                                                  ? Theme.of(
                                                      context,
                                                    ).colorScheme.primary
                                                  : Colors.transparent,
                                              width: 2,
                                            ),
                                          ),
                                          child: SizedBox.square(
                                            dimension: 56,
                                            child: WorldObjectWidget(
                                              object: object,
                                              domain: domain,
                                              tooltipTriggerMode:
                                                  TooltipTriggerMode.longPress,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                      ),
                      child:
                          selector ??
                          _PropertySelector(
                            selected: selectedProperty,
                            onChanged: onPropertyChanged,
                          ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Clear world',
                          onPressed: onClear,
                          icon: const Icon(Icons.clear_all),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 64,
                  child: Text(
                    interactionHint ??
                        (onPaint == null
                            ? 'World editing will be available soon.'
                            : selectedUnplacedObjectId == null
                            ? 'Click or tap to apply one property. Right click or long press to erase.'
                            : 'Tap an empty square to place #$selectedUnplacedObjectId. Select a property to cancel.'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PropertySelector extends StatelessWidget {
  const _PropertySelector({required this.selected, required this.onChanged});
  final ObjectProperty selected;
  final ValueChanged<ObjectProperty>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const groups = [
      [
        ObjectProperty.red,
        ObjectProperty.blue,
        ObjectProperty.green,
        ObjectProperty.yellow,
      ],
      [ObjectProperty.small, ObjectProperty.medium, ObjectProperty.large],
      [
        ObjectProperty.bloom,
        ObjectProperty.spark,
        ObjectProperty.drop,
        ObjectProperty.loop,
      ],
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final group in groups)
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [for (final property in group) _button(property, colors)],
          ),
      ],
    );
  }

  Widget _button(ObjectProperty property, ColorScheme colors) => Semantics(
    key: ValueKey('property-${property.name}'),
    label: property.name,
    selected: property == selected,
    child: Tooltip(
      message: property.name,
      excludeFromSemantics: true,
      child: SizedBox.square(
        dimension: 48,
        child: FilledButton(
          onPressed: onChanged == null ? null : () => onChanged!(property),
          style: FilledButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: property == selected
                ? colors.primary
                : colors.surfaceContainerHighest,
            foregroundColor: property == selected
                ? colors.onPrimary
                : colors.onSurface,
            disabledBackgroundColor: property == selected
                ? colors.primary.withValues(alpha: 0.5)
                : colors.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: _symbol(
                  property,
                  property == selected ? colors.onPrimary : colors.onSurface,
                ),
              ),
              if (property == selected)
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
  );

  Widget _symbol(ObjectProperty property, Color foreground) {
    final swatch = switch (property) {
      ObjectProperty.red => ObjectPalette.red,
      ObjectProperty.blue => ObjectPalette.blue,
      ObjectProperty.green => ObjectPalette.green,
      ObjectProperty.yellow => ObjectPalette.yellow,
      _ => null,
    };
    if (swatch != null) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: swatch,
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }
    final shape = switch (property) {
      ObjectProperty.bloom => ObjectShape.bloom,
      ObjectProperty.spark => ObjectShape.spark,
      ObjectProperty.drop => ObjectShape.drop,
      ObjectProperty.loop => ObjectShape.loop,
      _ => null,
    };
    if (shape != null) {
      return SizedBox.square(
        dimension: 22,
        child: ShapeGlyph(shape: shape, color: foreground),
      );
    }
    final diameter = switch (property) {
      ObjectProperty.small => 8.0,
      ObjectProperty.medium => 12.0,
      ObjectProperty.large => 16.0,
      _ => null,
    };
    if (diameter == null) return const SizedBox.shrink();
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(shape: BoxShape.circle, color: foreground),
    );
  }
}
