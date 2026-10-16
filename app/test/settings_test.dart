import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/services/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('night map setting: saved, reloaded, auto by default and for unknown values', () async {
    SharedPreferences.setMockInitialValues({});
    expect((await SettingsStore.load()).nightMap, NightMap.auto);
    await SettingsStore.save((await SettingsStore.load()).copyWith(nightMap: NightMap.always));
    expect((await SettingsStore.load()).nightMap, NightMap.always);
    expect(NightMap.parse('sometimes'), NightMap.auto);
  });
}
