import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/cellular_world.dart';
import '../models/world_slot.dart';
import 'cellular_world_widget.dart';
import 'cellular_color_selector.dart';
import 'cellular_ruleset_dialog.dart';
import 'world_slots.dart';

class CellularWorldDisplay extends StatelessWidget {
  const CellularWorldDisplay({
    super.key,
    required this.world,
    this.selectedColor = CellColor.black,
    this.onColorChanged,
    this.onPaint,
    this.onStep,
    this.onRulesetSubmitted,
    this.slots = const [],
    this.onSaveSlot,
    this.onLoadSlot,
  });

  final CellularWorld world;
  final CellColor selectedColor;
  final ValueChanged<CellColor>? onColorChanged;
  final void Function(int, int)? onPaint;
  final VoidCallback? onStep;
  final Future<bool> Function(CellularRuleset, bool)? onRulesetSubmitted;
  final List<WorldSlot> slots;
  final Future<bool> Function(int, bool)? onSaveSlot;
  final Future<bool> Function(int)? onLoadSlot;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: SizedBox(
        height: math.max(constraints.maxHeight, 320),
        child: Column(
          children: [
            Expanded(
              child: CellularWorldWidget(world: world, onPaint: onPaint),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: CellularColorSelector(
                palette: world.ruleset.palette,
                selected: selectedColor,
                onChanged: onColorChanged,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('cellular-step'),
                    onPressed: onStep,
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Step'),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Generation ${world.generation}',
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit rules',
                    onPressed: onRulesetSubmitted == null
                        ? null
                        : () => showDialog<bool>(
                            context: context,
                            barrierDismissible: false,
                            builder: (context) => CellularRulesetDialog(
                              world: world,
                              onSubmit: onRulesetSubmitted!,
                            ),
                          ),
                    icon: const Icon(Icons.tune),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${world.ruleset.neighborhood} neighbors · Edges wrap',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            WorldSlots(slots: slots, onSave: onSaveSlot, onLoad: onLoadSlot),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}
