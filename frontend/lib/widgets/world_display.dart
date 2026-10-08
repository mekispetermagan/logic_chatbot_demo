import 'package:flutter/material.dart';

import '../models/world.dart';
import '../models/world_object.dart';
import 'world_widget.dart';

class WorldDisplay extends StatelessWidget {
  const WorldDisplay({
    super.key,
    required this.world,
    required this.color,
    required this.size,
    required this.shape,
    required this.onColorChanged,
    required this.onSizeChanged,
    required this.onShapeChanged,
    required this.onPaint,
    required this.onErase,
    required this.onClear,
    required this.onUndo,
  });

  final World world;
  final ObjectColor color;
  final ObjectSize size;
  final ObjectShape shape;
  final ValueChanged<ObjectColor> onColorChanged;
  final ValueChanged<ObjectSize> onSizeChanged;
  final ValueChanged<ObjectShape> onShapeChanged;
  final void Function(int, int) onPaint;
  final void Function(int, int) onErase;
  final VoidCallback onClear;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Scrolling keeps the editor usable on short screens and with a keyboard.
        return SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(
                height: (constraints.maxHeight - 250)
                    .clamp(120.0, double.infinity)
                    .clamp(0.0, constraints.maxWidth)
                    .toDouble(),
                child: WorldWidget(
                  world: world,
                  onPaint: onPaint,
                  onErase: onErase,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _Selector<ObjectColor>(
                    label: 'Color',
                    values: ObjectColor.values,
                    selected: color,
                    onChanged: onColorChanged,
                  ),
                  _Selector<ObjectSize>(
                    label: 'Size',
                    values: ObjectSize.values,
                    selected: size,
                    onChanged: onSizeChanged,
                  ),
                  _Selector<ObjectShape>(
                    label: 'Shape',
                    values: ObjectShape.values,
                    selected: shape,
                    onChanged: onShapeChanged,
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
                      IconButton(
                        tooltip: 'Undo',
                        onPressed: onUndo,
                        icon: const Icon(Icons.undo),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Click or tap to paint. Right click or long press to erase.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Selector<T extends Enum> extends StatelessWidget {
  const _Selector({
    required this.label,
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<T> values;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(height: 4),
        SegmentedButton<T>(
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            minimumSize: const WidgetStatePropertyAll(Size(28, 36)),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            // backgroundColor: WidgetStatePropertyAll(
            //   Theme.of(context).colorScheme.primary,
            // ),
            // backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.selected)
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.outline,
                width: states.contains(WidgetState.selected) ? 2 : 1,
              ),
            ),
          ),
          showSelectedIcon: false,
          segments: [
            for (final value in values)
              ButtonSegment(
                value: value,
                tooltip: value.name,
                label: Semantics(
                  label: value.name,
                  child: Container(
                    width: 28,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: switch (value) {
                        ObjectColor.red => Colors.red,
                        ObjectColor.blue => Colors.blue,
                        ObjectColor.green => Colors.green,
                        ObjectColor.yellow => Colors.yellow,
                        _ => null,
                      },
                      // border: Border.all(
                      //   color: value == selected
                      //       ? Theme.of(context).colorScheme.onSurface
                      //       : Colors.transparent,
                      //   width: 2,
                      // ),
                    ),
                    child: _symbol(value),
                  ),
                ),
              ),
          ],
          selected: {selected},
          onSelectionChanged: (values) => onChanged(values.single),
        ),
      ],
    );
  }

  Widget? _symbol(T value) {
    if (value is ObjectShape) {
      return Text(switch (value) {
        ObjectShape.cube => '■',
        ObjectShape.sphere => '●',
        ObjectShape.pyramid => '▲',
      }, style: const TextStyle(fontSize: 20));
    }
    if (value is ObjectSize) {
      final diameter = switch (value) {
        ObjectSize.small => 8.0,
        ObjectSize.medium => 12.0,
        ObjectSize.large => 16.0,
      };
      return Builder(
        builder: (context) => Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
    }
    return null;
  }
}
