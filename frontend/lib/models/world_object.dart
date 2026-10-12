import 'attribute_property.dart';

enum ObjectShape { bloom, spark, drop, loop }

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
  WorldObject({
    required this.id,
    Map<String, String> attributes = const {},
    ObjectShape? shape,
    ObjectSize? size,
    ObjectColor? color,
    this.position,
  }) : attributes = Map.unmodifiable({
         ...attributes,
         if (shape != null) 'shape': shape.name,
         if (size != null) 'size': size.name,
         if (color != null) 'color': color.name,
       });

  factory WorldObject.fromJson(Map<String, dynamic> json) => WorldObject(
    id: json['id'] as int,
    attributes: Map<String, String>.from(json['attributes'] as Map),
    position: json['position'] == null
        ? null
        : BoardPosition.fromJson(json['position'] as Map<String, dynamic>),
  );

  final int id;
  final Map<String, String> attributes;
  final BoardPosition? position;

  ObjectShape? get shape => attributes['shape'] == null
      ? null
      : ObjectShape.values.byName(attributes['shape']!);
  ObjectSize? get size => attributes['size'] == null
      ? null
      : ObjectSize.values.byName(attributes['size']!);
  ObjectColor? get color => attributes['color'] == null
      ? null
      : ObjectColor.values.byName(attributes['color']!);

  bool hasPort(NetworkPort port) => attributes[port.name] == port.name;

  WorldObject withPosition(BoardPosition? position) =>
      WorldObject(id: id, attributes: attributes, position: position);

  WorldObject withProperty(AttributeProperty property) => WorldObject(
    id: id,
    attributes: {...attributes, property.attribute: property.value},
    position: position,
  );
}
