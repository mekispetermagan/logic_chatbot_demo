import 'package:flutter/foundation.dart';

import '../models/cellular_world.dart';

class EditableCellularRule {
  EditableCellularRule({
    required this.target,
    required Set<int> counts,
    required this.enabled,
    required this.present,
    this.incompatible = false,
  }) : counts = Set.unmodifiable(counts);
  final CellColor? target;
  final Set<int> counts;
  final bool enabled;
  final bool present;
  final bool incompatible;
}

/// A local form draft. No API calls happen until submit, and no board evolution
/// or random filling happens in Flutter.
class CellularRulesetController extends ChangeNotifier {
  CellularRulesetController({required this.world, required this.onSubmit}) {
    _load(world.ruleset);
  }
  final CellularWorld world;
  final Future<bool> Function(CellularRuleset, bool) onSubmit;
  late Set<CellColor> _palette;
  late int _neighborhood;
  final Map<CellColor, EditableCellularRule> _rules = {};
  bool submitting = false;
  String? submissionError;
  bool _disposed = false;

  List<CellColor> get palette =>
      CellColor.values.where(_palette.contains).toList();
  int get neighborhood => _neighborhood;
  bool get requiresRefill =>
      world.cells.any((color) => !_palette.contains(color));
  bool get canSubmit =>
      !submitting && submissionError == null && validationError == null;
  EditableCellularRule ruleFor(CellColor source) => _rules[source]!;

  void _load(CellularRuleset config) {
    _palette = config.palette.toSet();
    _neighborhood = config.neighborhood;
    _rules.clear();
    for (final color in CellColor.values) {
      final rule = config.rules[color];
      final others = palette.where((c) => c != color).toList();
      final complement =
          rule != null &&
          config.palette.length == 2 &&
          rule.neighborColor != rule.targetColor;
      _rules[color] = EditableCellularRule(
        target: rule?.targetColor ?? (others.isEmpty ? null : others.first),
        counts: rule == null
            ? {}
            : complement
            ? rule.counts.map((n) => _neighborhood - n).toSet()
            : rule.counts,
        enabled: rule?.enabled ?? false,
        present: rule != null,
        incompatible:
            rule != null &&
            !complement &&
            rule.neighborColor != rule.targetColor,
      );
    }
  }

  String? get validationError {
    if (_palette.length < 2) return 'Select at least two colors.';
    for (final source in palette) {
      final rule = ruleFor(source);
      if (!rule.present && !rule.enabled) continue;
      if (rule.incompatible) {
        return 'Update the counted/target color and counts for ${source.name}.';
      }
      if (rule.target == source || !_palette.contains(rule.target)) {
        return 'Choose a different active target for ${source.name}.';
      }
      if (rule.counts.any((n) => n < 0 || n > neighborhood)) {
        return 'Remove counts above $neighborhood for ${source.name}.';
      }
    }
    return null;
  }

  void toggleColor(CellColor color) {
    if (submitting) return;
    if (!_palette.remove(color)) _palette.add(color);
    notifyListeners();
  }

  void setNeighborhood(int value) {
    if (submitting || (value != 4 && value != 8)) return;
    _neighborhood = value;
    notifyListeners();
  }

  void setRule(
    CellColor source, {
    CellColor? target,
    bool? enabled,
    int? toggleCount,
    bool clearInvalid = false,
  }) {
    if (submitting) return;
    final before = ruleFor(source);
    final counts = before.counts.toSet();
    if (toggleCount != null &&
        toggleCount >= 0 &&
        toggleCount <= neighborhood) {
      if (!counts.remove(toggleCount)) counts.add(toggleCount);
    }
    if (clearInvalid) counts.removeWhere((n) => n > neighborhood);
    _rules[source] = EditableCellularRule(
      target: target ?? before.target,
      counts: counts,
      enabled: enabled ?? before.enabled,
      present: true,
      incompatible:
          target == null && toggleCount == null && before.incompatible,
    );
    notifyListeners();
  }

  void usePreset(CellularRuleset config) {
    if (submitting) return;
    _load(config);
    notifyListeners();
  }

  CellularRuleset buildRuleset() {
    if (validationError != null) throw StateError(validationError!);
    return CellularRuleset(
      palette: palette,
      neighborhood: neighborhood,
      rules: {
        for (final source in palette)
          if (ruleFor(source).present || ruleFor(source).enabled)
            source: CellularRule(
              targetColor: ruleFor(source).target!,
              neighborColor: ruleFor(source).target!,
              counts: ruleFor(source).counts,
              enabled: ruleFor(source).enabled,
            ),
      },
    );
  }

  Future<bool> submit({required bool refill}) async {
    if (!canSubmit || (requiresRefill && !refill)) return false;
    final config = buildRuleset();
    submitting = true;
    notifyListeners();
    try {
      if (await onSubmit(config, refill)) return true;
    } catch (_) {
      // The conversation controller keeps the authoritative response/error.
    } finally {
      submitting = false;
      if (!_disposed) notifyListeners();
    }
    submissionError =
        'Could not apply rules. Close this dialog and refresh the world before retrying.';
    if (!_disposed) notifyListeners();
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
