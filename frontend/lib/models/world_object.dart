enum ObjectShape { cube, sphere, pyramid }

enum ObjectSize { small, medium, large }

enum ObjectColor { red, blue, green, yellow }

/// A complete pair of zero-based coordinates, with A1 at the bottom left.
class BoardPosition {
  const BoardPosition(this.x, this.y);
  factory BoardPosition.fromJson(Map<String, dynamic> json) =>
      BoardPosition(json['x'] as int, json['y'] as int);
  final int x;
  final int y;

  String get square {
    var column = x + 1;
    var label = '';
    if (column <= 0) return '($x, $y)';
    while (column > 0) {
      column--;
      label = String.fromCharCode(65 + column % 26) + label;
      column ~/= 26;
    }
    return '$label${y + 1}';
  }

  @override
  bool operator ==(Object other) =>
      other is BoardPosition && x == other.x && y == other.y;
  @override
  int get hashCode => Object.hash(x, y);
}

/// Missing attributes are absent, rather than unknown.
class WorldObject {
  const WorldObject({
    required this.id,
    this.shape,
    this.size,
    this.color,
    this.position,
  });
  factory WorldObject.fromJson(Map<String, dynamic> json) => WorldObject(
    id: json['id'] as int,
    shape: json['shape'] == null
        ? null
        : ObjectShape.values.byName(json['shape'] as String),
    size: json['size'] == null
        ? null
        : ObjectSize.values.byName(json['size'] as String),
    color: json['color'] == null
        ? null
        : ObjectColor.values.byName(json['color'] as String),
    position: json['position'] == null
        ? null
        : BoardPosition.fromJson(json['position'] as Map<String, dynamic>),
  );
  final int id;
  final ObjectShape? shape;
  final ObjectSize? size;
  final ObjectColor? color;
  final BoardPosition? position;
}
