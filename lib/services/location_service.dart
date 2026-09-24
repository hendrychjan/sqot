import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

class LocationService extends GetxService {
  LocationService._();
  factory LocationService() => instance;
  static final LocationService instance = LocationService._();

  final StreamController<Position> _positionController =
      StreamController<Position>.broadcast();

  StreamSubscription<Position>? _positionSubscription;
  bool _isActive = false;
  bool _isRestartingStream = false;
  Position? _lastPosition;

  bool get isActive => _isActive;
  Stream<Position> get positionStream => _positionController.stream;
  Position? get lastPosition => _lastPosition;

  LocationSettings _buildLocationSettings() {
    if (GetPlatform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
      );
    }

    if (GetPlatform.isIOS || GetPlatform.isMacOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
  }

  Future<Position> start() async {
    if (_isActive) {
      if (_lastPosition != null) {
        return _lastPosition!;
      }
      throw StateError(
        'Location service is active but no position is available.',
      );
    }

    final servicesEnabled = await Geolocator.isLocationServiceEnabled();
    if (!servicesEnabled) {
      throw StateError('Location services are disabled on this device.');
    }

    final permission = await _ensurePermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission was not granted.');
    }

    final locationSettings = _buildLocationSettings();

    final initialPosition = await Geolocator.getCurrentPosition(
      locationSettings: locationSettings,
    );
    _publishPosition(initialPosition);

    // Mark active before attaching the stream so early stream errors can trigger restart.
    _isActive = true;
    _attachPositionStream(locationSettings);
    return initialPosition;
  }

  Future<void> stop() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _isRestartingStream = false;
    _isActive = false;
    _lastPosition = null;
  }

  void _attachPositionStream(LocationSettings locationSettings) {
    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (position) {
            _publishPosition(position);
          },
          onError: (error, stackTrace) {
            _positionController.addError(error, stackTrace);
            unawaited(_restartPositionStream(locationSettings));
          },
          onDone: () {
            _positionController.addError(
              StateError('Location stream ended unexpectedly.'),
            );
            unawaited(_restartPositionStream(locationSettings));
          },
        );
  }

  void _publishPosition(Position position) {
    _lastPosition = position;
    _positionController.add(position);
  }

  Future<void> _restartPositionStream(LocationSettings locationSettings) async {
    if (!_isActive || _isRestartingStream) {
      return;
    }

    _isRestartingStream = true;
    try {
      await _positionSubscription?.cancel();
      _positionSubscription = null;

      await Future<void>.delayed(const Duration(seconds: 2));
      if (!_isActive) {
        return;
      }

      _attachPositionStream(locationSettings);
    } catch (error, stackTrace) {
      _positionController.addError(error, stackTrace);
    } finally {
      _isRestartingStream = false;
    }
  }

  Future<LocationPermission> _ensurePermission() async {
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw StateError(
        'Location permission is permanently denied. Enable it in system settings.',
      );
    }

    return permission;
  }
}
