import 'dart:typed_data';

class MeshPacketEncoder {
  /// Compresses a coordinate into a 24-bit fixed-point integer.
  static int encodeCoordinate(double value, bool isLatitude) {
    final double min = isLatitude ? -90.0 : -180.0;
    final double max = isLatitude ? 90.0 : 180.0;
    final double range = max - min;

    const int max24 = 0xFFFFFF;
    final normalized = (value - min) / range;
    return (normalized * max24).round().clamp(0, max24);
  }

  static double decodeCoordinate(int encoded, bool isLatitude) {
    final double min = isLatitude ? -90.0 : -180.0;
    final double max = isLatitude ? 90.0 : 180.0;
    final double range = max - min;

    const int max24 = 0xFFFFFF;
    return (encoded / max24 * range) + min;
  }

  static Uint8List encodeManufacturerData({
    required double latitude,
    required double longitude,
    required bool isIOS,
    required bool isOnline,
    required Uint8List profileHash,
  }) {
    final lat24 = encodeCoordinate(latitude, true);
    final lon24 = encodeCoordinate(longitude, false);

    final data = Uint8List(9);

    // Lat (3 bytes)
    data[0] = (lat24 >> 16) & 0xFF;
    data[1] = (lat24 >> 8) & 0xFF;
    data[2] = lat24 & 0xFF;

    // Lon (3 bytes)
    data[3] = (lon24 >> 16) & 0xFF;
    data[4] = (lon24 >> 8) & 0xFF;
    data[5] = lon24 & 0xFF;

    // Short Hash (2 bytes) - First 2 bytes of the full 6-byte hash
    data[6] = profileHash[0];
    data[7] = profileHash[1];

    // Flags (1 byte)
    // Bit 0: isIOS
    // Bit 1: isOnline
    int flags = 0;
    if (isIOS) flags |= 0x01;
    if (isOnline) flags |= 0x02;
    data[8] = flags;

    return data;
  }
}
