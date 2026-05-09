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

  static Uint8List encodeMainPacket({
    required int stableId,
    required Uint8List profileHash,
    required bool isIOS,
    required bool isOnline,
  }) {
    final data = Uint8List(6);
    final buffer = ByteData.view(data.buffer);

    // Stable ID (4 bytes / 32 bits)
    buffer.setUint32(0, stableId, Endian.big);

    // Profile Hash Prefix (14 bits) + Flags (2 bits) into remaining 2 bytes
    // Read first 2 bytes of hash
    int hashPrefix = (profileHash[0] << 8 | profileHash[1]) >> 2; // Keep top 14 bits

    int flags = 0;
    if (isIOS) flags |= 0x02;
    if (isOnline) flags |= 0x01;

    int finalTwoBytes = (hashPrefix << 2) | flags;
    buffer.setUint16(4, finalTwoBytes, Endian.big);

    return data;
  }

  static Uint8List encodeScanResponseData({
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

    // Full Hash (6)
    data.setRange(6, 12, profileHash);

    return data;
  }
}
