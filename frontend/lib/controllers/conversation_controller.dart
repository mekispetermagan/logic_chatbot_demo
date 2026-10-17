import '../models/domain.dart';
import '../models/network_shape.dart';
import '../models/attribute_property.dart';
import 'package:flutter/foundation.dart';

import '../api/conversation_api.dart';
import '../models/conversation_state.dart';
import '../models/object_property.dart';
import '../models/world_object.dart';
import '../storage/conversation_id_store.dart';

/// Keeps local selection state and displays worlds returned by the server.
class ConversationController extends ChangeNotifier {
  ConversationController({required this.api, required this.store});

  WorldDomain domain = WorldDomain.objects;
  NetworkShape selectedNetworkShape = NetworkShape.empty;
  ObjectColor? selectedNetworkColor = ObjectColor.red;
  bool get canSwitchDomain => !loading && !editing;

  Future<void> switchDomain(WorldDomain next) async {
    if (!canSwitchDomain || next == domain || _disposed) return;
    domain = next;
    conversation = null;
    _pending = null;
    selectedUnplacedObjectId = null;
    await load();
  }

  void selectNetworkShape(NetworkShape shape) {
    if (!canEdit || _disposed) return;
    selectedNetworkShape = shape;
    selectedNetworkColor = null;
    selectedUnplacedObjectId = null;
    notifyListeners();
  }

  void selectNetworkColor(ObjectColor color) {
    if (!canEdit || _disposed) return;
    selectedNetworkColor = color;
    selectedUnplacedObjectId = null;
    notifyListeners();
  }

  final ConversationApi api;
  final ConversationIdStore store;
  ConversationState? conversation;
  ConversationState? _pending;
  bool loading = false;
  bool editing = false;
  bool sendingChat = false;
  bool useLlm = false;

  void setUseLlm(bool value) {
    if (_disposed || loading || editing || useLlm == value) return;
    useLlm = value;
    notifyListeners();
  }

  String? error;
  ObjectProperty selectedProperty = ObjectProperty.red;
  int? selectedUnplacedObjectId;
  bool get canRequest =>
      conversation != null && !loading && !editing && error == null;
  bool get canEdit => canRequest && conversation?.pending == null;
  bool _disposed = false;

  Future<void> load() async {
    if (loading || editing || _disposed) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (_pending == null) {
        final id = await store.read(domain: domain);
        if (_disposed) return;
        if (id == null) {
          _pending = await api.create(domain: domain);
        } else {
          try {
            _pending = await api.get(id);
          } on ApiException catch (exception) {
            if (exception.statusCode != 404) rethrow;
            if (_disposed) return;
            _pending = await api.create(domain: domain);
          }
        }
      }
      if (_disposed) return;
      if (_pending!.domain != domain) {
        throw const ApiException('The server returned an unexpected domain.');
      }
      // Keep the response for retry if local persistence fails: never create twice.
      await store.write(_pending!.id, domain: domain);
      if (_disposed) return;
      conversation = _pending;
      _pending = null;
      _reconcileSelection();
    } on ApiException catch (exception) {
      error = exception.message;
    } catch (_) {
      error = 'Could not read or save the conversation on this device.';
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  void selectProperty(ObjectProperty property) {
    if (!canEdit || _disposed) return;
    selectedProperty = property;
    selectedUnplacedObjectId = null;
    notifyListeners();
  }

  void selectUnplacedObject(int id) {
    if (!canEdit ||
        _disposed ||
        !conversation!.world.objects.any(
          (object) => object.id == id && object.position == null,
        )) {
      return;
    }
    selectedUnplacedObjectId = selectedUnplacedObjectId == id ? null : id;
    notifyListeners();
  }

  Future<void> paint(int x, int y) {
    final selected = selectedUnplacedObjectId;
    return _edit((id) {
      if (selected != null) return api.place(id, selected, BoardPosition(x, y));
      if (domain == WorldDomain.network) {
        final color = selectedNetworkColor;
        return color == null
            ? api.setPorts(id, BoardPosition(x, y), selectedNetworkShape.ports)
            : api.applyProperty(
                id,
                BoardPosition(x, y),
                AttributeProperty('color', color.name),
              );
      }
      return api.applyProperty(
        id,
        BoardPosition(x, y),
        selectedProperty.property,
      );
    });
  }

  Future<void> erase(int x, int y) =>
      _edit((id) => api.erase(id, BoardPosition(x, y)));
  Future<void> clear() => _edit(api.clear, clearSelection: true);
  Future<void> undo() async {
    if (conversation?.canUndo != true) return;
    await _edit(api.undo, clearSelection: true, allowPending: true);
  }

  Future<bool> sendChat(String text) async {
    if (text.trim().isEmpty) return false;
    return _edit((id) => api.chat(id, text, useLlm: useLlm), chat: true);
  }

  Future<bool> clarifySquare(BoardPosition position) => _edit(
    (id) => api.clarifySquare(id, position),
    chat: true,
    allowPending: true,
  );

  Future<bool> clarify(int objectId) =>
      _edit((id) => api.clarify(id, objectId), chat: true, allowPending: true);

  Future<bool> _edit(
    Future<ConversationState> Function(String) request, {
    bool clearSelection = false,
    bool chat = false,
    bool allowPending = false,
  }) async {
    if (!(allowPending ? canRequest : canEdit) || _disposed) return false;
    editing = true;
    sendingChat = chat;
    notifyListeners();
    try {
      final updated = await request(conversation!.id);
      if (_disposed) return false;
      if (updated.domain != conversation!.domain) {
        throw const ApiException('The server returned an unexpected domain.');
      }
      conversation = updated;
      if (clearSelection) selectedUnplacedObjectId = null;
      _reconcileSelection();
      return true;
    } on ApiException catch (exception) {
      error = exception.message;
    } catch (_) {
      error = 'Could not update the world.';
    } finally {
      editing = false;
      sendingChat = false;
      if (!_disposed) notifyListeners();
    }
    return false;
  }

  void _reconcileSelection() {
    if (selectedUnplacedObjectId != null &&
        !conversation!.world.objects.any(
          (object) =>
              object.id == selectedUnplacedObjectId && object.position == null,
        )) {
      selectedUnplacedObjectId = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    api.close();
    super.dispose();
  }
}
