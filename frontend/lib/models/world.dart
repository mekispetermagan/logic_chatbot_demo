import 'world_object.dart';

class World {
  factory World.fromJson(Map<String, dynamic> json) => World(
    width: json['width'] as int,
    height: json['height'] as int,
    objects: (json['objects'] as List<dynamic>)
        .map((object) => WorldObject.fromJson(object as Map<String, dynamic>))
        .toList(),
  );
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

  int get nextId =>
      objects.fold<int>(
        -1,
        (largest, object) => object.id > largest ? object.id : largest,
      ) +
      1;

  /// Unplaced objects do not have coordinates to validate.
  bool hasOutOfRangeCoordinates() => objects.any((object) {
    final position = object.position;
    return position != null &&
        (position.x < 0 ||
            position.x >= width ||
            position.y < 0 ||
            position.y >= height);
  });

  bool hasCollisions() {
    final occupiedCells = <BoardPosition>{};
    for (final object in objects) {
      final position = object.position;
      if (position != null && !occupiedCells.add(position)) return true;
    }
    return false;
  }
}
