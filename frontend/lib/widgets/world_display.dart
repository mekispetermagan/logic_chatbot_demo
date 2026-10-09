import 'package:flutter/material.dart';

import '../models/object_property.dart';
import '../models/world.dart';
import 'world_object_widget.dart';
import 'world_widget.dart';

class WorldDisplay extends StatelessWidget {
  const WorldDisplay({
    super.key,
    required this.world,
    required this.selectedProperty,
    required this.selectedUnplacedObjectId,
    required this.onUnplacedObjectSelected,
    required this.onPropertyChanged,
    required this.onPaint,
    required this.onErase,
    required this.onClear,
    this.interactionHint,
  });

  final World world;
  final ObjectProperty selectedProperty;
  final int? selectedUnplacedObjectId;
  final ValueChanged<int>? onUnplacedObjectSelected;
  final ValueChanged<ObjectProperty>? onPropertyChanged;
  final void Function(int, int)? onPaint;
  final void Function(int, int)? onErase;
  final VoidCallback? onClear;
  final String? interactionHint;

  @override
  Widget build(BuildContext context) {
    final unplaced = world.objects
        .where((object) => object.position == null)
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(
                height: (constraints.maxHeight - (unplaced.isEmpty ? 140 : 250))
                    .clamp(120.0, double.infinity)
                    .clamp(0.0, constraints.maxWidth)
                    .toDouble(),
                child: WorldWidget(
                  world: world,
                  onPaint: onPaint,
                  onErase: onErase,
                ),
              ),
              if (unplaced.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Unplaced'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final object in unplaced)
                      Semantics(
                        selected: object.id == selectedUnplacedObjectId,
                        button: true,
                        child: InkWell(
                          key: ValueKey('unplaced-${object.id}'),
                          onTap: onUnplacedObjectSelected == null
                              ? null
                              : () => onUnplacedObjectSelected!(object.id),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: object.id == selectedUnplacedObjectId
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: WorldObjectWidget(
                                    object: object,
                                    tooltipTriggerMode:
                                        TooltipTriggerMode.longPress,
                                  ),
                                ),
                                Text('#${object.id}'),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  // Keep all ten options in one control. It scrolls on narrow screens.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _PropertySelector(
                        selected: selectedProperty,
                        onChanged: onPropertyChanged,
                      ),
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
              Text(
                interactionHint ??
                    (onPaint == null
                        ? 'World editing will be available soon.'
                        : selectedUnplacedObjectId == null
                        ? 'Click or tap to apply one property. Right click or long press to erase.'
                        : 'Tap an empty square to place #$selectedUnplacedObjectId. Select a property to cancel.'),
                textAlign: TextAlign.center,
              ),
            ],
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
    return SegmentedButton<ObjectProperty>(
      showSelectedIcon: false,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: const WidgetStatePropertyAll(Size(28, 36)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.outline,
            width: states.contains(WidgetState.selected) ? 2 : 1,
          ),
        ),
      ),
      segments: [
        for (final property in ObjectProperty.values)
          ButtonSegment(
            value: property,
            tooltip: property.name,
            label: Semantics(
              label: property.name,
              child: Container(
                width: 28,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: switch (property) {
                    ObjectProperty.red => Colors.red,
                    ObjectProperty.blue => Colors.blue,
                    ObjectProperty.green => Colors.green,
                    ObjectProperty.yellow => Colors.yellow,
                    _ => null,
                  },
                  border: Border.all(
                    color: property == selected
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: _symbol(context, property),
              ),
            ),
          ),
      ],
      selected: {selected},
      // Emit taps on the active segment too; the controlled selection remains
      // exactly one property while allowing placement mode to be cancelled.
      emptySelectionAllowed: true,
      onSelectionChanged: onChanged == null
          ? null
          : (properties) =>
                onChanged!(properties.isEmpty ? selected : properties.single),
    );
  }

  Widget? _symbol(BuildContext context, ObjectProperty property) {
    final shape = switch (property) {
      ObjectProperty.cube => '■',
      ObjectProperty.sphere => '●',
      ObjectProperty.pyramid => '▲',
      _ => null,
    };
    if (shape != null) return Text(shape, style: const TextStyle(fontSize: 20));
    final diameter = switch (property) {
      ObjectProperty.small => 8.0,
      ObjectProperty.medium => 12.0,
      ObjectProperty.large => 16.0,
      _ => null,
    };
    if (diameter == null) return null;
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}
