import 'attribute_property.dart';
import 'world_object.dart';

/// All independent port combinations. Bits follow north/east/south/west.
enum NetworkShape {
  empty(0, '·'),
  west(8, '╴'),
  north(1, '╵'),
  east(2, '╶'),
  south(4, '╷'),
  eastWest(10, '─'),
  northSouth(5, '│'),
  northEast(3, '└'),
  eastSouth(6, '┌'),
  southWest(12, '┐'),
  northWest(9, '┘'),
  northEastSouth(7, '├'),
  northSouthWest(13, '┤'),
  eastSouthWest(14, '┬'),
  northEastWest(11, '┴'),
  all(15, '┼');

  const NetworkShape(this.mask, this.symbol);
  final int mask;
  final String symbol;
  List<NetworkPort> get ports => [
    for (final port in NetworkPort.values)
      if (mask & (1 << port.index) != 0) port,
  ];
  String get assetName =>
      mask == 0 ? 'empty' : ports.map((port) => port.name[0]).join();
  String get label =>
      mask == 0 ? 'No ports' : ports.map((port) => port.name).join(', ');
  static NetworkShape fromObject(WorldObject object) => values.firstWhere(
    (shape) =>
        shape.mask ==
        NetworkPort.values.fold<int>(
          0,
          (mask, port) => mask | (object.hasPort(port) ? 1 << port.index : 0),
        ),
  );
}
