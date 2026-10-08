import 'package:flutter/foundation.dart';

import '../models/world.dart';
import '../models/world_object.dart';

class WorldDisplayController extends ChangeNotifier {
  WorldDisplayController({required World initialWorld})
    : _history = [initialWorld];

  final List<World> _history;
  World get world => _history.last;
  List<World> get history => List.unmodifiable(_history);
  bool get canUndo => _history.length >= 2;

  ObjectColor _color = ObjectColor.red;
  ObjectSize _size = ObjectSize.medium;
  ObjectShape _shape = ObjectShape.cube;
  ObjectColor get color => _color;
  ObjectSize get size => _size;
  ObjectShape get shape => _shape;

  void selectColor(ObjectColor value) {
    if (_color == value) return;
    _color = value;
    notifyListeners();
  }

  void selectSize(ObjectSize value) {
    if (_size == value) return;
    _size = value;
    notifyListeners();
  }

  void selectShape(ObjectShape value) {
    if (_shape == value) return;
    _shape = value;
    notifyListeners();
  }

  bool _contains(int x, int y) =>
      x >= 0 && x < world.width && y >= 0 && y < world.height;

  void paint(int x, int y) {
    if (!_contains(x, y)) return;
    if (world.objects.any(
      (object) =>
          object.x == x &&
          object.y == y &&
          object.color == color &&
          object.size == size &&
          object.shape == shape,
    )) {
      return;
    }
    _append([
      ...world.objects.where((object) => object.x != x || object.y != y),
      WorldObject(shape: shape, size: size, color: color, x: x, y: y),
    ]);
  }

  void erase(int x, int y) {
    if (!_contains(x, y)) return;
    final objects = world.objects
        .where((object) => object.x != x || object.y != y)
        .toList();
    if (objects.length == world.objects.length) return;
    _append(objects);
  }

  void clear() {
    if (world.objects.isEmpty) return;
    _append([]);
  }

  void undo() {
    if (!canUndo) return;
    _history.removeLast();
    notifyListeners();
  }

  void _append(List<WorldObject> objects) {
    _history.add(
      World(width: world.width, height: world.height, objects: objects),
    );
    notifyListeners();
  }
}
