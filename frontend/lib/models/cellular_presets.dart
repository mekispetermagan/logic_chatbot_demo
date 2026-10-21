import 'cellular_world.dart';

abstract final class CellularPresets {
  static final life = CellularRuleset(
    palette: [CellColor.white, CellColor.black],
    neighborhood: 8,
    rules: {
      CellColor.white: CellularRule(
        targetColor: CellColor.black,
        neighborColor: CellColor.black,
        counts: {3},
      ),
      CellColor.black: CellularRule(
        targetColor: CellColor.white,
        neighborColor: CellColor.white,
        counts: {0, 1, 2, 3, 4, 7, 8},
      ),
    },
  );

  static final rgb = CellularRuleset(
    palette: [CellColor.red, CellColor.green, CellColor.blue],
    neighborhood: 8,
    rules: {
      for (final (source, target) in [
        (CellColor.red, CellColor.green),
        (CellColor.green, CellColor.blue),
        (CellColor.blue, CellColor.red),
      ])
        source: CellularRule(
          targetColor: target,
          neighborColor: target,
          counts: {2, 3, 4, 5, 6, 7, 8},
        ),
    },
  );
}
