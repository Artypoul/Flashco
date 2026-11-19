import 'dart:convert';

import 'package:flashco/common/migration.dart';
import 'package:flashco/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';

void main() {
  group('Migration', () {
    test(
      'upgrading cleans inherited bypass rules once and preserves later edits',
      () async {
        final configMap = _createConfigMap();
        (configMap['networkProps']! as Map<String, Object?>)['bypassDomain'] = [
          '*zhihu.com',
          '*zhimg.com',
          '*jd.com',
          '100ime-iat-api.xfyun.cn',
          '*360buyimg.com',
          'localhost',
          '*.example.org',
        ];
        final store = _FakeMigrationStore(configMap: configMap, version: 1);

        final upgraded = await Migration(store: store).run();

        expect(upgraded.networkProps.bypassDomain, [
          'localhost',
          '*.example.org',
        ]);
        expect(store.savedConfig, upgraded);
        expect(store.version, Migration.currentVersion);
        expect(store.restoredData?.profiles, isEmpty);
        final edited = upgraded.copyWith(
          networkProps: upgraded.networkProps.copyWith(
            bypassDomain: ['localhost', '*.example.org', '*jd.com'],
          ),
        );
        final nextStore = _FakeMigrationStore(
          configMap: jsonDecode(jsonEncode(edited)) as Map<String, Object?>,
          version: store.version,
        );

        final reloaded = await Migration(store: nextStore).run();

        expect(reloaded.networkProps.bypassDomain, [
          'localhost',
          '*.example.org',
          '*jd.com',
        ]);
        expect(nextStore.savedConfig, isNull);
      },
    );

    test('a failed bypass upgrade does not advance the version', () async {
      final store = _FakeMigrationStore(
        configMap: _createConfigMap(),
        version: 1,
        configSaveResult: false,
      );

      await expectLater(Migration(store: store).run(), throwsStateError);

      expect(store.version, 1);
      expect(store.events, isNot(contains('setVersion')));
    });

    test(
      'persists TUN defaults for a new installation with API closed',
      () async {
        final store = _FakeMigrationStore(configMap: null, version: 0);

        final config = await Migration(
          store: store,
        ).run(isNewInstallation: true);

        expect(config.patchClashConfig.tun.enable, isTrue);
        expect(config.patchClashConfig.tun.autoRoute, isTrue);
        expect(config.patchClashConfig.externalController.name, 'close');
        expect(config.patchClashConfig.secret, isEmpty);
        expect(store.savedConfig, config);
        expect(store.version, Migration.currentVersion);
      },
    );

    test('preserves a saved choice to disable TUN', () async {
      final configMap = _createConfigMap();
      final store = _FakeMigrationStore(
        configMap: configMap,
        version: Migration.currentVersion,
      );

      final config = await Migration(store: store).run();

      expect(config.patchClashConfig.tun.enable, isFalse);
      expect(config.patchClashConfig.tun.autoRoute, isFalse);
      expect(store.savedConfig, isNull);
    });

    test(
      'does not enable TUN when recovering missing existing settings',
      () async {
        final store = _FakeMigrationStore(
          configMap: null,
          version: Migration.currentVersion,
        );

        final config = await Migration(store: store).run();

        expect(config.patchClashConfig.tun.enable, isFalse);
        expect(config.patchClashConfig.tun.autoRoute, isFalse);
        expect(store.savedConfig, isNull);
      },
    );

    test('returns current config without rewriting storage', () async {
      final configMap = _createConfigMap(
        davProps: const DAVProps(
          uri: 'https://example.com/dav',
          user: 'user',
          password: 'secret',
        ),
      );
      final store = _FakeMigrationStore(
        configMap: configMap,
        version: Migration.currentVersion,
      );

      final config = await Migration(store: store).run();

      expect(config, Config.realFromJson(configMap));
      expect(config.davProps?.password, 'secret');
      expect(store.events, ['getConfigMap', 'getVersion']);
    });

    test(
      'obfuscates a compatible DAV password without a version migration',
      () async {
        final configMap = _createConfigMap(
          davProps: const DAVProps(
            uri: 'https://example.com/dav',
            user: 'user',
          ),
        );
        final davProps = configMap['davProps']! as Map<String, Object?>;
        davProps['password'] = 'secret';
        final store = _FakeMigrationStore(
          configMap: configMap,
          version: Migration.currentVersion,
        );

        final config = await Migration(store: store).run();

        expect(config.davProps?.user, 'user');
        expect(config.davProps?.password, 'secret');
        expect(store.savedConfig, config);
        expect(store.version, Migration.currentVersion);
        expect(store.events, ['getConfigMap', 'getVersion', 'saveConfig']);
        final savedConfigMap =
            jsonDecode(jsonEncode(store.savedConfig)) as Map<String, Object?>;
        final savedDavProps =
            savedConfigMap['davProps']! as Map<String, Object?>;
        expect(savedDavProps['password'], startsWith('v1.'));
        expect(savedDavProps['password'], isNot(contains('secret')));
      },
    );

    test(
      'commits v0 cleanup and version only after migrated data is saved',
      () async {
        final configMap = <String, Object?>{
          'proxiesStyle': <String, Object?>{},
          'dav': <String, Object?>{
            'uri': 'https://example.com/dav',
            'user': 'user',
            'password': 'secret',
          },
        };
        final store = _FakeMigrationStore(
          configMap: configMap,
          version: 0,
          clashConfigMap: <String, Object?>{'mixed-port': 7890},
        );
        final migration = Migration(
          store: store,
          migrateV0: (configMap) async {
            store.events.add('migrateV0');
            expect(configMap['patchClashConfig'], store.clashConfigMap);
            return MigrationData(
              configMap: _createConfigMap(
                davProps: const DAVProps(
                  uri: 'https://example.com/dav',
                  user: 'user',
                  password: 'secret',
                ),
              ),
            );
          },
        );

        await migration.run();

        expect(store.events, [
          'getConfigMap',
          'getVersion',
          'getClashConfigMap',
          'migrateV0',
          'restore',
          'saveConfig',
          'clearClashConfig',
          'setVersion',
        ]);
        expect(store.savedConfig?.davProps?.password, 'secret');
        expect(store.didClearClashConfig, isTrue);
        expect(store.version, Migration.currentVersion);
      },
    );

    test(
      'preserves legacy clash config when current-shaped data has version zero',
      () async {
        final configMap = _createConfigMap()..remove('patchClashConfig');
        final clashConfigMap = _createClashConfigMap(mixedPort: 1234);
        final store = _FakeMigrationStore(
          configMap: configMap,
          version: 0,
          clashConfigMap: clashConfigMap,
        );

        final config = await Migration(store: store).run();

        expect(config.patchClashConfig.mixedPort, 1234);
        expect(store.savedConfig?.patchClashConfig.mixedPort, 1234);
        expect(store.didClearClashConfig, isTrue);
        expect(store.events, [
          'getConfigMap',
          'getVersion',
          'getClashConfigMap',
          'restore',
          'saveConfig',
          'clearClashConfig',
          'setVersion',
        ]);
      },
    );

    test('does not clear legacy clash config when saving fails', () async {
      final configMap = _createConfigMap()..remove('patchClashConfig');
      final store = _FakeMigrationStore(
        configMap: configMap,
        version: 0,
        clashConfigMap: _createClashConfigMap(mixedPort: 1234),
        configSaveResult: false,
      );

      await expectLater(
        Migration(store: store).run(),
        throwsA(isA<StateError>()),
      );

      expect(store.didClearClashConfig, isFalse);
      expect(store.version, 0);
      expect(store.events, [
        'getConfigMap',
        'getVersion',
        'getClashConfigMap',
        'restore',
        'saveConfig',
        'isAvailable',
      ]);
    });

    test('starts with defaults when the store cannot be opened', () async {
      final store = _FakeMigrationStore(
        configMap: null,
        version: 0,
        configSaveResult: false,
        available: false,
      );

      final config = await Migration(store: store).run();

      expect(config, isNotNull);
      expect(store.didClearClashConfig, isFalse);
      expect(store.version, 0);
      expect(store.events, [
        'getConfigMap',
        'getVersion',
        'getClashConfigMap',
        'restore',
        'saveConfig',
        'isAvailable',
      ]);
    });

    group('Flashco theme upgrade policy', () {
      for (final marker in [0, 1, 4, 99]) {
        test('preserves saved choices with donor marker $marker', () async {
          final configMap = _createConfigMap();
          (configMap['themeProps']! as Map<String, Object?>)
            ..['primaryColor'] = 0xFF123456
            ..['primaryColors'] = [0xFF795548, 0xFF123456]
            ..['themeMode'] = 'dark'
            ..['sidebarBlur'] = true;
          final store = _FakeMigrationStore(
            configMap: configMap,
            version: Migration.currentVersion,
            upgradeVersion: marker,
          );
          final config = await Migration(store: store).run();
          expect(config.themeProps.primaryColor, 0xFF123456);
          expect(config.themeProps.primaryColors, [0xFF795548, 0xFF123456]);
          expect(config.themeProps.themeMode, ThemeMode.dark);
          expect(config.themeProps.sidebarBlur, isTrue);
          expect(store.upgradeVersion, marker);
          expect(store.events, ['getConfigMap', 'getVersion']);
        });
      }

      test('preserves an explicitly disabled sidebar blur', () async {
        final configMap = _createConfigMap();
        (configMap['themeProps']! as Map<String, Object?>)['sidebarBlur'] =
            false;
        final store = _FakeMigrationStore(
          configMap: configMap,
          version: Migration.currentVersion,
        );
        final config = await Migration(store: store).run();
        expect(config.themeProps.sidebarBlur, isFalse);
        expect(store.events, ['getConfigMap', 'getVersion']);
      });
    });

    test('keeps what it can read of a damaged current config', () async {
      final configMap = _createConfigMap()
        ..['currentProfileId'] = 7
        ..['excludeSSIDs'] = 'home';
      final store = _FakeMigrationStore(
        configMap: configMap,
        version: Migration.currentVersion,
      );

      final config = await Migration(store: store).run();

      expect(config.currentProfileId, 7);
      expect(config.excludeSSIDs, isEmpty);
      expect(store.events, ['getConfigMap', 'getVersion']);
    });

    test('keeps the current version when password obfuscation fails', () async {
      final configMap = _createConfigMap(
        davProps: const DAVProps(uri: 'https://example.com/dav', user: 'user'),
      );
      final davProps = configMap['davProps']! as Map<String, Object?>;
      davProps['password'] = 'secret';
      final store = _FakeMigrationStore(
        configMap: configMap,
        version: Migration.currentVersion,
        configSaveResult: false,
      );

      await expectLater(
        Migration(store: store).run(),
        throwsA(isA<StateError>()),
      );

      expect(store.events, ['getConfigMap', 'getVersion', 'saveConfig']);
      expect(store.version, Migration.currentVersion);
    });
  });
}

Map<String, Object?> _createConfigMap({DAVProps? davProps}) {
  return jsonDecode(
        jsonEncode(Config(themeProps: defaultThemeProps, davProps: davProps)),
      )
      as Map<String, Object?>;
}

Map<String, Object?> _createClashConfigMap({required int mixedPort}) {
  return jsonDecode(jsonEncode(PatchClashConfig(mixedPort: mixedPort)))
      as Map<String, Object?>;
}

class _FakeMigrationStore implements MigrationStore {
  final Map<String, Object?>? configMap;
  final Map<String, Object?>? clashConfigMap;
  final bool configSaveResult;
  final bool available;
  final List<String> events = [];

  int version;
  int upgradeVersion;
  Config? savedConfig;
  MigrationData? restoredData;
  bool didClearClashConfig = false;

  _FakeMigrationStore({
    required this.configMap,
    required this.version,
    this.upgradeVersion = 0,
    this.clashConfigMap,
    this.configSaveResult = true,
    this.available = true,
  });

  @override
  Future<bool> get isAvailable async {
    events.add('isAvailable');
    return available;
  }

  @override
  Future<void> clearClashConfig() async {
    events.add('clearClashConfig');
    didClearClashConfig = true;
  }

  @override
  Future<Map<String, Object?>?> getClashConfigMap() async {
    events.add('getClashConfigMap');
    return clashConfigMap;
  }

  @override
  Future<Map<String, Object?>?> getConfigMap() async {
    events.add('getConfigMap');
    return configMap;
  }

  @override
  Future<int> getVersion() async {
    events.add('getVersion');
    return version;
  }

  @override
  Future<void> restore(MigrationData data) async {
    events.add('restore');
    restoredData = data;
  }

  @override
  Future<bool> saveConfig(Config config) async {
    events.add('saveConfig');
    savedConfig = config;
    return configSaveResult;
  }

  @override
  Future<void> setVersion(int version) async {
    events.add('setVersion');
    this.version = version;
  }
}
