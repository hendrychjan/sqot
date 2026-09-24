import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

List<LatLng> parseGpxRoute(String? gpxContent) {
  if (gpxContent == null || gpxContent.trim().isEmpty) {
    return <LatLng>[];
  }

  try {
    final document = XmlDocument.parse(gpxContent);
    final trackPoints = document.findAllElements('trkpt');
    final routePoints = trackPoints.isNotEmpty
        ? trackPoints
        : document.findAllElements('rtept');

    return routePoints
        .map((point) {
          final lat = double.tryParse(point.getAttribute('lat') ?? '');
          final lon = double.tryParse(point.getAttribute('lon') ?? '');
          if (lat == null || lon == null) {
            return null;
          }
          return LatLng(lat, lon);
        })
        .whereType<LatLng>()
        .toList();
  } catch (_) {
    return <LatLng>[];
  }
}
