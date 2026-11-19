import 'dart:io';

import 'package:drift/native.dart';
import 'package:flashco/common/personal_defaults.dart';
import 'package:flashco/common/preferences.dart';
import 'package:flashco/core/controller.dart';
import 'package:flashco/core/interface.dart';
import 'package:flashco/database/database.dart' as db;
import 'package:flashco/enum/enum.dart';
import 'package:flashco/models/models.dart';
import 'package:flashco/providers/providers.dart';
import 'package:flashco/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';

import '../helpers/app_paths.dart';
import '../helpers/test_profiles.dart';

class _Core extends Mock implements CoreHandlerInterface {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  late Directory home;
  late db.Database database;
  late _Core core;

  setUp(() async {
    await (await SharedPreferences.getInstance()).clear();
    home = await Directory.systemTemp.createTemp('personal-pipeline-');
    await useAppPaths(home);
    database = db.Database(NativeDatabase.memory());
    db.database = database;
    core = _Core();
    globalState.packageInfo = PackageInfo(
      appName: 'Flashco',
      packageName: 'com.follow.flashco',
      version: '0.0.0',
      buildNumber: '0',
    );
  });

  tearDown(() async {
    await database.close();
    await home.delete(recursive: true);
  });

  Future<({YamlMap yaml, SetupState state, bool autoLaunch})> build(
    Config config, {
    bool? sourceStrictRoute,
  }) async {
    const profile = Profile(
      id: 42,
      label: 'Subscription',
      type: ProfileType.url,
      url: 'https://example.invalid/sub',
      autoUpdateDuration: Duration.zero,
    );
    final raw = <String, dynamic>{
      'tun': <String, dynamic>{'strict-route': ?sourceStrictRoute},
    };
    when(
      () => core.getProfileBase(any()),
    ).thenAnswer((_) async => ProfileBase(config: raw, digest: 'source'));
    when(() => core.readConfig(any())).thenAnswer((_) async => raw);
    final container = ProviderContainer(
      overrides: [
        ...buildConfigOverrides(config),
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    addTearDown(container.dispose);
    final hold = container.listen(setupStateProvider(profile.id), (_, _) {});
    addTearDown(hold.close);
    final state = await container.read(setupStateProvider(profile.id).future);
    final result = await container
        .read(setupActionProvider.notifier)
        .getProfile(
          setupState: state,
          patchConfig: container.read(patchClashConfigProvider),
        );
    return (
      yaml: loadYaml(result.yaml) as YamlMap,
      state: state,
      autoLaunch: container.read(appSettingProvider).autoLaunch,
    );
  }

  for (final firstRun in [false, true]) {
    for (final sourceStrict in [null, false]) {
      test('fresh ${firstRun ? 'first-run' : 'embedded'} defaults enforce '
          'strict routing with source $sourceStrict', () async {
        final defaults = await initializePersonalDefaults(
          const Config(themeProps: ThemeProps()),
          subscriptionUrl: firstRun ? '' : 'https://example.invalid/sub',
          enabled: true,
          isNewInstallation: true,
          subscriptionOnFirstRun: firstRun,
        );
        final saved = (await preferences.getConfig())!;
        expect(saved, defaults);
        final built = await build(saved, sourceStrictRoute: sourceStrict);
        expect(
          built.state.overrides.tunOverrideKeys,
          contains(TunOverrideKey.strictRoute),
        );
        expect((built.yaml['tun'] as YamlMap)['strict-route'], isTrue);
        expect(built.autoLaunch, isTrue);
        expect(saved.appSettingProps.autoRun, isTrue);
        expect(saved.patchClashConfig.tun.strictRoute, isTrue);
      });
    }
  }

  test(
    'an existing disabled choice survives defaults and final YAML',
    () async {
      final old = Config.realFromJson({
        'appSettingProps': {'autoLaunch': false, 'autoRun': false},
        'patchClashConfig': {
          'tun': {'strict-route': false},
        },
      });
      await preferences.saveConfig(old);
      final retained = await initializePersonalDefaults(
        old,
        subscriptionUrl: 'https://example.invalid/sub',
        enabled: true,
        isNewInstallation: false,
      );
      final built = await build(retained, sourceStrictRoute: true);
      expect(built.autoLaunch, isFalse);
      expect(retained.appSettingProps.autoRun, isFalse);
      expect((built.yaml['tun'] as YamlMap)['strict-route'], isFalse);
    },
  );
}
