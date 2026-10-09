import 'package:flutter/material.dart';

import '../models/conversation_state.dart';
import '../models/object_property.dart';
import 'world_display.dart';

class ConversationWorldPanel extends StatelessWidget {
  const ConversationWorldPanel({
    super.key,
    required this.conversation,
    required this.loading,
    required this.error,
    required this.onRetry,
    this.editing = false,
    this.selectedProperty = ObjectProperty.red,
    this.selectedUnplacedObjectId,
    this.onPropertyChanged,
    this.onUnplacedObjectSelected,
    this.onPaint,
    this.onErase,
    this.onClear,
  });

  final ConversationState? conversation;
  final bool loading;
  final bool editing;
  final String? error;
  final VoidCallback onRetry;
  final ObjectProperty selectedProperty;
  final int? selectedUnplacedObjectId;
  final ValueChanged<ObjectProperty>? onPropertyChanged;
  final ValueChanged<int>? onUnplacedObjectSelected;
  final void Function(int, int)? onPaint;
  final void Function(int, int)? onErase;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final state = conversation;
    if (state == null) {
      if (loading) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading world…'),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error ?? 'Could not load the world.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }
    final busy = loading || editing;
    final enabled = !busy && error == null && state.pending == null;
    return Column(
      children: [
        if (busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(editing ? 'Updating world…' : 'Refreshing world…'),
          const SizedBox(height: 8),
        ] else if (error != null) ...[
          Text(
            error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(onPressed: onRetry, child: const Text('Refresh world')),
        ],
        Expanded(
          child: WorldDisplay(
            world: state.world,
            selectedProperty: selectedProperty,
            selectedUnplacedObjectId: selectedUnplacedObjectId,
            onUnplacedObjectSelected: enabled ? onUnplacedObjectSelected : null,
            onPropertyChanged: enabled ? onPropertyChanged : null,
            onPaint: enabled ? onPaint : null,
            onErase: enabled ? onErase : null,
            onClear: enabled ? onClear : null,
            interactionHint: busy
                ? 'Please wait…'
                : error != null
                ? 'Refresh the world before editing.'
                : state.pending != null
                ? 'Choose an object in Chat, or undo the entry.'
                : null,
          ),
        ),
      ],
    );
  }
}
