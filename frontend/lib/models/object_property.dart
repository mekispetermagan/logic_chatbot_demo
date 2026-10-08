import 'world_object.dart';

/// The single base property supplied by a visual-editor performative.
enum ObjectProperty {
  red,
  blue,
  green,
  yellow,
  small,
  medium,
  large,
  cube,
  sphere,
  pyramid;

  WorldObject applyTo(WorldObject object) => WorldObject(
    id: object.id,
    position: object.position,
    color: switch (this) {
      red => ObjectColor.red,
      blue => ObjectColor.blue,
      green => ObjectColor.green,
      yellow => ObjectColor.yellow,
      _ => object.color,
    },
    size: switch (this) {
      small => ObjectSize.small,
      medium => ObjectSize.medium,
      large => ObjectSize.large,
      _ => object.size,
    },
    shape: switch (this) {
      cube => ObjectShape.cube,
      sphere => ObjectShape.sphere,
      pyramid => ObjectShape.pyramid,
      _ => object.shape,
    },
  );
}
