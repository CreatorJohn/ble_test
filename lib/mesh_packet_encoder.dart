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

  /// Encodes the primary advertisement manufacturer data (exactly 5 bytes).
  /// This minimal payload fits alongside the 16-byte Service UUID in a 31-byte packet.
  static Uint8List encodeMainPacket({
    required int stableId,
    required Uint8List profileHash,
    required bool isIOS,
    required bool isOnline,
  }) {
    final data = Uint8List(5);
    final buffer = ByteData.view(data.buffer);

    // Stable ID (4 bytes / 32 bits)
    buffer.setUint32(0, stableId, Endian.big);

    // Byte 4: Version Tag (top 6 bits) + Flags (bottom 2 bits)
    // 000000 (Tag) | 00 (Flags)
    int versionTag = (profileHash[0] >> 2) & 0x3F;

    int flags = 0;
    if (isIOS) flags |= 0x02;
    if (isOnline) flags |= 0x01;

    data[4] = (versionTag << 2) | flags;

    return data;
  }

  /// Encodes the scan response metadata (12 bytes) as raw manufacturer data.
  static Uint8List encodeScanResponseManufacturerData({
    required double latitude,
    required double longitude,
    required Uint8List profileHash,
  }) {
    final lat24 = encodeCoordinate(latitude, true);
    final lon24 = encodeCoordinate(longitude, false);

    final data = Uint8List(12);
    // Lat (3) + Lon (3)
    data[0] = (lat24 >> 16) & 0xFF;
    data[1] = (lat24 >> 8) & 0xFF;
    data[2] = lat24 & 0xFF;

    data[3] = (lon24 >> 16) & 0xFF;
    data[4] = (lon24 >> 8) & 0xFF;
    data[5] = lon24 & 0xFF;

    // Full Hash (6 bytes)
    data.setRange(6, 12, profileHash);

    return data;
  }

  /// Encodes 24-bit Lat/Long into a 6-byte buffer for GATT.
  static Uint8List encodeLocation(double lat, double lon) {
    final lat24 = encodeCoordinate(lat, true);
    final lon24 = encodeCoordinate(lon, false);
    final data = Uint8List(6);
    data[0] = (lat24 >> 16) & 0xFF;
    data[1] = (lat24 >> 8) & 0xFF;
    data[2] = lat24 & 0xFF;
    data[3] = (lon24 >> 16) & 0xFF;
    data[4] = (lon24 >> 8) & 0xFF;
    data[5] = lon24 & 0xFF;
    return data;
  }
}
