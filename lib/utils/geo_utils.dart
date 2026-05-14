import 'dart:math';

class GeoUtils {
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const p = 0.017453292519943295;
    final a =
        0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }

  static double calculateBearing(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLon = (lon2 - lon1) * (pi / 180);
    final y = sin(dLon) * cos(lat2 * (pi / 180));
    final x =
        cos(lat1 * (pi / 180)) * sin(lat2 * (pi / 180)) -
        sin(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) * cos(dLon);
    final brng = atan2(y, x) * (180 / pi);
    return (brng + 360) % 360;
  }
}
