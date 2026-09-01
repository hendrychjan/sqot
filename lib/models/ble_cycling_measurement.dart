import 'dart:typed_data';

class BleCyclingMeasurement {
  final int? cumulativeWheelRevolutions;
  final int? lastWheelEventTime;
  final int? cumulativeCrankRevolutions;
  final int? lastCrankEventTime;

  const BleCyclingMeasurement({
    required this.cumulativeWheelRevolutions,
    required this.lastWheelEventTime,
    required this.cumulativeCrankRevolutions,
    required this.lastCrankEventTime,
  });

  factory BleCyclingMeasurement.fromBytes(Uint8List value) {
    if (value.isEmpty) {
      return const BleCyclingMeasurement(
        cumulativeWheelRevolutions: null,
        lastWheelEventTime: null,
        cumulativeCrankRevolutions: null,
        lastCrankEventTime: null,
      );
    }

    final flags = value[0];
    final hasWheelData = (flags & 0x01) != 0;
    final hasCrankData = (flags & 0x02) != 0;

    int index = 1;
    int? cumulativeWheelRevolutions;
    int? lastWheelEventTime;
    int? cumulativeCrankRevolutions;
    int? lastCrankEventTime;

    if (hasWheelData && value.length >= index + 6) {
      cumulativeWheelRevolutions =
          value[index] |
          (value[index + 1] << 8) |
          (value[index + 2] << 16) |
          (value[index + 3] << 24);
      index += 4;

      lastWheelEventTime = value[index] | (value[index + 1] << 8);
      index += 2;
    }

    if (hasCrankData && value.length >= index + 4) {
      cumulativeCrankRevolutions = value[index] | (value[index + 1] << 8);
      index += 2;

      lastCrankEventTime = value[index] | (value[index + 1] << 8);
    }

    return BleCyclingMeasurement(
      cumulativeWheelRevolutions: cumulativeWheelRevolutions,
      lastWheelEventTime: lastWheelEventTime,
      cumulativeCrankRevolutions: cumulativeCrankRevolutions,
      lastCrankEventTime: lastCrankEventTime,
    );
  }
}
