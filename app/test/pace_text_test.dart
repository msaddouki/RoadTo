import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/ui/settings_screen.dart';
import 'package:roadto_core/roadto_core.dart';

void main() {
  test('what was learned, in words', () {
    expect(paceText(LearnedPace.none, RoadBand.town), 'pas encore assez de trajets');
    final pace = LearnedPace.none.add({
      RoadBand.town: const PaceSample(3600, 2880),
      RoadBand.fast: const PaceSample(3600, 3960),
    });
    expect(paceText(pace, RoadBand.town), '13 % plus rapide que prévu');
    expect(paceText(pace, RoadBand.fast), '7 % plus lent que prévu');
    expect(paceText(pace, RoadBand.road), 'pas encore assez de trajets');
  });
}
