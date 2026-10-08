import 'world_object.dart';

class World {
  World({int width = 8, int height = 8, List<WorldObject> objects = const []})
    : objects = List.unmodifiable(objects),
      width = width,
      height = height {
    if (width <= 0) {
      throw RangeError.value(width, 'width', 'Must be positive');
    }
    if (height <= 0) {
      throw RangeError.value(height, 'height', 'Must be positive');
    }
  }

  final int width;
  final int height;
  final List<WorldObject> objects;

  /// Whether any object lies outside this world's dimensions.
  bool hasOutOfRangeCoordinates() => objects.any(
    (object) =>
        object.x < 0 || object.x >= width || object.y < 0 || object.y >= height,
  );

  /// Whether two or more objects occupy the same cell.
  bool hasCollisions() {
    final occupiedCells = <(int, int)>{};
    for (final object in objects) {
      if (!occupiedCells.add((object.x, object.y))) {
        return true;
      }
    }
    return false;
  }
}
