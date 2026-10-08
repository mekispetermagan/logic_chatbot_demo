import '../models/world.dart';
import '../models/world_object.dart';

/// A fixed sample scene for frontend development.
final toyWorld = World(
  width: 8,
  height: 8,
  objects: const [
    WorldObject(
      shape: ObjectShape.cube,
      size: ObjectSize.medium,
      color: ObjectColor.red,
      x: 1,
      y: 7,
    ),
    WorldObject(
      shape: ObjectShape.sphere,
      size: ObjectSize.small,
      color: ObjectColor.blue,
      x: 5,
      y: 6,
    ),
    WorldObject(
      shape: ObjectShape.pyramid,
      size: ObjectSize.large,
      color: ObjectColor.yellow,
      x: 3,
      y: 5,
    ),
    WorldObject(
      shape: ObjectShape.sphere,
      size: ObjectSize.large,
      color: ObjectColor.green,
      x: 0,
      y: 3,
    ),
    WorldObject(
      shape: ObjectShape.cube,
      size: ObjectSize.small,
      color: ObjectColor.yellow,
      x: 6,
      y: 3,
    ),
    WorldObject(
      shape: ObjectShape.pyramid,
      size: ObjectSize.medium,
      color: ObjectColor.blue,
      x: 2,
      y: 1,
    ),
    WorldObject(
      shape: ObjectShape.cube,
      size: ObjectSize.large,
      color: ObjectColor.green,
      x: 7,
      y: 0,
    ),
  ],
);
