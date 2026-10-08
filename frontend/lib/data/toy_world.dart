import '../models/world.dart';
import '../models/world_object.dart';

/// A fixed sample scene for frontend development.
final toyWorld = World(
  width: 8,
  height: 8,
  objects: const [
    WorldObject(
      id: 0,
      shape: ObjectShape.cube,
      size: ObjectSize.medium,
      color: ObjectColor.red,
      position: BoardPosition(1, 7),
    ),
    WorldObject(
      id: 1,
      shape: ObjectShape.sphere,
      size: ObjectSize.small,
      color: ObjectColor.blue,
      position: BoardPosition(5, 6),
    ),
    WorldObject(
      id: 2,
      shape: ObjectShape.pyramid,
      size: ObjectSize.large,
      position: BoardPosition(3, 5),
    ),
    WorldObject(
      id: 3,
      size: ObjectSize.large,
      color: ObjectColor.green,
      position: BoardPosition(0, 3),
    ),
    WorldObject(
      id: 4,
      shape: ObjectShape.cube,
      color: ObjectColor.yellow,
      position: BoardPosition(6, 3),
    ),
    WorldObject(
      id: 5,
      shape: ObjectShape.pyramid,
      size: ObjectSize.medium,
      color: ObjectColor.blue,
    ),
    WorldObject(id: 6, shape: ObjectShape.cube, size: ObjectSize.large),
  ],
);
