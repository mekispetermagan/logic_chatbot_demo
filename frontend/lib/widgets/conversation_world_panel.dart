import '../models/domain.dart';
import '../models/network_shape.dart';
import '../models/world_object.dart';
import '../models/world.dart';
import '../models/grid_world.dart';
import '../models/cellular_world.dart';
import 'cellular_world_display.dart';
import 'network_selector.dart';
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
    this.selectedNetworkShape = NetworkShape.empty,
    this.selectedNetworkColor = ObjectColor.red,
    this.onNetworkShapeChanged,
    this.onNetworkColorChanged,
    this.selectedProperty = ObjectProperty.red,
    this.selectedUnplacedObjectId,
    this.onPropertyChanged,
    this.onUnplacedObjectSelected,
    this.onPaint,
    this.onErase,
    this.onClear,
    this.previewWorld,
    this.previewLabel = 'Preview — not applied',
    this.onSaveSlot,
    this.onLoadSlot,
    this.onStep,
    this.selectedCellColor = CellColor.black,
    this.onCellColorChanged,
    this.onPaintCell,
    this.onRulesetSubmitted,
  });

  final NetworkShape selectedNetworkShape;
  final ObjectColor? selectedNetworkColor;
  final ValueChanged<NetworkShape>? onNetworkShapeChanged;
  final ValueChanged<ObjectColor>? onNetworkColorChanged;
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
  final GridWorld? previewWorld;
  final String previewLabel;
  final Future<bool> Function(int, bool)? onSaveSlot;
  final Future<bool> Function(int)? onLoadSlot;
  final VoidCallback? onStep;
  final CellColor selectedCellColor;
  final ValueChanged<CellColor>? onCellColorChanged;
  final void Function(int, int)? onPaintCell;
  final Future<bool> Function(CellularRuleset, bool)? onRulesetSubmitted;

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
    final enabled =
        !busy &&
        error == null &&
        !state.resetPending &&
        state.pending == null &&
        state.proposal == null;
    final world = previewWorld ?? state.world;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (world is CellularWorld)
          CellularWorldDisplay(
            world: world,
            selectedColor: selectedCellColor,
            onColorChanged: enabled ? onCellColorChanged : null,
            onPaint: enabled ? onPaintCell : null,
            onRulesetSubmitted: enabled ? onRulesetSubmitted : null,
            onStep: enabled ? onStep : null,
            slots: state.worldSlots,
            onSaveSlot: enabled ? onSaveSlot : null,
            onLoadSlot: enabled ? onLoadSlot : null,
          )
        else
          WorldDisplay(
            world: world as World,
            domain: state.domain,
            selector: state.domain == WorldDomain.network
                ? NetworkSelector(
                    selectedShape: selectedNetworkShape,
                    selectedColor: selectedNetworkColor,
                    onShapeChanged: enabled ? onNetworkShapeChanged : null,
                    onColorChanged: enabled ? onNetworkColorChanged : null,
                  )
                : null,
            selectedProperty: selectedProperty,
            selectedUnplacedObjectId: selectedUnplacedObjectId,
            onUnplacedObjectSelected: enabled ? onUnplacedObjectSelected : null,
            onPropertyChanged: enabled ? onPropertyChanged : null,
            onPaint: enabled ? onPaint : null,
            onErase: enabled ? onErase : null,
            onClear: enabled ? onClear : null,
            worldSlots: state.worldSlots,
            onSaveSlot: enabled ? onSaveSlot : null,
            onLoadSlot: enabled ? onLoadSlot : null,
            interactionHint: busy
                ? 'Please wait…'
                : error != null
                ? 'Refresh the world before editing.'
                : state.resetPending
                ? 'Reply yes or no in Chat to confirm or cancel the reset.'
                : state.pending != null
                ? 'Choose an object in Chat, or undo the entry.'
                : state.proposal != null
                ? 'Review the interpretation in Chat.'
                : null,
          ),
        if (previewWorld != null)
          Positioned(top: 8, right: 8, child: Chip(label: Text(previewLabel))),
        if (busy)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(),
          ),
        if (!busy && error != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              child: Column(
                children: [
                  Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Refresh world'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
