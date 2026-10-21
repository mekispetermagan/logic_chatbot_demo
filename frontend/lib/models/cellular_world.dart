import 'grid_world.dart';

enum CellColor { white, black, red, green, blue, yellow }

class CellularRule {
  CellularRule({
    required this.targetColor,
    required this.neighborColor,
    required Set<int> counts,
    this.enabled = true,
  }) : counts = Set.unmodifiable(counts);

  factory CellularRule.fromJson(Map<String, dynamic> json) {
    final counts = (json['counts'] as List<dynamic>).cast<int>();
    if (counts.toSet().length != counts.length) {
      throw const FormatException('Duplicate neighbor count');
    }
    return CellularRule(
      targetColor: CellColor.values.byName(json['targetColor'] as String),
      neighborColor: CellColor.values.byName(json['neighborColor'] as String),
      counts: counts.toSet(),
      enabled: json['enabled'] as bool,
    );
  }

  final CellColor targetColor;
  final CellColor neighborColor;
  final Set<int> counts;
  final bool enabled;

  Map<String, dynamic> toJson() => {
    'targetColor': targetColor.name,
    'neighborColor': neighborColor.name,
    'counts': counts.toList()..sort(),
    'enabled': enabled,
  };
}

class CellularRuleset {
  CellularRuleset({
    required List<CellColor> palette,
    required this.neighborhood,
    required Map<CellColor, CellularRule> rules,
  }) : palette = List.unmodifiable(palette),
       rules = Map.unmodifiable(rules) {
    final active = palette.toSet();
    if (active.length < 2 ||
        active.length > 6 ||
        active.length != palette.length ||
        (neighborhood != 4 && neighborhood != 8)) {
      throw const FormatException('Invalid cellular palette or neighborhood');
    }
    for (final entry in rules.entries) {
      final rule = entry.value;
      if (!active.containsAll([
            entry.key,
            rule.targetColor,
            rule.neighborColor,
          ]) ||
          entry.key == rule.targetColor ||
          rule.counts.any((count) => count < 0 || count > neighborhood)) {
        throw const FormatException('Invalid cellular rule');
      }
    }
  }

  factory CellularRuleset.fromJson(Map<String, dynamic> json) =>
      CellularRuleset(
        palette: (json['palette'] as List<dynamic>)
            .map((color) => CellColor.values.byName(color as String))
            .toList(),
        neighborhood: json['neighborhood'] as int,
        rules: (json['rules'] as Map<String, dynamic>).map(
          (color, rule) => MapEntry(
            CellColor.values.byName(color),
            CellularRule.fromJson(rule as Map<String, dynamic>),
          ),
        ),
      );

  final List<CellColor> palette;
  final int neighborhood;
  final Map<CellColor, CellularRule> rules;

  Map<String, dynamic> toJson() => {
    'palette': palette.map((color) => color.name).toList(),
    'neighborhood': neighborhood,
    'rules': {
      for (final entry in rules.entries) entry.key.name: entry.value.toJson(),
    },
  };
}

class CellularWorld implements GridWorld {
  static const boardSize = 16;
  static const cellCount = boardSize * boardSize;

  CellularWorld({
    required List<CellColor> cells,
    required this.ruleset,
    required this.generation,
    required this.rulesetRevision,
  }) : cells = List.unmodifiable(cells) {
    if (cells.length != cellCount ||
        generation < 0 ||
        rulesetRevision < 1 ||
        !ruleset.palette.toSet().containsAll(cells)) {
      throw const FormatException('Invalid cellular world');
    }
  }

  factory CellularWorld.fromJson(Map<String, dynamic> json) {
    if ((json['width'] as int) != boardSize ||
        (json['height'] as int) != boardSize ||
        json['topology'] != 'torus' ||
        json.containsKey('objects')) {
      throw const FormatException('Expected a 16 by 16 cellular torus');
    }
    return CellularWorld(
      cells: (json['cells'] as List<dynamic>)
          .map((color) => CellColor.values.byName(color as String))
          .toList(),
      ruleset: CellularRuleset.fromJson(
        json['ruleset'] as Map<String, dynamic>,
      ),
      generation: json['generation'] as int,
      rulesetRevision: json['rulesetRevision'] as int,
    );
  }

  @override
  int get width => boardSize;
  @override
  int get height => boardSize;
  final List<CellColor> cells;
  final CellularRuleset ruleset;
  final int generation;
  final int rulesetRevision;

  CellColor colorAt(int x, int y) {
    RangeError.checkValueInInterval(x, 0, boardSize - 1, 'x');
    RangeError.checkValueInInterval(y, 0, boardSize - 1, 'y');
    return cells[x + boardSize * y];
  }
}
