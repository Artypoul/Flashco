import 'dart:async';
import 'dart:convert';

import 'package:flashco/common/preferences.dart';
import 'package:flashco/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_fallback_test.dart' show settings;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url = 'https://subscription.example.invalid/profile';
  late Completer<SharedPreferences?> original;

  setUp(() async {
    original = preferences.sharedPreferencesCompleter;
    SharedPreferences.setMockInitialValues({});
    preferences.sharedPreferencesCompleter = Completer()
      ..complete(await SharedPreferences.getInstance());
  });
  tearDown(() => preferences.sharedPreferencesCompleter = original);

  Future<void> stage({bool fresh = true, bool enabled = true}) =>
      preferences.stageBundledFallback(
        url,
        jsonEncode(settings.toJson()),
        isNewInstallation: fresh,
        enabled: enabled,
      );

  test('only fresh eligible installations receive pending defaults', () async {
    await stage(fresh: false);
    expect(await preferences.pendingBundledFallback(url), isNull);
    await stage(enabled: false);
    expect(await preferences.pendingBundledFallback(url), isNull);
    await stage();
    expect(await preferences.pendingBundledFallback(url), settings);
    expect(
      await preferences.pendingBundledFallback('https://other.example.invalid'),
      isNull,
    );
  });

  test(
    'pending defaults survive preferences recreation and later startup',
    () async {
      await stage();
      await preferences.saveConfig(const Config(themeProps: defaultThemeProps));
      preferences.sharedPreferencesCompleter = Completer()
        ..complete(await SharedPreferences.getInstance());
      await stage(fresh: false);
      expect(await preferences.pendingBundledFallback(url), settings);
      await preferences.completeBundledFallback(url);
      expect(await preferences.pendingBundledFallback(url), isNull);
    },
  );

  test(
    'does not replace a pending configuration with newer build defaults',
    () async {
      await stage();
      await preferences.stageBundledFallback(
        url,
        jsonEncode(settings.copyWith(interval: 60).toJson()),
        isNewInstallation: true,
        enabled: true,
      );
      expect(await preferences.pendingBundledFallback(url), settings);
    },
  );
}
