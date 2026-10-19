import 'package:flutter/material.dart';

import '../models/world_slot.dart';

/// Five fixed-size checkpoint controls; persistence belongs to the controller.
class WorldSlots extends StatelessWidget {
  const WorldSlots({super.key, required this.slots, this.onSave, this.onLoad});

  final List<WorldSlot> slots;
  final Future<bool> Function(int slot, bool overwrite)? onSave;
  final Future<bool> Function(int slot)? onLoad;

  Future<void> _save(BuildContext context, int slot, bool occupied) async {
    final save = onSave;
    if (save == null) return;
    if (occupied) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Overwrite slot $slot?'),
          content: const Text(
            'Replace the saved setup with the current world?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Overwrite'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    final saved = await save(slot, occupied);
    if (saved && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Saved slot $slot')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: Row(
        spacing: 4,
        children: [
          for (var slot = 1; slot <= 5; slot++)
            Expanded(
              child: Builder(
                builder: (context) {
                  final occupied = slots.any(
                    (saved) => saved.slot == slot && saved.isSaved,
                  );
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                      color: occupied ? colors.surfaceContainerHigh : null,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              '$slot',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                          Expanded(
                            child: IconButton(
                              key: ValueKey('save-slot-$slot'),
                              tooltip: 'Save slot $slot',
                              onPressed: onSave == null
                                  ? null
                                  : () => _save(context, slot, occupied),
                              icon: const Icon(Icons.save_outlined),
                              iconSize: 18,
                              style: _buttonStyle,
                            ),
                          ),
                          Expanded(
                            child: IconButton(
                              key: ValueKey('load-slot-$slot'),
                              tooltip: occupied
                                  ? 'Load slot $slot'
                                  : 'Slot $slot is empty',
                              onPressed: !occupied || onLoad == null
                                  ? null
                                  : () => onLoad!(slot),
                              icon: const Icon(Icons.restore_page_outlined),
                              iconSize: 18,
                              style: _buttonStyle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  static final _buttonStyle = IconButton.styleFrom(
    padding: EdgeInsets.zero,
    minimumSize: const Size(24, 32),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}
