import 'package:flutter/material.dart';

import '../controllers/cellular_ruleset_controller.dart';
import '../models/cellular_presets.dart';
import '../models/cellular_world.dart';
import 'cellular_palette.dart';

/// Owns the form controller's lifetime and modal presentation. The controller
/// owns draft validation and submission; the conversation callback owns HTTP.
class CellularRulesetDialog extends StatefulWidget {
  const CellularRulesetDialog({
    super.key,
    required this.world,
    required this.onSubmit,
  });
  final CellularWorld world;
  final Future<bool> Function(CellularRuleset, bool) onSubmit;

  @override
  State<CellularRulesetDialog> createState() => _CellularRulesetDialogState();
}

class _CellularRulesetDialogState extends State<CellularRulesetDialog> {
  late final CellularRulesetController draft;
  @override
  void initState() {
    super.initState();
    draft = CellularRulesetController(
      world: widget.world,
      onSubmit: widget.onSubmit,
    );
  }

  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    var refill = false;
    if (draft.requiresRefill) {
      refill =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Randomly refill the board?'),
              content: const Text(
                'The selected palette excludes colors on the board. Replace every cell with a random selected color and start generation 0? You can undo the whole change.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const ValueKey('confirm-cellular-refill'),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Refill and submit'),
                ),
              ],
            ),
          ) ??
          false;
      if (!refill) return;
    }
    if (!mounted) return;
    if (await draft.submit(refill: refill) && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: draft,
    builder: (context, _) => PopScope(
      canPop: !draft.submitting,
      child: AlertDialog(
        title: const Text('Edit cellular rules'),
        insetPadding: const EdgeInsets.all(12),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Palette — select at least two colors'),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final color in CellColor.values)
                      FilterChip(
                        key: ValueKey('rules-palette-${color.name}'),
                        avatar: _swatch(color),
                        label: Text(color.name),
                        selected: draft.palette.contains(color),
                        onSelected: draft.submitting
                            ? null
                            : (_) => draft.toggleColor(color),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 8, label: Text('Moore (8)')),
                    ButtonSegment(value: 4, label: Text('von Neumann (4)')),
                  ],
                  selected: {draft.neighborhood},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 6),
                    ),
                    minimumSize: WidgetStatePropertyAll(Size(0, 40)),
                    visualDensity: VisualDensity.compact,
                  ),
                  onSelectionChanged: draft.submitting
                      ? null
                      : (values) => draft.setNeighborhood(values.single),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Count neighbors of the target color. A disabled rule keeps its source color.',
                ),
                for (final source in draft.palette)
                  _RuleRow(
                    source: source,
                    rule: draft.ruleFor(source),
                    palette: draft.palette,
                    neighborhood: draft.neighborhood,
                    enabled: !draft.submitting,
                    onEnabled: (value) => draft.setRule(source, enabled: value),
                    onTarget: (color) => draft.setRule(source, target: color),
                    onCount: (count) =>
                        draft.setRule(source, toggleCount: count),
                    onClearInvalid: () =>
                        draft.setRule(source, clearInvalid: true),
                  ),
                const SizedBox(height: 12),
                const Text('Presets — prefill this form'),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      key: const ValueKey('preset-life'),
                      onPressed: draft.submitting
                          ? null
                          : () => draft.usePreset(CellularPresets.life),
                      child: const Text('Game of Life'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('preset-rgb'),
                      onPressed: draft.submitting
                          ? null
                          : () => draft.usePreset(CellularPresets.rgb),
                      child: const Text('RGB cycle'),
                    ),
                  ],
                ),
                if (draft.submissionError ?? draft.validationError
                    case final String error)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: draft.submitting ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('submit-cellular-rules'),
            onPressed: draft.canSubmit ? _submit : null,
            child: Text(draft.submitting ? 'Submitting…' : 'Submit'),
          ),
        ],
      ),
    ),
  );
}

Widget _swatch(CellColor color) => Container(
  width: 16,
  height: 16,
  decoration: BoxDecoration(
    color: CellularPalette.forColor(color),
    border: Border.all(color: const Color(0xFF808080)),
    borderRadius: BorderRadius.circular(3),
  ),
);

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.source,
    required this.rule,
    required this.palette,
    required this.neighborhood,
    required this.enabled,
    required this.onEnabled,
    required this.onTarget,
    required this.onCount,
    required this.onClearInvalid,
  });
  final CellColor source;
  final EditableCellularRule rule;
  final List<CellColor> palette;
  final int neighborhood;
  final bool enabled;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<CellColor> onTarget;
  final ValueChanged<int> onCount;
  final VoidCallback onClearInvalid;

  @override
  Widget build(BuildContext context) {
    final targets = palette.where((color) => color != source).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                key: ValueKey('rule-enabled-${source.name}'),
                value: rule.enabled,
                onChanged: enabled ? (value) => onEnabled(value!) : null,
              ),
              _swatch(source),
              const SizedBox(width: 6),
              Expanded(child: Text('For ${source.name} cells')),
            ],
          ),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Count / change to'),
              DropdownButton<CellColor>(
                key: ValueKey('rule-target-${source.name}'),
                value: targets.contains(rule.target) ? rule.target : null,
                hint: const Text('Choose color'),
                items: [
                  for (final color in targets)
                    DropdownMenuItem(
                      value: color,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _swatch(color),
                          const SizedBox(width: 6),
                          Text(color.name),
                        ],
                      ),
                    ),
                ],
                onChanged: enabled
                    ? (color) {
                        if (color != null) onTarget(color);
                      }
                    : null,
              ),
            ],
          ),
          Wrap(
            spacing: 4,
            children: [
              for (var count = 0; count <= neighborhood; count++)
                FilterChip(
                  key: ValueKey('rule-count-${source.name}-$count'),
                  label: Text('$count'),
                  selected: rule.counts.contains(count),
                  onSelected: enabled ? (_) => onCount(count) : null,
                ),
            ],
          ),
          if (rule.counts.any((n) => n > neighborhood))
            TextButton(
              onPressed: enabled ? onClearInvalid : null,
              child: Text('Remove counts above $neighborhood'),
            ),
          if (rule.incompatible)
            const Text(
              'Stored rule counts a different color. Choose the target color and counts to replace it.',
            ),
        ],
      ),
    );
  }
}
