import 'package:roadto_core/roadto_core.dart';
import 'package:test/test.dart';

// Reference values from the astral library (NOAA algorithm, full precision).
void main() {
  const lyon = LatLon(45.7578, 4.8320);

  test('sun elevation over Lyon', () {
    expect(sunElevationDeg(lyon, DateTime.utc(2026, 10, 12, 3)), closeTo(-30.42, 0.6));
    expect(sunElevationDeg(lyon, DateTime.utc(2026, 10, 12, 11)), closeTo(36.43, 0.6));
    expect(sunElevationDeg(lyon, DateTime.utc(2026, 10, 12, 16, 30)), closeTo(4.54, 0.6));
    expect(sunElevationDeg(lyon, DateTime.utc(2026, 10, 12, 17, 30)), closeTo(-5.88, 0.6));
  });

  test('solar noon height across the year', () {
    expect(sunElevationDeg(lyon, DateTime.utc(2026, 6, 21, 11, 41)), closeTo(67.69, 0.6));
    expect(sunElevationDeg(lyon, DateTime.utc(2026, 12, 21, 11, 38)), closeTo(20.85, 0.6));
  });

  test('night between sunset and sunrise (12 Oct 2026: 05:53 and 17:00 UTC)', () {
    expect(isNight(lyon, DateTime.utc(2026, 10, 12, 5, 40)), isTrue);
    expect(isNight(lyon, DateTime.utc(2026, 10, 12, 6, 10)), isFalse);
    expect(isNight(lyon, DateTime.utc(2026, 10, 12, 16, 45)), isFalse);
    expect(isNight(lyon, DateTime.utc(2026, 10, 12, 17, 15)), isTrue);
  });

  test('midnight sun: no night in Tromsø in June', () {
    expect(sunElevationDeg(const LatLon(69.65, 18.96), DateTime.utc(2026, 6, 21, 23)), closeTo(3.34, 0.6));
    expect(isNight(const LatLon(69.65, 18.96), DateTime.utc(2026, 6, 21, 23)), isFalse);
  });

  test('local time and UTC give the same answer', () {
    final utc = DateTime.utc(2026, 10, 12, 17, 15);
    expect(isNight(lyon, utc.toLocal()), isNight(lyon, utc));
  });
}
