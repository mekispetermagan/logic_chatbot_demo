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
  bloom,
  spark,
  drop,
  loop;

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
      bloom => ObjectShape.bloom,
      spark => ObjectShape.spark,
      drop => ObjectShape.drop,
      loop => ObjectShape.loop,
      _ => object.shape,
    },
  );
}
