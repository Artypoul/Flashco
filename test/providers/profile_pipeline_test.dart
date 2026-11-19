import 'dart:convert';
import 'dart:io';

import 'package:flashco/common/common.dart';
import 'package:flashco/core/controller.dart';
import 'package:flashco/core/interface.dart';
import 'package:flashco/enum/enum.dart';
import 'package:flashco/models/models.dart';
import 'package:flashco/providers/action.dart';
import 'package:flashco/providers/core.dart';
import 'package:flashco/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod/riverpod.dart';
import 'package:yaml/yaml.dart';

import '../helpers/app_paths.dart';

class _Core extends Mock implements CoreHandlerInterface {}

const _fallback = FallbackConfig(
  selector: 'PROXY',
  name: 'Fallback',
  url: 'https://probe.example.invalid/check',
  interval: 10,
  timeout: 3000,
  lazy: false,
  expectedStatus: '204',
);

const _node = <String, dynamic>{
  'name': 'edge',
  'type': 'vless',
  'server': 'example.invalid',
  'port': 443,
  'uuid': '2a70e3a9-b4ce-4f20-908d-e99950a0a611',
  'tls': true,
  'reality-opts': {
    'public-key': 'SbVKOEMjK0sIlbwg4akyBg5mL5KZwwB-ed4eEE7YnRc',
    'short-id': '000123',
  },
};

Map<String, dynamic> _source() => {
  'proxies': [
    Map<String, dynamic>.from(_node),
    {..._node, 'name': 'second'},
  ],
  'proxy-groups': [
    {
      'name': 'PROXY',
      'type': 'select',
      'proxies': ['edge', 'second'],
    },
  ],
  'rule': ['DOMAIN,example.invalid,DIRECT', 'MATCH,PROXY'],
};

const _state = SetupState(
  profileId: 42,
  profileLastUpdateDate: null,
  profileType: ProfileType.file,
  extendType: ExtendType.standard,
  rules: [],
  proxyGroups: [],
  addedRules: [],
  script: null,
  overrides: ProfileOverrides(),
);

void _expectReality(Map proxy) {
  expect(proxy['name'], 'edge');
  expect(
    proxy['reality-opts']['public-key'],
    _node['reality-opts']['public-key'],
  );
  expect(
    proxy['reality-opts']['support-x25519mlkem768'],
    realitySupportX25519Mlkem768 ? isTrue : isNull,
  );
  expect(
    proxy['client-fingerprint'],
    realitySupportX25519Mlkem768 ? 'chrome' : null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Core core;
  late ProviderContainer container;
  late SetupAction action;
  late File sourceFile;
  late String originalSource;
  late ScriptEvaluator originalEvaluator;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('profile_pipeline_test');
    await useAppPaths(root);
    globalState.packageInfo = PackageInfo(
      appName: 'Flashco',
      packageName: 'com.follow.flashco',
      version: '0.0.0',
      buildNumber: '0',
    );
    originalSource = jsonEncode(_source());
    sourceFile = File(await appPath.getProfilePath('42'));
    await sourceFile.parent.create(recursive: true);
    await sourceFile.writeAsString(originalSource);
    core = _Core();
    when(() => core.readConfig(any())).thenAnswer(
      (_) async => jsonDecode(originalSource) as Map<String, dynamic>,
    );
    when(() => core.getProfileBase(any())).thenAnswer(
      (_) async => const ProfileBase(
        config: {'mixed-port': 7890},
        digest: 'source-digest',
        proxies: 2,
        proxyGroups: 1,
        rules: 2,
      ),
    );
    container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        setupActionProvider.overrideWith(SetupAction.new),
      ],
    );
    action = container.read(setupActionProvider.notifier);
    originalEvaluator = scriptEvaluator;
  });

  tearDown(() async {
    scriptEvaluator = originalEvaluator;
    container.dispose();
    await root.delete(recursive: true);
  });

  Future<BuiltProfile> build(SetupState state) => action.getProfile(
    setupState: state,
    patchConfig: const PatchClashConfig(),
  );

  void expectFastOrFull(BuiltProfile result) {
    if (realitySupportX25519Mlkem768) {
      verify(() => core.readConfig(any())).called(1);
      verifyNever(() => core.getProfileBase(any()));
      expect(result.base, isNull);
      _expectReality((loadYaml(result.yaml) as YamlMap)['proxies'][0] as Map);
    } else {
      verify(() => core.getProfileBase(any())).called(1);
      verifyNever(() => core.readConfig(any()));
      expect(result.base?.path, sourceFile.path);
      expect(result.base?.overlay, result.yaml);
      expect(result.counts.proxies, 2);
    }
  }

  test('no profile returns an empty result without reading Core', () async {
    final result = await build(_state.copyWith(profileId: null));
    expect(result.yaml, isEmpty);
    expect(result.md5, isEmpty);
    expect(result.base, isNull);
    verifyZeroInteractions(core);
  });

  test('ordinary file takes the correct path for the build define', () async {
    final result = await build(_state);
    expectFastOrFull(result);
    expect(await sourceFile.readAsString(), originalSource);
  });

  test(
    'saved fallback reads the full profile and preserves the source',
    () async {
      final result = await build(
        _state.copyWith(overrides: const ProfileOverrides(fallback: _fallback)),
      );
      verify(() => core.readConfig(any())).called(1);
      verifyNever(() => core.getProfileBase(any()));
      expect(result.base, isNull);
      final config = loadYaml(result.yaml) as YamlMap;
      final groups = config['proxy-groups'] as YamlList;
      final selector = groups.firstWhere((group) => group['name'] == 'PROXY');
      final fallback = groups.firstWhere(
        (group) => group['name'] == 'Fallback',
      );
      expect(selector['proxies'], ['Fallback', 'edge', 'second']);
      expect(fallback['proxies'], ['edge', 'second']);
      expect(fallback['type'], 'fallback');
      expect(fallback['empty-fallback'], 'REJECT');
      expect(fallback['url'], _fallback.url);
      expect(fallback['interval'], 10);
      expect(fallback['timeout'], 3000);
      expect(fallback['lazy'], isFalse);
      expect(fallback['expected-status'], '204');
      expect(config['rules'], ['DOMAIN,example.invalid,DIRECT', 'MATCH,PROXY']);
      _expectReality(config['proxies'][0] as Map);
      expect(await sourceFile.readAsString(), originalSource);
    },
  );

  test(
    'script uses full profile, skips fallback and applies final defaults',
    () async {
      var calls = 0;
      scriptEvaluator = ({required script, required config}) async {
        calls++;
        expect(script, 'pipeline-script');
        final decoded = jsonDecode(config) as Map<String, dynamic>;
        decoded['proxies'] = [Map<String, dynamic>.from(_node)];
        decoded['rule'] = ['MATCH,DIRECT'];
        decoded['rules'] = ['MATCH,DIRECT'];
        return jsonEncode(decoded);
      };
      final script = await Script(
        id: 91,
        label: 'pipeline',
        lastUpdateTime: DateTime(2026),
      ).save('pipeline-script');
      final result = await build(
        _state.copyWith(
          extendType: ExtendType.script,
          script: script,
          overrides: const ProfileOverrides(fallback: _fallback),
        ),
      );
      expect(calls, 1);
      verify(() => core.readConfig(any())).called(1);
      verifyNever(() => core.getProfileBase(any()));
      expect(result.base, isNull);
      final config = loadYaml(result.yaml) as YamlMap;
      expect(
        (config['proxy-groups'] as YamlList).any(
          (g) => g['name'] == 'Fallback',
        ),
        isFalse,
      );
      expect(config['rules'], ['MATCH,DIRECT']);
      _expectReality(config['proxies'][0] as Map);
      expect(await sourceFile.readAsString(), originalSource);
    },
  );

  test('empty script follows the ordinary file path', () async {
    var calls = 0;
    scriptEvaluator = ({required script, required config}) async {
      calls++;
      return config;
    };
    final script = await Script(
      id: 92,
      label: 'empty',
      lastUpdateTime: DateTime(2026),
    ).save('');
    final result = await build(
      _state.copyWith(extendType: ExtendType.script, script: script),
    );
    expect(calls, 0);
    expectFastOrFull(result);
  });

  test('custom profile includes only named proxies and providers', () async {
    final result = await build(
      _state.copyWith(
        profileType: ProfileType.custom,
        proxyGroups: const [
          ProxyGroup(
            id: 1,
            name: 'PROXY',
            type: GroupType.Selector,
            proxies: ['edge'],
            use: ['sub'],
          ),
        ],
        appProxies: const [
          CustomProxy(id: 11, definition: _node),
          CustomProxy(id: 12, definition: {'name': 'unused', 'type': 'direct'}),
        ],
        profileProviders: const {'sub': 42, 'unused': 43},
        rules: [Rule.parse('MATCH,PROXY')],
      ),
    );
    verifyNever(() => core.readConfig(any()));
    verifyNever(() => core.getProfileBase(any()));
    expect(result.base, isNull);
    final config = loadYaml(result.yaml) as YamlMap;
    expect((config['proxies'] as YamlList), hasLength(1));
    _expectReality(config['proxies'][0] as Map);
    expect((config['proxy-providers'] as YamlMap).keys, {'sub'});
    expect(config['proxy-providers']['sub']['path'], sourceFile.path);
  });

  test('DIRECT-only file without fallback remains valid', () async {
    when(() => core.readConfig(any())).thenAnswer(
      (_) async => {
        'proxies': <Object>[],
        'proxy-groups': <Object>[],
        'rule': ['MATCH,DIRECT'],
      },
    );
    when(() => core.getProfileBase(any())).thenAnswer(
      (_) async => const ProfileBase(config: {}, digest: 'direct-only'),
    );
    final result = await build(_state);
    expect(result.yaml, isNotEmpty);
    if (realitySupportX25519Mlkem768) {
      verify(() => core.readConfig(any())).called(1);
      verifyNever(() => core.getProfileBase(any()));
      expect((loadYaml(result.yaml) as YamlMap)['rules'], ['MATCH,DIRECT']);
    } else {
      verify(() => core.getProfileBase(any())).called(1);
      verifyNever(() => core.readConfig(any()));
      expect(result.base, isNotNull);
    }
  });
}
