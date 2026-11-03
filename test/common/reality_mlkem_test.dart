import 'dart:convert';

import 'package:flashco/common/reality_mlkem.dart';
import 'package:flashco/common/task.dart';
import 'package:flashco/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

Map<String, dynamic> proxy({String name = 'First', int port = 443}) => {
  'name': name,
  'type': 'vless',
  'server': 'node.example',
  'port': port,
  'network': 'xhttp',
  'servername': 'cover.example',
  'reality-opts': <String, dynamic>{
    'public-key': 'test-public-key',
    'short-id': '01',
  },
};

void main() {
  test(
    'persisted global, profile and node settings determine the runtime value',
    () async {
      final cases = [
        (global: true, profile: null, node: null, expected: true),
        (global: false, profile: null, node: null, expected: false),
        (global: false, profile: true, node: null, expected: true),
        (global: true, profile: false, node: null, expected: false),
        (global: false, profile: false, node: true, expected: true),
        (global: true, profile: true, node: false, expected: false),
      ];
      for (final value in cases) {
        final item = proxy();
        final global = Config.fromJson(
          jsonDecode(
            jsonEncode(
              Config(
                themeProps: const ThemeProps(),
                patchClashConfig: PatchClashConfig(
                  realityMlkemEnabled: value.global,
                ),
              ),
            ),
          ),
        ).patchClashConfig;
        final saved = ProfileOverrides.fromJson(
          jsonDecode(
            jsonEncode(
              ProfileOverrides(
                realityMlkemEnabled: value.profile,
                realityMlkem: {
                  if (value.node != null) realityMlkemKey(item)!: value.node!,
                },
              ),
            ),
          ),
        );
        expect(global.realityMlkemEnabled, value.global);
        expect(global.setupOnly.realityMlkemEnabled, value.global);
        expect(saved.realityMlkemEnabled, value.profile);
        final result = await makeRealProfileTask(
          MakeRealProfileState(
            profilesPath: '/profiles',
            profileId: 1,
            rawConfig: {
              'proxies': [item],
            },
            realPatchConfig: global,
            overrides: saved,
            appendSystemDns: false,
            proxyGroups: const [],
            rules: const [],
            addedRules: const [],
            defaultUA: 'test',
          ),
        );
        final working = loadYaml(result.yaml) as Map;
        expect(
          working['proxies'][0]['reality-opts']['support-x25519mlkem768'],
          value.expected,
        );
      }
      expect(const PatchClashConfig().realityMlkemEnabled, true);
      expect(PatchClashConfig.fromJson({}).realityMlkemEnabled, true);
      expect(ProfileOverrides.fromJson({}).realityMlkemEnabled, isNull);
    },
  );

  for (final network in ['xhttp', 'grpc']) {
    test(
      '$network enables ML-KEM without setup on every subscription refresh',
      () async {
        for (final subscriptionValue in [null, false, true]) {
          final item = proxy(name: 'Refreshed $subscriptionValue');
          item['network'] = network;
          if (subscriptionValue != null) {
            (item['reality-opts'] as Map)['support-x25519mlkem768'] =
                subscriptionValue;
          }
          final saved = ProfileOverrides.fromJson(
            jsonDecode(jsonEncode(const ProfileOverrides())),
          );
          final result = await makeRealProfileTask(
            MakeRealProfileState(
              profilesPath: '/profiles',
              profileId: 1,
              rawConfig: {
                'proxies': [item],
              },
              realPatchConfig: const PatchClashConfig(),
              overrides: saved,
              appendSystemDns: false,
              proxyGroups: const [],
              rules: const [],
              addedRules: const [],
              defaultUA: 'test',
            ),
          );
          final config = loadYaml(result.yaml) as YamlMap;
          expect(
            config['proxies'][0]['reality-opts']['support-x25519mlkem768'],
            true,
          );
        }
      },
    );
  }

  test(
    'the final runtime YAML reapplies the saved selection after refresh',
    () async {
      final item = proxy(name: 'Refreshed');
      final result = await makeRealProfileTask(
        MakeRealProfileState(
          profilesPath: '/profiles',
          profileId: 1,
          rawConfig: {
            'proxies': [item],
          },
          realPatchConfig: const PatchClashConfig(),
          overrides: ProfileOverrides(
            realityMlkem: {realityMlkemKey(item)!: true},
          ),
          appendSystemDns: false,
          proxyGroups: const [],
          rules: const [],
          addedRules: const [],
          defaultUA: 'test',
        ),
      );
      final config = loadYaml(result.yaml) as YamlMap;
      expect(
        config['proxies'][0]['reality-opts']['support-x25519mlkem768'],
        true,
      );
    },
  );

  test('a saved node override survives a renamed subscription proxy', () {
    final original = proxy();
    final key = realityMlkemKey(original)!;
    final saved = ProfileOverrides.fromJson(
      jsonDecode(jsonEncode(ProfileOverrides(realityMlkem: {key: true}))),
    );
    final refreshed = proxy(name: 'Renamed');
    final raw = <String, dynamic>{
      'proxies': [refreshed, proxy(port: 8443)],
    };
    applyRealityMlkemOverrides(
      raw,
      saved.realityMlkem,
      enabledByDefault: const PatchClashConfig().realityMlkemEnabled,
    );

    final items = raw['proxies']!;
    expect(
      items[0]['reality-opts'],
      containsPair('support-x25519mlkem768', true),
    );
    expect(
      items[1]['reality-opts'],
      containsPair('support-x25519mlkem768', true),
    );
    expect(
      refreshed['reality-opts'],
      isNot(contains('support-x25519mlkem768')),
    );
  });

  test(
    'explicitly disabling overrides the default and survives serialization',
    () {
      final item = proxy();
      (item['reality-opts'] as Map)['support-x25519mlkem768'] = true;
      final raw = <String, dynamic>{
        'proxies': [item],
      };
      final saved = ProfileOverrides.fromJson(
        jsonDecode(
          jsonEncode(
            ProfileOverrides(realityMlkem: {realityMlkemKey(item)!: false}),
          ),
        ),
      );
      applyRealityMlkemOverrides(
        raw,
        saved.realityMlkem,
        enabledByDefault: const PatchClashConfig().realityMlkemEnabled,
      );
      expect(
        raw['proxies']![0]['reality-opts'],
        containsPair('support-x25519mlkem768', false),
      );
      final following = <String, dynamic>{
        'proxies': [item],
      };
      applyRealityMlkemOverrides(
        following,
        {},
        enabledByDefault: const PatchClashConfig().realityMlkemEnabled,
      );
      expect(
        following['proxies']![0]['reality-opts'],
        containsPair('support-x25519mlkem768', true),
      );
    },
  );

  test(
    'inline providers use the same node choices without changing the source',
    () {
      final item = proxy();
      final raw = <String, dynamic>{
        'proxy-providers': {
          'inline': {
            'type': 'inline',
            'payload': [item],
          },
          'remote': {'type': 'http', 'url': 'https://example.com/proxies'},
        },
      };
      expect(realityMlkemNodes(raw).single.name, 'First');
      applyRealityMlkemOverrides(raw, {
        realityMlkemKey(item)!: true,
      }, enabledByDefault: false);
      final providers = raw['proxy-providers'] as Map;
      expect(
        providers['inline']['payload'][0]['reality-opts'],
        containsPair('support-x25519mlkem768', true),
      );
      expect(providers['remote'], {
        'type': 'http',
        'url': 'https://example.com/proxies',
      });
      expect(item['reality-opts'], isNot(contains('support-x25519mlkem768')));
    },
  );

  test('ordinary TLS and malformed definitions are left alone', () {
    final ordinary = {
      'name': 'TLS',
      'server': 'node.example',
      'port': 443,
      'tls': true,
    };
    expect(realityMlkemKey(ordinary), isNull);
    expect(realityMlkemKey({'reality-opts': {}}), isNull);
    expect(
      realityMlkemNodes({
        'proxies': [ordinary, 'invalid', null],
      }),
      isEmpty,
    );
  });
}
