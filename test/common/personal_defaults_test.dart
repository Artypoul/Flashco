import 'dart:async';

import 'package:flashco/common/personal_defaults.dart';
import 'package:flashco/common/preferences.dart';
import 'package:flashco/enum/enum.dart';
import 'package:flashco/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _url = 'https://example.invalid/subscription';
const _existing = Config(
  currentProfileId: 42,
  excludeSSIDs: ['home'],
  themeProps: ThemeProps(
    themeMode: ThemeMode.dark,
    primaryColor: 0xff123456,
    fontFamily: 'Missing Font',
  ),
  appSettingProps: AppSettingProps(locale: 'en', autoRun: false),
  networkProps: NetworkProps(systemProxy: true, bypassPrivateRoute: false),
  vpnProps: VpnProps(systemProxy: true, allowBypass: true, ipv6: true),
  patchClashConfig: PatchClashConfig(
    mode: Mode.global,
    tun: Tun(stack: TunStack.system, mtu: 1450),
  ),
);

class _FailingConfigStore extends InMemorySharedPreferencesStore {
  _FailingConfigStore() : super.empty();
  bool failConfig = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (failConfig && key == 'flutter.config') return Future.value(false);
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUp(() async {
    final store = await SharedPreferences.getInstance();
    await store.clear();
  });

  test(
    'an existing installation without a marker keeps its settings',
    () async {
      await preferences.saveConfig(_existing);
      final store = await SharedPreferences.getInstance();
      final savedKeys = store.getKeys();

      final updated = await initializePersonalDefaults(
        _existing,
        subscriptionUrl: _url,
        enabled: true,
        isNewInstallation: false,
      );

      expect(updated, _existing);
      expect(await preferences.getConfig(), _existing);
      expect(await preferences.werePersonalDefaultsApplied(), isFalse);
      expect(store.getKeys(), savedKeys);
    },
  );

  test('a fresh-install decision survives migration writes', () async {
    final isNewInstallation = await preferences.isNewInstallation;
    await preferences.saveConfig(const Config(themeProps: ThemeProps()));
    await preferences.setVersion(2);
    expect(await preferences.isNewInstallation, isFalse);

    final updated = await initializePersonalDefaults(
      const Config(themeProps: ThemeProps()),
      subscriptionUrl: _url,
      enabled: true,
      isNewInstallation: isNewInstallation,
    );

    expect(updated.appSettingProps.autoRun, isTrue);
    expect(updated.appSettingProps.autoLaunch, isTrue);
    expect(updated.patchClashConfig.tun.strictRoute, isTrue);
    expect(await preferences.werePersonalDefaultsApplied(), isTrue);
    expect(await preferences.getConfig(), updated);
  });

  test('embedded defaults resume after failed save and store reload', () async {
    final previous = SharedPreferencesStorePlatform.instance;
    final backend = _FailingConfigStore();
    SharedPreferencesStorePlatform.instance = backend;
    addTearDown(() => SharedPreferencesStorePlatform.instance = previous);
    final store = await SharedPreferences.getInstance();
    await store.reload();
    await preferences.beginPersonalDefaultsInitialization(
      enabled: true,
      isNewInstallation: await preferences.isNewInstallation,
    );
    await store.reload();
    expect(await preferences.isNewInstallation, isFalse);
    expect(await preferences.isPersonalDefaultsInitializing, isTrue);
    await preferences.saveConfig(const Config(themeProps: ThemeProps()));
    await preferences.setVersion(2);
    backend.failConfig = true;
    await expectLater(
      initializePersonalDefaults(
        const Config(themeProps: ThemeProps()),
        subscriptionUrl: _url,
        enabled: true,
        isNewInstallation: true,
      ),
      throwsStateError,
    );
    await store.reload();
    expect(await preferences.isNewInstallation, isFalse);
    expect(await preferences.isPersonalDefaultsInitializing, isTrue);
    expect(await preferences.werePersonalDefaultsApplied(), isFalse);
    backend.failConfig = false;
    final resumed = await initializePersonalDefaults(
      (await preferences.getConfig())!,
      subscriptionUrl: _url,
      enabled: true,
      isNewInstallation: await preferences.isPersonalDefaultsInitializing,
    );
    expect(resumed.appSettingProps.locale, 'ru');
    expect(resumed.appSettingProps.autoRun, isTrue);
    expect(resumed.appSettingProps.autoLaunch, isTrue);
    expect(resumed.patchClashConfig.tun.strictRoute, isTrue);
    expect(resumed.patchClashConfig.tunOverride.strictRoute, isTrue);
    expect(
      resumed.patchClashConfig.tunOverrideKeys,
      contains(TunOverrideKey.strictRoute),
    );
    await store.reload();
    expect(await preferences.getConfig(), resumed);
    expect(await preferences.werePersonalDefaultsApplied(), isTrue);
    expect(await preferences.isPersonalDefaultsInitializing, isFalse);
  });

  test('existing installs cannot acquire a fresh defaults intent', () async {
    await preferences.saveConfig(_existing);
    await preferences.beginPersonalDefaultsInitialization(
      enabled: true,
      isNewInstallation: await preferences.isNewInstallation,
    );
    expect(await preferences.isPersonalDefaultsInitializing, isFalse);
    expect(await preferences.getConfig(), _existing);
  });

  test('an existing store without a saved config is left untouched', () async {
    await preferences.setVersion(2);

    final updated = await initializePersonalDefaults(
      _existing,
      subscriptionUrl: _url,
      enabled: true,
      isNewInstallation: await preferences.isNewInstallation,
    );

    expect(updated, _existing);
    expect(await preferences.getConfig(), isNull);
    expect(await preferences.werePersonalDefaultsApplied(), isFalse);
  });

  test(
    'fresh personal defaults preserve unrelated initial config fields',
    () async {
      final updated = await initializePersonalDefaults(
        _existing,
        subscriptionUrl: _url,
        enabled: true,
        isNewInstallation: true,
      );

      expect(updated.themeProps.themeMode, ThemeMode.light);
      expect(updated.themeProps.fontFamily, isNull);
      expect(updated.appSettingProps.autoRun, isTrue);
      expect(updated.appSettingProps.autoLaunch, isTrue);
      expect(updated.appSettingProps.locale, 'ru');
      expect(updated.networkProps.systemProxy, isFalse);
      expect(updated.networkProps.bypassPrivateRoute, isTrue);
      expect(updated.vpnProps.systemProxy, isFalse);
      expect(updated.vpnProps.allowBypass, isFalse);
      expect(updated.patchClashConfig.mode, Mode.rule);
      expect(updated.patchClashConfig.tun.enable, isTrue);
      expect(updated.patchClashConfig.tun.autoRoute, isTrue);
      expect(updated.patchClashConfig.tun.stack, TunStack.mips);
      expect(updated.patchClashConfig.tun.strictRoute, isTrue);
      expect(updated.currentProfileId, 42);
      expect(updated.excludeSSIDs, ['home']);
      expect(updated.themeProps.primaryColor, 0xff123456);
      expect(updated.appSettingProps.locale, 'ru');
      expect(await preferences.getConfig(), updated);
    },
  );

  test(
    'later launches preserve a manual dark theme and disabled auto-run',
    () async {
      await initializePersonalDefaults(
        _existing,
        subscriptionUrl: _url,
        enabled: true,
        isNewInstallation: true,
      );
      await preferences.saveConfig(_existing);

      final reloaded = await initializePersonalDefaults(
        _existing,
        subscriptionUrl: _url,
        enabled: true,
        isNewInstallation: true,
      );

      expect(reloaded, _existing);
      expect(await preferences.getConfig(), _existing);
      expect(reloaded.appSettingProps.autoLaunch, isFalse);
      expect(reloaded.appSettingProps.autoRun, isFalse);
    },
  );

  test(
    'fresh personal install persists auto-run before importing a profile',
    () async {
      final updated = await initializePersonalDefaults(
        const Config(themeProps: ThemeProps()),
        subscriptionUrl: _url,
        enabled: true,
        isNewInstallation: true,
      );

      expect(updated.currentProfileId, isNull);
      expect(updated.themeProps.themeMode, ThemeMode.light);
      expect(updated.appSettingProps.autoRun, isTrue);
      expect(updated.appSettingProps.autoLaunch, isTrue);
    },
  );

  test('changing a bundled URL does not reset later manual choices', () async {
    await initializePersonalDefaults(
      _existing,
      subscriptionUrl: _url,
      enabled: true,
      isNewInstallation: true,
    );
    await preferences.saveConfig(_existing);

    final reloaded = await initializePersonalDefaults(
      _existing,
      subscriptionUrl: 'https://example.invalid/other-subscription',
      enabled: true,
      isNewInstallation: true,
    );

    expect(reloaded, _existing);
    expect(await preferences.getConfig(), _existing);
  });

  test(
    'safe mode and unsupported platforms leave settings and marker untouched',
    () async {
      expect(
        await initializePersonalDefaults(
          _existing,
          subscriptionUrl: _url,
          enabled: false,
          isNewInstallation: true,
        ),
        _existing,
      );
      expect(await preferences.getConfig(), isNull);
      final updated = await initializePersonalDefaults(
        _existing,
        subscriptionUrl: _url,
        enabled: true,
        isNewInstallation: true,
      );
      expect(updated.appSettingProps.autoRun, isTrue);
    },
  );

  test('generic and invalid builds do not change settings', () async {
    for (final url in ['', 'invalid', 'https://', 'file:///subscription']) {
      expect(
        await initializePersonalDefaults(
          _existing,
          subscriptionUrl: url,
          enabled: true,
          isNewInstallation: true,
        ),
        _existing,
      );
    }
    expect(await preferences.getConfig(), isNull);
  });

  test(
    'first-run input applies the same defaults without a bundled URL',
    () async {
      final bundled = await initializePersonalDefaults(
        _existing,
        subscriptionUrl: _url,
        enabled: true,
        isNewInstallation: true,
      );
      final store = await SharedPreferences.getInstance();
      await store.clear();

      final prompted = await initializePersonalDefaults(
        _existing,
        subscriptionUrl: '',
        enabled: true,
        isNewInstallation: true,
        subscriptionOnFirstRun: true,
      );

      expect(prompted, bundled);
      expect(prompted.appSettingProps.autoLaunch, isTrue);
      expect(prompted.appSettingProps.autoRun, isTrue);
      expect(await preferences.getConfig(), bundled);
      expect(await preferences.werePersonalDefaultsApplied(), isTrue);
    },
  );

  test(
    'first-run input preserves existing installations and disabled defaults',
    () async {
      for (final (enabled, isNew) in [(true, false), (false, true)]) {
        final updated = await initializePersonalDefaults(
          _existing,
          subscriptionUrl: '',
          enabled: enabled,
          isNewInstallation: isNew,
          subscriptionOnFirstRun: true,
        );

        expect(updated, _existing);
        expect(await preferences.getConfig(), isNull);
        expect(await preferences.werePersonalDefaultsApplied(), isFalse);
      }
    },
  );

  test(
    'unavailable preferences cannot mark the defaults as complete',
    () async {
      final previous = preferences.sharedPreferencesCompleter;
      preferences.sharedPreferencesCompleter = Completer()..complete(null);
      try {
        expect(
          await initializePersonalDefaults(
            _existing,
            subscriptionUrl: _url,
            enabled: true,
            isNewInstallation: true,
          ),
          _existing,
        );
      } finally {
        preferences.sharedPreferencesCompleter = previous;
      }
      final updated = await initializePersonalDefaults(
        _existing,
        subscriptionUrl: _url,
        enabled: true,
        isNewInstallation: true,
      );
      expect(updated.appSettingProps.autoRun, isTrue);
    },
  );
}
