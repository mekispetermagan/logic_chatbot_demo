enum ObjectShape { cube, sphere, pyramid }

enum ObjectSize { small, medium, large }

enum ObjectColor { red, blue, green, yellow }

/// An object on the board, with the origin at the bottom-left cell (A1).
///
/// [x] increases to the right and [y] increases upward; both are zero-based.
class WorldObject {
  const WorldObject({
    required this.shape,
    required this.size,
    required this.color,
    required this.x,
    required this.y,
  });

  final ObjectShape shape;
  final ObjectSize size;
  final ObjectColor color;
  final int x;
  final int y;
}
