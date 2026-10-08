import 'package:flutter/foundation.dart';

import '../models/world.dart';
import '../models/object_property.dart';
import '../models/world_object.dart';

class WorldDisplayController extends ChangeNotifier {
  WorldDisplayController({required World initialWorld})
    : _history = [initialWorld];

  final List<World> _history;
  World get world => _history.last;
  List<World> get history => List.unmodifiable(_history);
  bool get canUndo => _history.length >= 2;

  ObjectProperty _selectedProperty = ObjectProperty.red;
  ObjectProperty get selectedProperty => _selectedProperty;

  int? _selectedUnplacedObjectId;
  int? get selectedUnplacedObjectId => _selectedUnplacedObjectId;

  void selectUnplacedObject(int id) {
    if (!world.objects.any(
      (object) => object.id == id && object.position == null,
    )) {
      return;
    }
    _selectedUnplacedObjectId = _selectedUnplacedObjectId == id ? null : id;
    notifyListeners();
  }

  void selectProperty(ObjectProperty property) {
    if (_selectedProperty == property && _selectedUnplacedObjectId == null) {
      return;
    }
    _selectedUnplacedObjectId = null;
    _selectedProperty = property;
    notifyListeners();
  }

  bool _contains(int x, int y) =>
      x >= 0 && x < world.width && y >= 0 && y < world.height;

  void paint(int x, int y) {
    if (!_contains(x, y)) return;
    final position = BoardPosition(x, y);
    final matching = world.objects
        .where((object) => object.position == position)
        .toList();
    final selectedId = _selectedUnplacedObjectId;
    if (selectedId != null) {
      if (matching.isNotEmpty) return;
      final unplaced = world.objects
          .where((object) => object.id == selectedId && object.position == null)
          .toList();
      if (unplaced.length != 1) return;
      final selected = unplaced.single;
      final placed = WorldObject(
        id: selected.id,
        shape: selected.shape,
        size: selected.size,
        color: selected.color,
        position: position,
      );
      _selectedUnplacedObjectId = null;
      _append([
        for (final object in world.objects)
          if (identical(object, selected)) placed else object,
      ]);
      return;
    }
    if (matching.length > 1) return;
    if (matching.isEmpty) {
      final created = WorldObject(id: world.nextId, position: position);
      _append([...world.objects, selectedProperty.applyTo(created)]);
      return;
    }
    final previous = matching.single;
    final updated = selectedProperty.applyTo(previous);
    if (previous.color == updated.color &&
        previous.size == updated.size &&
        previous.shape == updated.shape) {
      return;
    }
    _append([
      for (final object in world.objects)
        if (identical(object, previous)) updated else object,
    ]);
  }

  void erase(int x, int y) {
    if (!_contains(x, y)) return;
    final objects = world.objects
        .where((object) => object.position != BoardPosition(x, y))
        .toList();
    if (objects.length == world.objects.length) return;
    _append(objects);
  }

  void clear() {
    _selectedUnplacedObjectId = null;
    if (world.objects.isEmpty) return;
    _append([]);
  }

  void undo() {
    if (!canUndo) return;
    _selectedUnplacedObjectId = null;
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
